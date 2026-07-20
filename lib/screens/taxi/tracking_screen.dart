import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:nomade_client/models/ride.dart';
import 'package:nomade_client/providers/all_providers.dart';
import 'package:nomade_client/theme/app_colors.dart';
import 'ride_completion_screen.dart';
import 'track_driver_screen.dart';

/// Écran de suivi en temps réel — design Kinetic Monolith
class TrackingScreen extends ConsumerStatefulWidget {
  const TrackingScreen({super.key});

  @override
  ConsumerState<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends ConsumerState<TrackingScreen>
    with SingleTickerProviderStateMixin {

  final MapController _mapController = MapController();
  bool _showCompletionDialog = false;
  bool _noDriverPopupShown   = false;
  late AppColors _c;
  late bool _isDark;

  // Cache du document chauffeur (plaque) : l'écran se reconstruit à chaque
  // mise à jour de la course, on ne veut PAS relire Firestore à chaque rebuild.
  Future<DocumentSnapshot<Map<String, dynamic>>>? _driverDocFuture;
  String? _driverDocFutureId;

  Future<DocumentSnapshot<Map<String, dynamic>>> _driverDoc(String driverId) {
    if (_driverDocFutureId != driverId) {
      _driverDocFutureId = driverId;
      _driverDocFuture = FirebaseFirestore.instance
          .collection('drivers')
          .doc(driverId)
          .get();
    }
    return _driverDocFuture!;
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  // ════════════════════════════════════════════════════════════
  // STATUS HELPERS
  // ════════════════════════════════════════════════════════════

  Map<String, dynamic> _getStatusInfo(RideStatus status) {
    switch (status) {
      case RideStatus.requested:
        return {
          'label': 'SCAN_RÉSEAU',
          'text':  'Recherche d\'un commandant de bord...',
          'showTimer': true,
        };
      case RideStatus.accepted:
        return {
          'label': 'COMMANDANT_ASSIGNÉ',
          'text':  'Chauffeur en route vers vous',
          'showTimer': false,
        };
      case RideStatus.arriving:
        return {
          'label': 'APPROCHE_IMMINENTE',
          'text':  'Votre chauffeur approche !',
          'showTimer': false,
        };
      case RideStatus.arrived:
        return {
          'label': 'ARRIVÉE_CONFIRMÉE',
          'text':  'Votre chauffeur est arrivé !',
          'showTimer': false,
        };
      case RideStatus.started:
        return {
          'label': 'EN_TRANSIT',
          'text':  'En route vers la destination',
          'showTimer': true,
        };
      case RideStatus.completed:
        return {
          'label': 'MISSION_ACCOMPLIE',
          'text':  'Course terminée',
          'showTimer': false,
        };
      case RideStatus.cancelled:
      case RideStatus.noDriverAvailable:
        return {
          'label': 'COURSE_ANNULÉE',
          'text':  'Course annulée',
          'showTimer': false,
        };
    }
  }

  // ════════════════════════════════════════════════════════════
  // ACTIONS
  // ════════════════════════════════════════════════════════════

  Future<void> _cancelRide() async {
    final c = _c;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: c.surfaceLow,
        title: Text(
          'ANNULER LA COURSE ?',
          style: GoogleFonts.spaceGrotesk(
              color: c.onSurface, fontWeight: FontWeight.w800),
        ),
        content: Text(
          'Êtes-vous sûr de vouloir annuler cette course ?',
          style: GoogleFonts.inter(color: c.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('NON',
                style: GoogleFonts.spaceGrotesk(color: c.onSurfaceVariant)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('OUI, ANNULER',
                style: GoogleFonts.spaceGrotesk(color: c.error)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await ref
            .read(activeRideProvider.notifier)
            .cancelRide('Annulé par le client');
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Erreur annulation: $e'),
                backgroundColor: _c.error),
          );
        }
      }
    }
  }

  void _navigateToCompletion(Ride ride) {
    if (_showCompletionDialog) return;
    _showCompletionDialog = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => RideCompletionScreen(ride: ride)),
      );
    });
  }

  // ════════════════════════════════════════════════════════════
  // BUILD
  // ════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    _isDark = ref.watch(themeNotifierProvider).isDarkMode;
    _c = _isDark ? AppColors.dark : AppColors.light;

    final rideState = ref.watch(activeRideProvider);

    ref.listen<ActiveRideState>(activeRideProvider, (prev, next) {
      if (next.ride == null || !mounted) return;
      final ride = next.ride!;

      if (ride.status == RideStatus.completed && !_showCompletionDialog) {
        _navigateToCompletion(ride);
      }

      if (ride.status == RideStatus.noDriverAvailable &&
          !_noDriverPopupShown &&
          mounted) {
        _noDriverPopupShown = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final c = _c;
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => AlertDialog(
              backgroundColor: c.surfaceLow,
              title: Text(
                'AUCUN COMMANDANT',
                style: GoogleFonts.spaceGrotesk(
                    color: c.onSurface, fontWeight: FontWeight.w800),
              ),
              content: Text(
                'Aucun chauffeur disponible dans votre zone. Réessayez dans quelques minutes.',
                style: GoogleFonts.inter(color: c.onSurfaceVariant),
              ),
              actions: [
                GestureDetector(
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).popUntil((r) => r.isFirst);
                    ref.read(activeRideProvider.notifier).clearRide();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                    color: c.primary,
                    child: Text(
                      'RETOUR',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: c.onPrimary,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        });
      }

      if (ride.status == RideStatus.cancelled && mounted) {
        Navigator.of(context).popUntil((r) => r.isFirst);
        ref.read(activeRideProvider.notifier).clearRide();
      }
    });

    final tileUrl = _isDark
        ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png'
        : 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png';

    // Loading
    if ((rideState.isLoading || rideState.isWatching) &&
        rideState.ride == null) {
      return Scaffold(
        backgroundColor: _c.bg,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                    color: _c.primary, strokeWidth: 2),
              ),
              const SizedBox(height: 16),
              Text(
                'INITIALISATION...',
                style: GoogleFonts.spaceGrotesk(
                    color: _c.onSurfaceVariant, fontSize: 11, letterSpacing: 2),
              ),
            ],
          ),
        ),
      );
    }

    // Error
    if (rideState.error != null && rideState.ride == null) {
      return _buildErrorScreen(rideState.error!);
    }

    // No ride — navigate home
    if (rideState.ride == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
      });
      return Scaffold(
        backgroundColor: _c.bg,
        body: Center(
          child: CircularProgressIndicator(color: _c.primary),
        ),
      );
    }

    final ride = rideState.ride!;
    final statusInfo = _getStatusInfo(ride.status);
    final canCancel = ride.status == RideStatus.requested ||
        ride.status == RideStatus.accepted ||
        ride.status == RideStatus.arriving ||
        ride.status == RideStatus.arrived;
    final timerStart = ride.status == RideStatus.started
        ? (ride.startedAt ?? ride.requestedAt)
        : ride.requestedAt;

    return Scaffold(
      backgroundColor: _c.bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(),
            Expanded(
              child: Stack(
                children: [
                  _buildMap(ride, tileUrl),
                  // Status banner — top overlay
                  Positioned(
                    top: 16,
                    left: 16,
                    right: 16,
                    child: _buildStatusBanner(
                      statusInfo: statusInfo,
                      isWatching: rideState.isWatching,
                      showTimer: statusInfo['showTimer'] as bool,
                      timerStart: timerStart,
                    ),
                  ),
                  // Side action buttons
                  Positioned(
                    right: 16,
                    top: 0,
                    bottom: 0,
                    child: Align(
                      alignment: Alignment.center,
                      child: _buildSideActions(),
                    ),
                  ),
                  // Bottom control panel
                  Positioned(
                    bottom: 16,
                    left: 16,
                    right: 16,
                    child: _buildBottomPanel(ride, canCancel),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── App Bar ──────────────────────────────────────────────────

  Widget _buildAppBar() {
    return Container(
      color: _c.bg,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        children: [
          Text(
            'KINETIC_DRIVE',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: _c.primary,
              letterSpacing: -0.5,
            ),
          ),
          const Spacer(),
          Icon(Icons.settings_outlined, color: _c.onSurfaceVariant),
        ],
      ),
    );
  }

  // ── Full-screen Map ──────────────────────────────────────────

  Widget _buildMap(Ride ride, String tileUrl) {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: LatLng(ride.pickup.latitude, ride.pickup.longitude),
        initialZoom: 14,
      ),
      children: [
        TileLayer(
          urlTemplate: tileUrl,
          subdomains: const ['a', 'b', 'c', 'd'],
        ),
        MarkerLayer(
          markers: [
            Marker(
              point: LatLng(ride.pickup.latitude, ride.pickup.longitude),
              width: 36,
              height: 36,
              child: Container(
                color: _c.primary,
                child: Icon(Icons.location_on,
                    color: _c.onPrimary, size: 22),
              ),
            ),
            Marker(
              point:
                  LatLng(ride.destination.latitude, ride.destination.longitude),
              width: 36,
              height: 36,
              child: Container(
                color: _c.onSurface,
                child: Icon(Icons.flag, color: _c.bg, size: 22),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Status Banner ────────────────────────────────────────────

  Widget _buildStatusBanner({
    required Map<String, dynamic> statusInfo,
    required bool isWatching,
    required bool showTimer,
    required DateTime timerStart,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _c.surfaceTop.withValues(alpha: 0.88),
        border: Border(left: BorderSide(color: _c.primary, width: 4)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _c.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        statusInfo['label'] as String,
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: _c.primary,
                          letterSpacing: 2,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  statusInfo['text'] as String,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: _c.onSurface,
                    letterSpacing: -0.3,
                  ),
                ),
                if (showTimer) ...[
                  const SizedBox(height: 4),
                  _ElapsedTimer(startTime: timerStart, color: _c.primary),
                ],
              ],
            ),
          ),
          Container(
            width: 40,
            height: 40,
            color: _c.surfaceTop,
            child: Icon(
              isWatching
                  ? Icons.notifications_active
                  : Icons.notifications_outlined,
              color: _c.onSurfaceVariant,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }

  // ── Side Buttons ─────────────────────────────────────────────

  Widget _buildSideActions() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _sideBtn(Icons.my_location),
        const SizedBox(height: 8),
        _sideBtn(Icons.layers_outlined),
      ],
    );
  }

  Widget _sideBtn(IconData icon) {
    return Container(
      width: 48,
      height: 48,
      color: _c.surfaceTop.withValues(alpha: 0.88),
      child: Icon(icon, color: _c.onSurface, size: 22),
    );
  }

  // ── Plaque d'immatriculation + bouton de suivi ───────────────
  // La plaque n'est pas sur la course : `Ride.vehicleId` est écrit à null par
  // ride_service. On la lit sur le document chauffeur, en lecture pour tout
  // client authentifié (firestore.rules). Si le chauffeur ne l'a pas
  // renseignée, le bouton de suivi prend toute la largeur plutôt que de
  // laisser un encart vide.
  Widget _buildPlateAndTrackRow(Ride ride) {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: _driverDoc(ride.driverId!),
      builder: (context, snap) {
        final plate = (snap.data?.data()?['licensePlate'] as String?)?.trim();
        final hasPlate = plate != null && plate.isNotEmpty;

        if (!hasPlate) return _buildTrackDriverButton(ride);

        return Row(
          children: [
            Expanded(flex: 2, child: _buildPlateChip(plate)),
            const SizedBox(width: 8),
            Expanded(child: _buildTrackDriverButton(ride)),
          ],
        );
      },
    );
  }

  Widget _buildPlateChip(String plate) {
    return Container(
      color: _c.surfaceTop,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Icon(Icons.directions_car_outlined,
              color: _c.onSurfaceVariant, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              plate.toUpperCase(),
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _c.onSurface,
                letterSpacing: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Bouton "voir la position du chauffeur" ───────────────────
  Widget _buildTrackDriverButton(Ride ride) {
    // Avant le départ le chauffeur roule vers le pickup ; une fois la course
    // lancée, vers la destination.
    final enRouteVersClient = ride.status == RideStatus.accepted ||
        ride.status == RideStatus.arriving ||
        ride.status == RideStatus.arrived;
    final cible = enRouteVersClient ? ride.pickup : ride.destination;

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TrackDriverScreen(
            driverId: ride.driverId!,
            driverName: ride.driverName,
            target: LatLng(cible.latitude, cible.longitude),
            targetLabel: enRouteVersClient ? 'Vous' : 'la destination',
          ),
        ),
      ),
      child: Container(
        color: _c.surfaceTop,
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.map_outlined, color: _c.primary, size: 16),
            const SizedBox(width: 6),
            Text(
              'SUIVRE',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: _c.primary,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Bottom Control Panel ─────────────────────────────────────

  Widget _buildBottomPanel(Ride ride, bool canCancel) {
    final fare = ride.finalFare?.toStringAsFixed(0) ??
        ride.estimatedFare.toStringAsFixed(0);

    return Container(
      color: _c.surfaceLow,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Driver info row
          Row(
            children: [
              Container(
                width: 64,
                height: 64,
                color: _c.surfaceTop,
                child: ride.driverPhotoUrl != null &&
                        ride.driverPhotoUrl!.isNotEmpty
                    ? Image.network(
                        ride.driverPhotoUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Icon(
                            Icons.person,
                            color: _c.onSurfaceVariant,
                            size: 32),
                      )
                    : Icon(Icons.person,
                        color: _c.onSurfaceVariant, size: 32),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Commandant de bord',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: _c.onSurfaceVariant,
                        letterSpacing: 1.5,
                      ),
                    ),
                    Text(
                      (ride.driverName ?? 'EN ATTENTE').toUpperCase(),
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: _c.onSurface,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Tarif estimé',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: _c.onSurfaceVariant,
                      letterSpacing: 1.5,
                    ),
                  ),
                  Text(
                    '$fare FDJ',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: _c.primary,
                      letterSpacing: -1,
                    ),
                  ),
                ],
              ),
            ],
          ),

          // Phone + Call button (shown when driver assigned)
          if (ride.hasDriver) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Container(
                    color: _c.surfaceTop,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    child: Row(
                      children: [
                        Icon(Icons.phone_outlined,
                            color: _c.onSurfaceVariant, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            ride.driverPhone ?? '---',
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: _c.onSurface,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      if (ride.driverPhone != null) {
                        launchUrl(Uri.parse('tel:${ride.driverPhone}'));
                      }
                    },
                    child: Container(
                      color: _c.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Center(
                        child: Text(
                          'APPELER',
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            color: _c.onPrimary,
                            letterSpacing: 2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // Plaque + suivi carte du chauffeur
            const SizedBox(height: 8),
            _buildPlateAndTrackRow(ride),
          ],

          // Status strip + cancel
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                color: _c.primary.withValues(alpha: 0.1),
                child: Text(
                  'SYSTEM_STABLE',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: _c.primary,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                color: _c.surfaceTop,
                child: Text(
                  'EN_ROUTE',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: _c.onSurfaceVariant,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
              const Spacer(),
              if (canCancel)
                GestureDetector(
                  onTap: _cancelRide,
                  child: Text(
                    'ANNULER',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: _c.error,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Error Screen ─────────────────────────────────────────────

  Widget _buildErrorScreen(String error) {
    return Scaffold(
      backgroundColor: _c.bg,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: _c.error),
              const SizedBox(height: 16),
              Text(
                'ERREUR_SYSTÈME',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _c.error,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                error,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(color: _c.onSurfaceVariant, fontSize: 14),
              ),
              const SizedBox(height: 24),
              GestureDetector(
                onTap: () =>
                    Navigator.of(context).popUntil((r) => r.isFirst),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 32, vertical: 16),
                  color: _c.primary,
                  child: Text(
                    'RETOUR',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: _c.onPrimary,
                      letterSpacing: 2,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// ELAPSED TIMER
// ════════════════════════════════════════════════════════════

class _ElapsedTimer extends StatefulWidget {
  final DateTime startTime;
  final Color    color;
  const _ElapsedTimer({required this.startTime, required this.color});

  @override
  State<_ElapsedTimer> createState() => _ElapsedTimerState();
}

class _ElapsedTimerState extends State<_ElapsedTimer> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final diff = DateTime.now().difference(widget.startTime);
    final text = diff.inMinutes < 1
        ? '${diff.inSeconds}s'
        : diff.inHours < 1
            ? '${diff.inMinutes}min'
            : '${diff.inHours}h ${diff.inMinutes.remainder(60)}min';
    return Text(
      text,
      style: GoogleFonts.spaceGrotesk(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: widget.color,
        letterSpacing: 1,
      ),
    );
  }
}
