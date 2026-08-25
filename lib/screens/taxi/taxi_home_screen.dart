import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import 'package:nomade_client/constants.dart';
import 'package:nomade_client/theme/app_colors.dart';
import 'package:nomade_client/translations/app_translations.dart';
import 'package:nomade_client/models/place.dart';
import 'package:nomade_client/models/ride_choice.dart';
import 'package:nomade_client/models/trip_details.dart';
import 'package:nomade_client/providers/all_providers.dart';
import 'package:nomade_client/services/location_service.dart';
import 'destination_picker_screen.dart';
import 'ride_confirmation_screen.dart';
import 'components/ride/ride_choice_card.dart';

// ─────────────────────────────────────────────────────────────
// TaxiHomeScreen — 2 états :
//
//  1. IDLE : carte GPS, pickup localisé, bouton "Choisir une destination"
//     → DestinationPickerScreen (retourne Place via pop)
//
//  2. AVEC DESTINATION : RouteMapView intégrée, sélecteur véhicule horizontal
//     avec prix calculés, bouton "Confirmer la course"
//     → RideConfirmationScreen → TrackingScreen
// ─────────────────────────────────────────────────────────────

class TaxiHomeScreen extends ConsumerStatefulWidget {
  const TaxiHomeScreen({super.key});

  @override
  ConsumerState<TaxiHomeScreen> createState() => _TaxiHomeScreenState();
}

class _TaxiHomeScreenState extends ConsumerState<TaxiHomeScreen>
    with TickerProviderStateMixin, RestorationMixin, WidgetsBindingObserver {

  // ── Carte ────────────────────────────────────────────────
  final MapController _mapController = MapController();
  static const LatLng _djiboutiCenter = LatLng(11.5892, 43.1456);

  // ── Animation pulse marker GPS ───────────────────────────
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // ── ÉTAT PICKUP ───────────────────────────────────────────
  bool _isAdjustingPickup = false;
  LatLng? _pickupLatLng;
  // RestorableStringN : restauré par l'OS si l'app est tuée en background
  final RestorableStringN _restorablePickupAddress = RestorableStringN(null);
  bool _isLoadingPickup = false;

  // ── ÉTAT DESTINATION ──────────────────────────────────────
  Place? _destination; // null = état idle
  // Restaure uniquement le nom de destination (pour affichage UX)
  final RestorableStringN _restorableDestinationName = RestorableStringN(null);

  // ── VÉHICULE SÉLECTIONNÉ ──────────────────────────────────
  /// Véhicule sélectionné, mémorisé par ID et non par instance : le catalogue
  /// est rechargé dès que l'admin change les tarifs dans `config/taxiPricing`,
  /// et garder l'ancienne instance afficherait un prix périmé.
  String? _selectedRideId;

  RideChoice get _selectedRide {
    final choices = ref.read(rideChoicesProvider);
    return choices.firstWhere(
      (r) => r.id == _selectedRideId,
      orElse: () => choices.first,
    );
  }

  // ── DISTANCE / DURÉE ─────────────────────────────────────
  double _distanceKm = 0;
  int _durationMin = 0;
  bool _isComputingRoute = false;

  /// Géométrie routière renvoyée par `getRoute`, utilisée pour DESSINER le
  /// trajet. Vide tant que l'itinéraire n'est pas calculé (ou si l'API a
  /// échoué) : on retombe alors sur la droite pickup → destination.
  List<LatLng> _routePoints = const [];
  // Incrémenté à chaque nouvelle destination : une réponse getRoute tardive
  // portant un id périmé est ignorée (anti-écrasement par une course obsolète).
  int _routeRequestId = 0;

  // ── ÉCHEC GPS ─────────────────────────────────────────────
  // Non-null = on ne connaît pas la position réelle de l'utilisateur. On
  // bloque plutôt que de supposer un départ : une course partirait du mauvais
  // endroit et serait facturée depuis ce mauvais endroit.
  LocationFailure? _gpsFailure;

  // ── Services ──────────────────────────────────────────────
  final LocationService _locationService = LocationService();

  // ── Couleurs thème ────────────────────────────────────────
  late AppColors _c;

  // ── Getters raccourcis sur les champs restaurables ────────
  String? get _pickupAddress        => _restorablePickupAddress.value;
  set _pickupAddress(String? v)     => _restorablePickupAddress.value = v;

  // ════════════════════════════════════════════════════════════
  // RESTORATION
  // ════════════════════════════════════════════════════════════

  @override
  String get restorationId => 'taxi_home_screen';

  @override
  void restoreState(RestorationBucket? oldBucket, bool initialRestore) {
    registerForRestoration(_restorablePickupAddress,    'pickup_address');
    registerForRestoration(_restorableDestinationName,  'destination_name');
  }

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _initGps());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Retour depuis les réglages iOS : si on était bloqué faute de position,
    // on retente tout de suite pour que l'utilisateur n'ait rien à retaper.
    if (state == AppLifecycleState.resumed && _gpsFailure != null) {
      _initGps();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulseController.dispose();
    _mapController.dispose();
    _restorablePickupAddress.dispose();
    _restorableDestinationName.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────
  // GPS INIT
  // ─────────────────────────────────────────────────────────
  Future<void> _initGps() async {
    final locNotifier = ref.read(locationNotifierProvider.notifier);
    setState(() {
      _isLoadingPickup = true;
      _gpsFailure = null;
    });

    try {
      if (!ref.read(locationNotifierProvider).hasPosition) {
        // getCurrentLocation() n'émet pas : il stocke la cause dans l'état.
        await locNotifier.getCurrentLocation();
      }

      final locState = ref.read(locationNotifierProvider);
      final pos = locState.position;

      if (pos == null) {
        if (mounted) {
          setState(() {
            _gpsFailure = locState.failure ?? LocationFailure.unavailable;
            _isLoadingPickup = false;
          });
        }
        return;
      }

      if (!mounted) return;
      _pickupLatLng = pos;
      _mapController.move(pos, 15);

      final address = await _locationService.getAddressFromCoordinates(
        pos.latitude, pos.longitude,
      );
      if (mounted) setState(() { _pickupAddress = address; _isLoadingPickup = false; });
    } catch (e) {
      // La position est connue mais l'adresse lisible n'a pas pu être résolue :
      // ce n'est pas bloquant, on garde les coordonnées.
      debugPrint('❌ Adresse pickup: $e');
      if (mounted) {
        setState(() {
          _pickupAddress ??= 'Position actuelle';
          _isLoadingPickup = false;
        });
      }
    }
  }

  Future<void> _openLocationSettings() async {
    if (_gpsFailure == LocationFailure.permissionDeniedForever) {
      await _locationService.openAppSettings();
    } else {
      await _locationService.openLocationSettings();
    }
  }

  // ─────────────────────────────────────────────────────────
  // AJUSTEMENT MANUEL PICKUP
  // ─────────────────────────────────────────────────────────
  void _togglePickupAdjustment() {
    setState(() => _isAdjustingPickup = !_isAdjustingPickup);
    if (_isAdjustingPickup && _pickupLatLng != null) {
      _mapController.move(_pickupLatLng!, 16.0);
    }
  }

  Future<void> _onMapTap(LatLng latLng) async {
    // En mode idle uniquement (carte GPS), pas en mode route
    if (!_isAdjustingPickup || _destination != null) return;

    setState(() {
      _pickupLatLng = latLng;
      _pickupAddress = null;
      _isLoadingPickup = true;
      _isAdjustingPickup = false;
    });
    _mapController.move(latLng, 16);

    try {
      final address = await _locationService.getAddressFromCoordinates(
        latLng.latitude, latLng.longitude,
      );
      if (mounted) setState(() { _pickupAddress = address; _isLoadingPickup = false; });
    } catch (_) {
      if (mounted) {
        setState(() {
          _pickupAddress = '${latLng.latitude.toStringAsFixed(5)}, ${latLng.longitude.toStringAsFixed(5)}';
          _isLoadingPickup = false;
        });
      }
    }
  }

  // ─────────────────────────────────────────────────────────
  // NAVIGATION VERS DESTINATION PICKER
  // Retourne un Place? via pop
  // ─────────────────────────────────────────────────────────
  Future<void> _openDestinationPicker() async {
    if (_pickupLatLng == null) return;

    final pickupPlace = Place(
      id: 'pickup_current',
      name: _pickupAddress ?? tr('my_position'),
      location: _pickupLatLng!,
      address: _pickupAddress ?? tr('my_position'),
      type: PlaceType.saved,
      icon: Icons.my_location,
    );

    // DestinationPickerScreen retourne un Place? via Navigator.pop
    final Place? result = await Navigator.push<Place>(
      context,
      MaterialPageRoute(
        builder: (_) => DestinationPickerScreen(currentLocation: pickupPlace),
      ),
    );

    if (result != null && mounted) {
      await _setDestination(result);
    }
  }

  // ─────────────────────────────────────────────────────────
  // APPLIQUER LA DESTINATION → calcul distance + centrage carte
  // ─────────────────────────────────────────────────────────
  /// Le prix se calcule sur la distance ROUTIÈRE (OpenRouteService), pas à vol
  /// d'oiseau : en ville la route fait ~1,3× la ligne droite, ce qui sous-
  /// facturait toutes les courses d'autant.
  Future<void> _setDestination(Place dest) async {
    final pickup = _pickupLatLng;
    if (pickup == null) return;

    // Estimation immédiate à vol d'oiseau pour que l'écran réagisse tout de
    // suite ; elle est remplacée par la vraie distance dès la réponse réseau.
    final straight = _locationService.calculateDistance(
      pickup.latitude, pickup.longitude,
      dest.location.latitude, dest.location.longitude,
    );

    final requestId = ++_routeRequestId;
    setState(() {
      _destination = dest;
      _distanceKm  = straight;
      _durationMin = _locationService.calculateETA(straight);
      _restorableDestinationName.value = dest.name;
      _isComputingRoute = true;
      // Nouvelle destination : l'ancien tracé ne vaut plus rien.
      _routePoints = const [];
    });

    try {
      final route = await _locationService.getRoute(
        startLat: pickup.latitude,
        startLon: pickup.longitude,
        endLat:   dest.location.latitude,
        endLon:   dest.location.longitude,
      );
      // Une destination plus récente a été choisie entre-temps : réponse périmée.
      if (!mounted || requestId != _routeRequestId) return;
      setState(() {
        _distanceKm  = route.distance;
        _durationMin = route.duration;
        // La géométrie était calculée puis jetée : le tracé bleu reliait
        // pickup et destination en ligne droite, à travers les bâtiments.
        _routePoints = route.coordinates
            .map((c) => LatLng(c.latitude, c.longitude))
            .toList();
        _isComputingRoute = false;
      });
    } catch (e) {
      // Réseau ou API indisponible : on conserve l'estimation à vol d'oiseau.
      // Sous-évaluée, mais jamais bloquante pour la commande.
      debugPrint('❌ Itinéraire: $e');
      if (mounted && requestId == _routeRequestId) {
        setState(() => _isComputingRoute = false);
      }
    }
  }

  // ─────────────────────────────────────────────────────────
  // RÉINITIALISER → retour état idle
  // ─────────────────────────────────────────────────────────
  void _clearDestination() {
    setState(() {
      _destination   = null;
      _distanceKm    = 0;
      _durationMin   = 0;
      _routePoints   = const [];
      _restorableDestinationName.value = null;
    });
    if (_pickupLatLng != null) {
      _mapController.move(_pickupLatLng!, 15);
    }
  }

  // ─────────────────────────────────────────────────────────
  // CONFIRMER → RideConfirmationScreen
  // ─────────────────────────────────────────────────────────
  void _confirmRide() {
    if (_destination == null || _pickupLatLng == null) return;

    final pickupPlace = Place(
      id: 'pickup_current',
      name: _pickupAddress ?? tr('my_position'),
      location: _pickupLatLng!,
      address: _pickupAddress ?? tr('my_position'),
      type: PlaceType.saved,
    );

    final tripDetails = TripDetails(
      departure: _pickupLatLng!,
      destination: _destination!.location,
      departureAddress: _pickupAddress ?? tr('my_position'),
      destinationAddress: _destination!.address ?? _destination!.name,
      distance: _distanceKm,
      duration: _durationMin,
      selectedRide: _selectedRide,
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RideConfirmationScreen(
          pickup: pickupPlace,
          destination: _destination!,
          tripDetails: tripDetails,
          routePoints: _routePoints,
        ),
      ),
    ).then((_) {
      // Après la course (retour du flow), on remet l'état idle
      if (mounted) _clearDestination();
    });
  }

  // ─────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = ref.watch(themeNotifierProvider).isDarkMode;
    _c = isDark ? AppColors.dark : AppColors.light;
    // Un changement de tarif côté admin doit reconstruire l'écran, y compris
    // les branches qui n'affichent pas le sélecteur de véhicule.
    ref.watch(rideChoicesProvider);
    final bool hasDestination = _destination != null;

    if (_gpsFailure != null) {
      return Scaffold(
        backgroundColor: _c.bg,
        appBar: _buildAppBar(),
        body: SafeArea(child: _buildGpsBlocker()),
      );
    }

    return Scaffold(
      backgroundColor: _c.bg,
      appBar: _buildAppBar(),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            children: [
              const SizedBox(height: 10),

              // ── Titre ──────────────────────────────────────
              Text(
                hasDestination
                    ? '${tr('ride_ready')} ✓'
                    : '${tr('where_to_today')} 🌍',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: kNeonGreen,
                ),
              ),

              const SizedBox(height: 16),
              _buildDecorativeElements(),

              // ── Champs localisation ─────────────────────────
              _buildLocationFields(),
              const SizedBox(height: 16),

              // ── Carte : GPS idle OU route avec destination ──
              hasDestination
                  ? _buildRouteMap()
                  : _buildGpsMap(),

              const SizedBox(height: 18),

              // ── Titre sélecteur véhicule (toujours visible) ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    tr('choose_vehicle'),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _c.onSurface,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // ── SÉLECTEUR VÉHICULE UNIQUE (horizontal avec RideChoiceCard) ──
              _buildVehicleSelector(),

              const SizedBox(height: 18),

              // ── Bouton principal ────────────────────────────
              hasDestination
                  ? _buildConfirmButton()
                  : _buildChooseDestinationButton(),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // BLOCAGE GPS
  // Sans position réelle on n'affiche pas le formulaire : une course partirait
  // d'un point inventé et serait facturée depuis ce point.
  // ─────────────────────────────────────────────────────────
  Widget _buildGpsBlocker() {
    final deniedForever = _gpsFailure == LocationFailure.permissionDeniedForever;
    final serviceOff = _gpsFailure == LocationFailure.serviceDisabled;

    final String titre;
    final String detail;
    if (serviceOff) {
      titre = 'Activez votre localisation';
      detail = 'La localisation est désactivée sur votre iPhone. '
          'Nous en avons besoin pour savoir où venir vous chercher.';
    } else if (deniedForever) {
      titre = 'Localisation bloquée';
      detail = 'Vous avez refusé l\'accès à votre position. '
          'Autorisez Velox dans les réglages pour commander une course.';
    } else if (_gpsFailure == LocationFailure.permissionDenied) {
      titre = 'Autorisez votre localisation';
      detail = 'Velox a besoin de votre position pour savoir où venir '
          'vous chercher.';
    } else {
      titre = 'Position introuvable';
      detail = 'Le GPS ne répond pas. Placez-vous près d\'une fenêtre ou '
          'à l\'extérieur, puis réessayez.';
    }

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: kNeonGreen.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                serviceOff ? Icons.location_off_rounded : Icons.location_disabled_rounded,
                size: 44,
                color: kNeonGreen,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              titre,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: _c.onSurface,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: _c.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _openLocationSettings,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kNeonGreen,
                  foregroundColor: kNeonGreenDark,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  serviceOff ? 'Ouvrir les réglages' : 'Autoriser la localisation',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: OutlinedButton(
                onPressed: _isLoadingPickup ? null : _initGps,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _c.onSurface,
                  side: BorderSide(color: _c.outlineVariant),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _isLoadingPickup
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text(
                        'Réessayer',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // APP BAR
  // ─────────────────────────────────────────────────────────
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: _c.surfaceLow,
      elevation: 0,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: kNeonGreen.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text('🇩🇯', style: TextStyle(fontSize: 20)),
          ),
          const SizedBox(width: 8),
          const Text('Velox', style: TextStyle(color: kNeonGreen, fontSize: 22, fontWeight: FontWeight.bold)),
        ],
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Container(
            decoration: BoxDecoration(
              color: _c.surface,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha:0.05), blurRadius: 8, offset: const Offset(0, 2))],
            ),
            child: IconButton(
              icon: const Icon(Icons.notifications_none),
              color: _c.onSurfaceVariant,
              onPressed: () {},
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDecorativeElements() {
    return SizedBox(
      height: 60,
      child: Stack(children: [
        Positioned(left: -20, top: 0, child: Container(
          width: 100, height: 100,
          decoration: BoxDecoration(
            gradient: RadialGradient(colors: [drapeauVert.withValues(alpha:0.1), drapeauVert.withValues(alpha:0)]),
            shape: BoxShape.circle,
          ),
        )),
        Positioned(right: -30, bottom: 0, child: Container(
          width: 120, height: 120,
          decoration: BoxDecoration(
            gradient: RadialGradient(colors: [drapeauBleu.withValues(alpha:0.1), drapeauBleu.withValues(alpha:0)]),
            shape: BoxShape.circle,
          ),
        )),
      ]),
    );
  }

  // ─────────────────────────────────────────────────────────
  // CHAMPS PICKUP + DESTINATION
  // ─────────────────────────────────────────────────────────
  Widget _buildLocationFields() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _c.surfaceLow,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha:0.08), blurRadius: 16, offset: const Offset(0, 6)),
            if (_isAdjustingPickup)
              BoxShadow(color: drapeauVert.withValues(alpha:0.2), blurRadius: 12, offset: const Offset(0, 4)),
          ],
          border: _isAdjustingPickup
              ? Border.all(color: drapeauVert.withValues(alpha:0.3), width: 1.5)
              : null,
        ),
        child: Column(
          children: [
            // ── PICKUP ──
            _buildPickupRow(),

            // Connecteur
            Padding(
              padding: const EdgeInsets.only(left: 7),
              child: Container(
                width: 2, height: 20,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [vertPrincipal.withValues(alpha:0.4), _c.outlineVariant],
                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),

            // ── DESTINATION ──
            _buildDestinationRow(),
          ],
        ),
      ),
    );
  }

  Widget _buildPickupRow() {
    return GestureDetector(
      onTap: _destination == null ? _togglePickupAdjustment : null,
      behavior: HitTestBehavior.opaque,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Dot vert animé
          ScaleTransition(
            scale: _pulseAnimation,
            child: Container(
              width: 16, height: 16,
              decoration: BoxDecoration(
                color: kNeonGreen,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: kNeonGreen.withValues(alpha:0.4), blurRadius: 6)],
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isAdjustingPickup ? '🔄 ${tr('manual_adjust')}' : '📍 ${tr('pickup_point')}',
                  style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w600,
                    color: _isAdjustingPickup ? drapeauVert : _c.onSurfaceVariant,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 3),
                if (_isLoadingPickup)
                  Row(children: [
                    SizedBox(width: 14, height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(drapeauVert))),
                    const SizedBox(width: 8),
                    Text(tr('locating'), style: TextStyle(fontSize: 13, color: _c.onSurfaceVariant)),
                  ])
                else
                  Text(
                    _pickupAddress ?? tr('choose_pickup'),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: _pickupAddress != null ? FontWeight.w600 : FontWeight.w400,
                      color: _pickupAddress != null ? _c.onSurface : _c.onSurfaceVariant,
                    ),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          // Bouton ajustement manuel (visible uniquement en état idle)
          if (_destination == null)
            GestureDetector(
              onTap: _togglePickupAdjustment,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: _isAdjustingPickup ? drapeauVert.withValues(alpha:0.12) : _c.surface,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.edit_location_alt,
                    color: _isAdjustingPickup ? drapeauVert : _c.onSurfaceVariant, size: 16),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDestinationRow() {
    final bool hasDestination = _destination != null;

    return GestureDetector(
      onTap: _openDestinationPicker,
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          Container(
            width: 16, height: 16,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [drapeauBleu, bleuPrincipal],
                begin: Alignment.topLeft, end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              hasDestination
                  ? (_destination!.address ?? _destination!.name)
                  : tr('destination_hint'),
              style: TextStyle(
                fontSize: 15,
                fontWeight: hasDestination ? FontWeight.w600 : FontWeight.w500,
                color: hasDestination ? _c.onSurface : _c.onSurfaceVariant,
              ),
              maxLines: 1, overflow: TextOverflow.ellipsis,
            ),
          ),
          // Bouton modifier (si destination choisie) ou chevron
          if (hasDestination)
            GestureDetector(
              onTap: _clearDestination,
              child: Container(
                padding: const EdgeInsets.all(4),
                child: Icon(Icons.close, color: _c.onSurfaceVariant, size: 18),
              ),
            )
          else
            const Icon(Icons.chevron_right, color: drapeauBleu, size: 20),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // CARTE GPS SIMPLE (état idle)
  // ─────────────────────────────────────────────────────────
  Widget _buildGpsMap() {
    final displayPos = _pickupLatLng ?? _djiboutiCenter;

    return Container(
      height: MediaQuery.of(context).size.height * 0.32,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha:0.15), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: displayPos,
                initialZoom: 15,
                maxZoom: 18, minZoom: 10,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
                onTap: (_, latLng) => _onMapTap(latLng),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://basemaps.cartocdn.com/light_all/{z}/{x}/{y}@2x.png',
                  userAgentPackageName: 'com.nomade253.app',
                ),
                MarkerLayer(markers: [
                  Marker(
                    point: displayPos, width: 70, height: 70,
                    child: ScaleTransition(
                      scale: _pulseAnimation,
                      child: Container(
                        decoration: BoxDecoration(
                          color: secondaryColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: blanc, width: 3),
                          boxShadow: [BoxShadow(color: secondaryColor.withValues(alpha:0.5), blurRadius: 20, spreadRadius: 2)],
                        ),
                        child: const Icon(Icons.person_pin_circle, color: blanc, size: 28),
                      ),
                    ),
                  ),
                ]),
              ],
            ),
            // Bouton recentrer
            Positioned(bottom: 16, right: 16, child: _mapFab(
              icon: Icons.my_location,
              color: drapeauBleu,
              onTap: () { if (_pickupLatLng != null) _mapController.move(_pickupLatLng!, 15); },
            )),
            // Contrôles zoom (+/−) au-dessus du bouton recentrer
            Positioned(bottom: 64, right: 16, child: _zoomControls(_mapController)),
            // Badge ajustement
            if (_isAdjustingPickup)
              Positioned(top: 16, left: 16, child: _adjustBadge()),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // CARTE ROUTE (état avec destination)
  // ─────────────────────────────────────────────────────────
  Widget _buildRouteMap() {
    if (_pickupLatLng == null || _destination == null) return const SizedBox.shrink();
    // Carte isolée dans son propre widget : les setState du parent (sélection
    // véhicule, prix…) ne la reconstruisent plus. Un MapController attaché à une
    // carte reconstruite en boucle gelait les gestes et le zoom — d'où ce split.
    return _RouteMapCard(
      pickup: _pickupLatLng!,
      dest: _destination!.location,
      routePoints: _routePoints,
      distanceKm: _distanceKm,
      durationMin: _durationMin,
      colors: _c,
      onEditDestination: _openDestinationPicker,
    );
  }

  // ─────────────────────────────────────────────────────────
  // SÉLECTEUR VÉHICULE UNIQUE (horizontal avec RideChoiceCard)
  // Affiche les prix de base si pas de destination, prix calculés si destination
  // ─────────────────────────────────────────────────────────
  Widget _buildVehicleSelector() {
    final vehicles = ref.watch(rideChoicesProvider);
    final bool hasDestination = _destination != null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: vehicles.asMap().entries.map((e) {
          final i = e.key;
          final v = e.value;
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(left: i == 0 ? 0 : 8),
              child: RideChoiceCard(
                ride: v,
                distance: hasDestination ? _distanceKm : 0.0,
                isSelected: _selectedRide.id == v.id,
                onTap: () => setState(() => _selectedRideId = v.id),
                c: _c,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // BOUTON "Choisir une destination" (état idle)
  // ─────────────────────────────────────────────────────────
  Widget _buildChooseDestinationButton() {
    final bool canTap = _pickupLatLng != null && !_isLoadingPickup;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        height: 60,
        decoration: BoxDecoration(
          color: canTap ? kNeonGreen : Colors.grey.shade400,
          borderRadius: BorderRadius.circular(30),
          boxShadow: canTap
              ? [BoxShadow(color: kNeonGreen.withValues(alpha:0.35), blurRadius: 14, offset: const Offset(0, 8))]
              : [],
        ),
        child: ElevatedButton(
          onPressed: canTap ? _openDestinationPicker : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            disabledBackgroundColor: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                canTap ? Icons.search : Icons.location_searching,
                color: canTap ? kNeonGreenDark : Colors.white70, size: 20,
              ),
              const SizedBox(width: 10),
              Text(
                canTap ? tr('choose_destination') : tr('locating_in_progress'),
                style: TextStyle(
                  fontSize: 17, fontWeight: FontWeight.bold,
                  color: canTap ? kNeonGreenDark : Colors.white70, letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // BOUTON "Confirmer la course" (état avec destination)
  // ─────────────────────────────────────────────────────────
  Widget _buildConfirmButton() {
    final price = _selectedRide.calculatePrice(_distanceKm);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        height: 62,
        decoration: BoxDecoration(
          color: kNeonGreen,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(color: kNeonGreen.withValues(alpha:0.4), blurRadius: 16, offset: const Offset(0, 8)),
          ],
        ),
        child: ElevatedButton(
          // Tant que la vraie distance routière n'est pas revenue, le prix
          // affiché est l'estimation à vol d'oiseau : on ne laisse pas
          // confirmer sur un montant qui va encore changer.
          onPressed: _isComputingRoute ? null : _confirmRide,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            disabledBackgroundColor: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _isComputingRoute
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: kNeonGreenDark),
                    )
                  : const Icon(Icons.local_taxi, color: kNeonGreenDark, size: 22),
              const SizedBox(width: 10),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      _isComputingRoute
                          ? 'Calcul de l\'itinéraire...'
                          : tr('confirm_ride'),
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: kNeonGreenDark, letterSpacing: 0.3)),
                  Text('${price.toStringAsFixed(0)} FDJ · ${_selectedRide.name}',
                      style: const TextStyle(fontSize: 12, color: kNeonGreenDark)),
                ],
              ),
              const SizedBox(width: 10),
              if (!_isComputingRoute)
                const Icon(Icons.arrow_forward, color: kNeonGreenDark, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // HELPERS UI
  // ─────────────────────────────────────────────────────────
  Widget _mapFab({required IconData icon, required Color color, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: _c.surfaceLow,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha:0.15), blurRadius: 10, offset: const Offset(0, 3))],
        ),
        child: Icon(icon, color: color, size: 18),
      ),
    );
  }

  /// Change le zoom de la carte `c` d'un cran, en gardant le centre actuel.
  void _zoomBy(MapController c, double delta) {
    final cam = c.camera;
    final z = (cam.zoom + delta).clamp(4.0, 18.0);
    c.move(cam.center, z);
  }

  /// Contrôles de zoom (+ / −) empilés, à poser sur une carte VTC.
  Widget _zoomControls(MapController c) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _mapFab(
          icon: Icons.add,
          color: _c.onSurface,
          onTap: () => _zoomBy(c, 1),
        ),
        const SizedBox(height: 8),
        _mapFab(
          icon: Icons.remove,
          color: _c.onSurface,
          onTap: () => _zoomBy(c, -1),
        ),
      ],
    );
  }

  Widget _adjustBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: kNeonGreen,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [BoxShadow(color: kNeonGreen.withValues(alpha:0.3), blurRadius: 8)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.touch_app, color: kNeonGreenDark, size: 14),
          const SizedBox(width: 6),
          Text(tr('tap_to_move'),
              style: const TextStyle(color: kNeonGreenDark, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// Carte « route » (départ + destination + tracé) isolée dans son propre
/// StatefulWidget. Elle possède son MapController et ne se reconstruit que si
/// le trajet change réellement (via didUpdateWidget) — les rebuilds du parent
/// (sélection véhicule, recalcul prix) ne la touchent plus, ce qui élimine le
/// gel des gestes/zoom. Contient ses propres contrôles + / −.
class _RouteMapCard extends StatefulWidget {
  final LatLng pickup;
  final LatLng dest;

  /// Géométrie routière à tracer. Vide tant que l'itinéraire est en cours de
  /// calcul ou si l'API a échoué : on trace alors la droite pickup → dest.
  final List<LatLng> routePoints;

  final double distanceKm;
  final int durationMin;
  final AppColors colors;
  final VoidCallback onEditDestination;

  const _RouteMapCard({
    required this.pickup,
    required this.dest,
    required this.routePoints,
    required this.distanceKm,
    required this.durationMin,
    required this.colors,
    required this.onEditDestination,
  });

  @override
  State<_RouteMapCard> createState() => _RouteMapCardState();
}

class _RouteMapCardState extends State<_RouteMapCard> {
  final MapController _controller = MapController();

  static double _zoomFor(double km) {
    if (km > 20) return 11;
    if (km > 10) return 12;
    if (km > 5) return 13;
    if (km < 2) return 15;
    return 14;
  }

  LatLng get _center => LatLng(
        (widget.pickup.latitude + widget.dest.latitude) / 2,
        (widget.pickup.longitude + widget.dest.longitude) / 2,
      );

  @override
  void didUpdateWidget(covariant _RouteMapCard old) {
    super.didUpdateWidget(old);
    // Recadrer UNIQUEMENT si le trajet a réellement changé — pas sur un simple
    // rebuild parent — sinon on écraserait le zoom manuel de l'utilisateur.
    if (old.pickup != widget.pickup || old.dest != widget.dest) {
      _controller.move(_center, _zoomFor(widget.distanceKm));
      return;
    }
    // La géométrie routière arrive ~1 s après le choix de la destination. Une
    // route contourne, donc elle sort régulièrement du rectangle départ↔arrivée
    // sur lequel le cadrage initial était calculé : sans ce recadrage, une
    // partie du tracé nouvellement dessiné reste hors de la carte.
    if (old.routePoints != widget.routePoints &&
        widget.routePoints.length >= 2) {
      _controller.fitCamera(
        CameraFit.coordinates(
          coordinates: widget.routePoints,
          padding: const EdgeInsets.all(28),
          maxZoom: 17,
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _zoomBy(double delta) {
    final cam = _controller.camera;
    _controller.move(cam.center, (cam.zoom + delta).clamp(4.0, 18.0));
  }

  Widget _fab(IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: widget.colors.surfaceLow,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 10, offset: const Offset(0, 3))],
        ),
        child: Icon(icon, color: color, size: 18),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    return Container(
      height: MediaQuery.of(context).size.height * 0.32,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          children: [
            FlutterMap(
              mapController: _controller,
              options: MapOptions(
                initialCenter: _center,
                initialZoom: _zoomFor(widget.distanceKm),
                maxZoom: 18, minZoom: 8,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://basemaps.cartocdn.com/light_all/{z}/{x}/{y}@2x.png',
                  userAgentPackageName: 'com.nomade253.app',
                ),
                PolylineLayer(polylines: [
                  Polyline(
                    // Le tracé suit les routes dès que la géométrie est
                    // disponible ; la droite ne reste qu'un état transitoire.
                    points: widget.routePoints.length >= 2
                        ? widget.routePoints
                        : [widget.pickup, widget.dest],
                    color: secondaryColor,
                    strokeWidth: 5,
                    borderColor: Colors.white.withValues(alpha: 0.8),
                    borderStrokeWidth: 3,
                  ),
                ]),
                MarkerLayer(markers: [
                  Marker(
                    point: widget.pickup, width: 50, height: 50,
                    child: Container(
                      decoration: BoxDecoration(
                        color: drapeauVert,
                        shape: BoxShape.circle,
                        border: Border.all(color: blanc, width: 3),
                        boxShadow: [BoxShadow(color: drapeauVert.withValues(alpha: 0.4), blurRadius: 10)],
                      ),
                      child: const Icon(Icons.circle, color: blanc, size: 14),
                    ),
                  ),
                  Marker(
                    point: widget.dest, width: 56, height: 66,
                    child: Icon(
                      Icons.location_pin,
                      color: drapeauBleu,
                      size: 56,
                      shadows: [Shadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 10, offset: const Offset(0, 5))],
                    ),
                  ),
                ]),
              ],
            ),

            // Badge infos trajet (distance + durée)
            Positioned(
              bottom: 12, left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: c.surfaceLow,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 8)],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.straighten, size: 13, color: c.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text('${widget.distanceKm.toStringAsFixed(1)} km',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: c.onSurface)),
                    const SizedBox(width: 10),
                    Icon(Icons.timer_outlined, size: 13, color: c.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text('${widget.durationMin} min',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: c.onSurface)),
                  ],
                ),
              ),
            ),

            // Bouton modifier destination
            Positioned(
              top: 12, right: 12,
              child: _fab(Icons.edit_location_alt, drapeauBleu, widget.onEditDestination),
            ),

            // Contrôles zoom (+ / −)
            Positioned(
              bottom: 12, right: 12,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _fab(Icons.add, c.onSurface, () => _zoomBy(1)),
                  const SizedBox(height: 8),
                  _fab(Icons.remove, c.onSurface, () => _zoomBy(-1)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}