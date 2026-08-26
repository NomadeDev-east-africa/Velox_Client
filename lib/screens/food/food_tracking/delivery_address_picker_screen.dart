import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:nomade_client/constants.dart';
import '../../../theme/app_colors.dart';
import '../../../services/location_service.dart';
import '../../../providers/all_providers.dart';

class DeliveryAddressPickerScreen extends ConsumerStatefulWidget {
  const DeliveryAddressPickerScreen({super.key});

  @override
  ConsumerState<DeliveryAddressPickerScreen> createState() => _DeliveryAddressPickerScreenState();
}

class _DeliveryAddressPickerScreenState extends ConsumerState<DeliveryAddressPickerScreen> {
  final LocationService _locationService = LocationService();
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();

  LatLng? _customDeliveryPosition;
  bool _showSearchResults = false;
  List<PlaceResult> _searchResults = [];
  bool _isSearching = false;
  Timer? _debounceTimer;
  bool _isDarkMap = false;

  // ✅ AJOUTÉ: Variable pour gérer l'état d'initialisation
  bool _isInitialized = false;
  Timer? _mapMoveTimer;

  // Adresse correspondant à _customDeliveryPosition (indépendante du GPS)
  String? _customAddress;
  bool _isAddressLoading = false;

  @override
  void initState() {
    super.initState();
    debugPrint('🚀 DeliveryAddressPickerScreen - initState()');

    // ✅ CORRIGÉ: Charger la position IMMÉDIATEMENT
    _initializePosition();
  }

  // ✅ AJOUTÉ: Méthode séparée pour initialiser la position
  Future<void> _initializePosition() async {
    try {
      final locNotifier = ref.read(locationNotifierProvider.notifier);

      if (!ref.read(locationNotifierProvider).hasPosition) {
        debugPrint('📍 Aucune position disponible - Obtention de la position...');
        await locNotifier.getCurrentLocation();
      }

      final position = ref.read(locationNotifierProvider).position ??
          const LatLng(11.5880, 43.1450);

      // `getCurrentLocation()` prend plusieurs secondes : l'utilisateur a pu
      // quitter l'écran entre-temps, et setState sur un widget détruit lève.
      if (!mounted) return;
      setState(() {
        _customDeliveryPosition = position;
        _isInitialized = true;
      });

      // ✅ CORRIGÉ: Utiliser un délai pour s'assurer que la carte est prête
      _mapMoveTimer?.cancel();
      _mapMoveTimer = Timer(const Duration(milliseconds: 100), () {
        try {
          _mapController.move(position, 16.0);
          debugPrint('✅ Carte déplacée à: $position');
        } catch (e) {
          debugPrint('⚠️ Erreur déplacement carte: $e');
        }
      });

      debugPrint('✅ Position initialisée: $position');

      // Charger l'adresse pour cette position et la stocker localement
      if (!mounted) return;
      setState(() => _isAddressLoading = true);
      ref.read(locationNotifierProvider.notifier)
          .getAddressForPosition(position)
          .then((addr) {
        if (mounted) {
          setState(() {
            _customAddress = addr;
            _isAddressLoading = false;
          });
        }
      });

    } catch (e) {
      debugPrint('❌ Erreur initialisation position: $e');

      // Fallback sur position par défaut
      const defaultPosition = LatLng(11.5880, 43.1450);
      // C'est ce setState-ci qui plantait sur 1.0.16 : l'échec GPS survient
      // après un délai d'attente, souvent une fois l'écran quitté.
      if (!mounted) return;
      setState(() {
        _customDeliveryPosition = defaultPosition;
        _isInitialized = true;
      });

      // Déplacer la carte vers la position par défaut
      _mapMoveTimer?.cancel();
      _mapMoveTimer = Timer(const Duration(milliseconds: 100), () {
        try {
          _mapController.move(defaultPosition, 12.0);
        } catch (e) {
          debugPrint('⚠️ Erreur déplacement carte défaut: $e');
        }
      });

      // Informer l'utilisateur que le GPS est désactivé
      if (mounted) _showGpsDisabledBanner();
    }
  }

  void _showGpsDisabledBanner() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Localisation désactivée — carte centrée par défaut'),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: 'Activer',
          onPressed: () async {
            await Geolocator.openLocationSettings();
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    debugPrint('🛑 DeliveryAddressPickerScreen - dispose()');
    _searchController.dispose();
    _debounceTimer?.cancel();
    _mapMoveTimer?.cancel();
    super.dispose();
  }

  void _searchPlaces(String query) {
    _debounceTimer?.cancel();

    if (query.trim().isEmpty) {
      setState(() {
        _showSearchResults = false;
        _searchResults = [];
      });
      return;
    }

    _debounceTimer = Timer(const Duration(milliseconds: 500), () async {
      setState(() => _isSearching = true);
      debugPrint('🔍 Recherche adresse: "$query"');

      try {
        final results = await _locationService.searchPlaces(query);
        debugPrint('📦 ${results.length} résultats trouvés');

        if (mounted) {
          setState(() {
            _searchResults = results;
            _showSearchResults = true;
            _isSearching = false;
          });
        }
      } catch (e, stackTrace) {
        debugPrint('❌ Erreur recherche: $e');
        debugPrint('📝 Stack trace: $stackTrace');

        if (mounted) {
          setState(() {
            _isSearching = false;
            _showSearchResults = false;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Recherche limitée - Vérifiez votre connexion'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    });
  }

  void _selectSearchResult(PlaceResult place) {
    debugPrint('✅ Sélection adresse: ${place.name}');

    final position = LatLng(place.latitude, place.longitude);
    setState(() {
      _customDeliveryPosition = position;
      _showSearchResults = false;
      _searchController.text = place.name;
      _customAddress = place.name; // L'adresse est déjà le nom du lieu recherché
    });

    // Déplacer la carte vers la nouvelle position
    _mapMoveTimer?.cancel();
    _mapMoveTimer = Timer(const Duration(milliseconds: 50), () {
      try {
        _mapController.move(position, 16.0);
      } catch (e) {
        debugPrint('⚠️ Erreur déplacement carte après sélection: $e');
      }
    });

    setState(() => _isAddressLoading = true);
    ref.read(locationNotifierProvider.notifier)
        .getAddressForPosition(position)
        .then((addr) {
      if (mounted) {
        setState(() {
          _customAddress = addr;
          _isAddressLoading = false;
        });
      }
    });

    FocusScope.of(context).unfocus();
  }

  void _confirmDeliveryAddress() {
    debugPrint('🎯 Confirmer l\'adresse de livraison');

    final locState         = ref.read(locationNotifierProvider);
    final deliveryPosition = _customDeliveryPosition ?? locState.position;
    final deliveryAddress  = _customAddress ?? locState.address;

    debugPrint('🎯 Position: $deliveryPosition');
    debugPrint('🎯 Adresse: "$deliveryAddress"');

    if (deliveryPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sélectionnez une position valide'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // ✅ CORRIGÉ: Utiliser les coordonnées si l'adresse n'est pas encore chargée
    final finalAddress = deliveryAddress ??
        '${deliveryPosition.latitude.toStringAsFixed(6)}, ${deliveryPosition.longitude.toStringAsFixed(6)}';

    Navigator.pop(context, {
      'location': deliveryPosition,
      'address': finalAddress,
      'addressName': finalAddress,
    });
  }

  String get _mapTileUrl => _isDarkMap
      ? 'https://basemaps.cartocdn.com/dark_all/{z}/{x}/{y}@2x.png'
      : 'https://basemaps.cartocdn.com/light_all/{z}/{x}/{y}@2x.png';

  Widget _buildAddressLoadingIndicator(AppColors c) {
    return Column(
      children: [
        Container(
          height: 20,
          width: double.infinity,
          decoration: BoxDecoration(
            color: c.surfaceHigh,
            borderRadius: BorderRadius.circular(8),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              backgroundColor: c.surfaceHigh,
              color: c.error.withValues(alpha:0.5),
              minHeight: 20,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Chargement de l\'adresse...',
          style: TextStyle(
            fontSize: 12,
            color: c.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ref.watch(themeNotifierProvider).isDarkMode;
    final c = isDark ? AppColors.dark : AppColors.light;
    final locationState = ref.watch(locationNotifierProvider);

    final deliveryPosition = _customDeliveryPosition ??
        locationState.position ??
        const LatLng(11.5880, 43.1450);
    final deliveryAddress   = _customAddress ?? locationState.address;
    final isLoadingAddress  = locationState.isLoading;

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: const Text('Choisir l\'adresse de livraison'),
        elevation: 0,
      ),
      body: Stack(
        children: [
          // ✅ CORRIGÉ: Toujours afficher la carte
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: deliveryPosition,
              initialZoom: _isInitialized ? 16.0 : 12.0,
              maxZoom: 18,
              minZoom: 10,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
              onPositionChanged: (position, hasGesture) {
                if (hasGesture) {
                  final center = position.center;
                  debugPrint('🗺️ Carte déplacée: ${center.latitude}, ${center.longitude}');

                  setState(() {
                    _customDeliveryPosition = center;
                  });

                  setState(() => _isAddressLoading = true);
                  ref.read(locationNotifierProvider.notifier)
                      .getAddressForPosition(center)
                      .then((addr) {
                    if (mounted) {
                      setState(() {
                        _customAddress = addr;
                        _isAddressLoading = false;
                      });
                    }
                  });
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: _mapTileUrl,
                userAgentPackageName: 'com.nomade253.app',
              ),
              // Marqueur de destination
              MarkerLayer(
                markers: [
                  Marker(
                    point: deliveryPosition,
                    width: 50,
                    height: 70,
                    child: Icon(
                      Icons.location_pin,
                      color: deliveryPosition == const LatLng(11.5880, 43.1450) &&
                          _customDeliveryPosition == null
                          ? Colors.grey
                          : Colors.red,
                      size: 50,
                      shadows: [
                        Shadow(
                          color: Colors.black.withValues(alpha:0.3),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),

          // Barre de recherche
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 16,
            right: 16,
            child: Container(
              decoration: BoxDecoration(
                color: c.surfaceLow,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha:0.1),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: TextField(
                controller: _searchController,
                onChanged: _searchPlaces,
                style: TextStyle(fontSize: 17, color: c.onSurface),
                decoration: InputDecoration(
                  hintText: 'Rechercher une adresse...',
                  hintStyle: TextStyle(color: c.onSurfaceVariant, fontSize: 17),
                  prefixIcon: const Icon(Icons.search, color: secondaryColor, size: 26),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                    icon: Icon(Icons.clear, size: 20, color: c.onSurfaceVariant),
                    onPressed: () {
                      setState(() {
                        _searchController.clear();
                        _showSearchResults = false;
                        _searchResults = [];
                      });
                      FocusScope.of(context).unfocus();
                    },
                  )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                ),
              ),
            ),
          ),

          // Résultats de recherche
          if (_showSearchResults)
            Positioned(
              top: MediaQuery.of(context).padding.top + 90,
              left: 16,
              right: 16,
              bottom: MediaQuery.of(context).padding.bottom + 200,
              child: Container(
                decoration: BoxDecoration(
                  color: c.surfaceLow,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 16,
                      offset: Offset(0, -4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Text(
                            'Résultats',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: c.onSurface,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${_searchResults.length} trouvé(s)',
                            style: TextStyle(
                              fontSize: 14,
                              color: c.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 0, color: c.outlineVariant),
                    Expanded(
                      child: _isSearching
                          ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const CircularProgressIndicator(color: secondaryColor),
                            const SizedBox(height: 16),
                            Text(
                              'Recherche en cours...',
                              style: TextStyle(color: c.onSurfaceVariant),
                            ),
                          ],
                        ),
                      )
                          : _searchResults.isEmpty
                          ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.location_off,
                              size: 60,
                              color: c.outlineVariant,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Aucun résultat trouvé',
                              style: TextStyle(
                                fontSize: 16,
                                color: c.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Essayez avec d\'autres termes',
                              style: TextStyle(
                                fontSize: 14,
                                color: c.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      )
                          : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _searchResults.length,
                        separatorBuilder: (_, _) => Divider(height: 16, color: c.outlineVariant),
                        itemBuilder: (context, index) {
                          final place = _searchResults[index];
                          return ListTile(
                            leading: Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: secondaryColor.withValues(alpha:0.1),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Icon(
                                Icons.location_on,
                                color: secondaryColor,
                                size: 26,
                              ),
                            ),
                            title: Text(
                              place.name,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: c.onSurface,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${place.latitude.toStringAsFixed(4)}, ${place.longitude.toStringAsFixed(4)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: c.onSurfaceVariant,
                              ),
                            ),
                            onTap: () => _selectSearchResult(place),
                            contentPadding: EdgeInsets.zero,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Panneau bottom
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
              decoration: BoxDecoration(
                color: c.surfaceLow,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 20,
                    offset: Offset(0, -8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Destination
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha:0.1),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(
                          Icons.location_pin,
                          color: Colors.red,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Livrer à',
                              style: TextStyle(
                                color: c.onSurfaceVariant,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 6),
                            isLoadingAddress
                                ? _buildAddressLoadingIndicator(c)
                                : Text(
                              deliveryAddress ?? 'Déplacez la carte pour choisir',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: deliveryAddress == null
                                    ? c.onSurfaceVariant
                                    : c.onSurface,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Instructions
                  if (!isLoadingAddress)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 16,
                            color: c.onSurfaceVariant,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              deliveryAddress == null
                                  ? 'Déplacez la carte ou recherchez une adresse'
                                  : 'Déplacez la carte pour ajuster l\'adresse exacte',
                              style: TextStyle(
                                fontSize: 13,
                                color: c.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Bouton confirmer
                  SizedBox(
                    height: 56,
                    child: ElevatedButton(
                      onPressed: (_customDeliveryPosition != null && !_isAddressLoading)
                          ? _confirmDeliveryAddress
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: Ink(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: (_customDeliveryPosition != null && !_isAddressLoading)
                                ? const [secondaryColor, primaryColor]
                                : [Colors.grey.shade400, Colors.grey.shade500],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: (_customDeliveryPosition != null && !_isAddressLoading)
                              ? [
                            BoxShadow(
                              color: secondaryColor.withValues(alpha:0.3),
                              blurRadius: 6,
                              offset: const Offset(0, 3),
                            ),
                          ]
                              : null,
                        ),
                        child: SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: Center(
                            child: _isAddressLoading
                                ? Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                ),
                                SizedBox(width: 12),
                                Text(
                                  'Chargement adresse...',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            )
                                : Text(
                              _customDeliveryPosition != null
                                  ? 'Confirmer cette adresse'
                                  : 'Sélectionnez une position',
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ✅ AJOUTÉ: Toggle thème map (comme dans destination_picker_screen)
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            right: 16,
            child: Container(
              decoration: BoxDecoration(
                color: c.surfaceLow,
                shape: BoxShape.circle,
                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8)],
              ),
              child: IconButton(
                iconSize: 24,
                icon: Icon(
                  _isDarkMap ? Icons.light_mode : Icons.dark_mode,
                  color: c.onSurface,
                ),
                onPressed: () {
                  debugPrint('🎨 Changement thème: $_isDarkMap → ${!_isDarkMap}');
                  setState(() => _isDarkMap = !_isDarkMap);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}