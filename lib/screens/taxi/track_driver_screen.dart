import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nomade_client/providers/theme_notifier.dart';
import 'package:nomade_client/theme/app_colors.dart';
import 'package:nomade_client/services/location_service.dart';

/// Suivi temps réel de la position du chauffeur VTC.
/// Ouvert depuis la carte chauffeur de TrackingScreen — pendant que le
/// chauffeur vient vous chercher, puis pendant la course.
///
/// `drivers/{driverId}.currentLocation` est écrit par la Cloud Function
/// `driverHeartbeat` ; la collection est en lecture pour tout client
/// authentifié (cf. firestore.rules).
class TrackDriverScreen extends ConsumerStatefulWidget {
  final String driverId;
  final String? driverName;

  /// Point vers lequel le chauffeur roule : le pickup tant qu'il vient vous
  /// chercher, la destination une fois la course démarrée.
  final LatLng? target;
  final String targetLabel;

  const TrackDriverScreen({
    super.key,
    required this.driverId,
    this.driverName,
    this.target,
    this.targetLabel = 'Vous',
  });

  @override
  ConsumerState<TrackDriverScreen> createState() => _TrackDriverScreenState();
}

class _TrackDriverScreenState extends ConsumerState<TrackDriverScreen> {
  final MapController _mapController = MapController();
  _DriverPosition? _dernierePosition;

  final LocationService _locationService = LocationService();
  List<LatLng> _routePoints = [];
  LatLng? _routeAnchor;
  bool _fetchingRoute = false;

  /// Recalcule la route seulement si le chauffeur a bougé de plus de 40 m,
  /// sinon chaque battement GPS déclencherait un appel réseau.
  Future<void> _maybeUpdateRoute(LatLng driver, LatLng? destination) async {
    if (destination == null || _fetchingRoute) return;
    if (_routePoints.isNotEmpty && _routeAnchor != null) {
      final moved = _locationService.calculateDistance(
        _routeAnchor!.latitude, _routeAnchor!.longitude,
        driver.latitude, driver.longitude,
      );
      if (moved < 0.04) return;
    }
    _fetchingRoute = true;
    try {
      final route = await _locationService.getRoute(
        startLat: driver.latitude,
        startLon: driver.longitude,
        endLat: destination.latitude,
        endLon: destination.longitude,
      );
      if (!mounted) return;
      setState(() {
        _routePoints =
            route.coordinates.map((c) => LatLng(c.latitude, c.longitude)).toList();
        _routeAnchor = driver;
      });
    } catch (_) {
      // Échec réseau : on conserve la route précédente.
    } finally {
      _fetchingRoute = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ref.watch(themeNotifierProvider).isDarkMode;
    final c = isDark ? AppColors.dark : AppColors.light;

    final tileUrl = isDark
        ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png'
        : 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png';

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        foregroundColor: c.primary,
        elevation: 0,
        title: Text(
          'Position du chauffeur',
          style: TextStyle(
            color: c.primary,
            fontWeight: FontWeight.bold,
            fontSize: 16,
            letterSpacing: 0.5,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: c.primary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: StreamBuilder<_DriverPosition?>(
        stream: _watchDriverPosition(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              _dernierePosition == null) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: c.primary),
                  const SizedBox(height: 16),
                  Text(
                    'Localisation du chauffeur...',
                    style: TextStyle(color: c.onSurfaceVariant, fontSize: 14),
                  ),
                ],
              ),
            );
          }

          final position = snapshot.data ?? _dernierePosition;
          if (snapshot.data != null) _dernierePosition = snapshot.data;

          if (position == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.location_off,
                        color: c.onSurfaceVariant.withValues(alpha: 0.5), size: 64),
                    const SizedBox(height: 16),
                    Text(
                      'Position du chauffeur non disponible',
                      style: TextStyle(color: c.onSurfaceVariant, fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Le chauffeur n\'a pas encore activé son suivi GPS. '
                      'Vous pouvez l\'appeler depuis l\'écran précédent.',
                      style: TextStyle(color: c.onSurfaceVariant, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }

          final driverLatLng = LatLng(position.latitude, position.longitude);

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              try {
                _mapController.move(driverLatLng, _mapController.camera.zoom);
              } catch (_) {}
              _maybeUpdateRoute(driverLatLng, widget.target);
            }
          });

          final markers = <Marker>[
            Marker(
              point: driverLatLng,
              width: 48,
              height: 48,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF9FFF88),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF9FFF88).withValues(alpha: 0.4),
                      blurRadius: 12,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Icon(Icons.local_taxi,
                    color: Color(0xFF026400), size: 26),
              ),
            ),
          ];

          if (widget.target != null) {
            markers.add(
              Marker(
                point: widget.target!,
                width: 44,
                height: 44,
                child: const Icon(Icons.person_pin_circle,
                    color: Colors.blue, size: 44),
              ),
            );
          }

          return Column(
            children: [
              Expanded(
                child: FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: driverLatLng,
                    initialZoom: 15,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: tileUrl,
                      subdomains: const ['a', 'b', 'c', 'd'],
                    ),
                    if (_routePoints.length >= 2)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: _routePoints,
                            color: c.primary,
                            strokeWidth: 4,
                            borderColor: Colors.white.withValues(alpha: 0.7),
                            borderStrokeWidth: 2,
                          ),
                        ],
                      ),
                    MarkerLayer(markers: markers),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                decoration: BoxDecoration(
                  color: c.surfaceLow,
                  boxShadow: [
                    BoxShadow(
                      color: c.primary.withValues(alpha: 0.06),
                      blurRadius: 16,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                child: SafeArea(
                  top: false,
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: c.primary.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.local_taxi, color: c.primary, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.driverName ?? 'Chauffeur',
                              style: TextStyle(
                                color: c.onSurface,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Container(
                                  width: 7, height: 7,
                                  decoration: BoxDecoration(
                                    color: c.primary, shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  'En route vers ${widget.targetLabel.toLowerCase()}',
                                  style: TextStyle(
                                    color: c.primary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Text(
                        _formateurHeure(position.miseAJour),
                        style: TextStyle(color: c.onSurfaceVariant, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Stream<_DriverPosition?> _watchDriverPosition() {
    return FirebaseFirestore.instance
        .collection('drivers')
        .doc(widget.driverId)
        .snapshots()
        .map<_DriverPosition?>((doc) {
          if (!doc.exists) return null;
          final data = doc.data()!;
          final raw = data['currentLocation'];

          // Le champ peut être un GeoPoint ou une Map selon l'écriture côté
          // chauffeur — on accepte les deux (même approche que le suivi livreur).
          if (raw is GeoPoint) {
            final ts = data['lastHeartbeat'] ?? data['updatedAt'];
            return _DriverPosition(
              latitude: raw.latitude,
              longitude: raw.longitude,
              miseAJour: ts is Timestamp ? ts.toDate() : DateTime.now(),
            );
          }
          return _extrairePositionDepuisMap(raw);
        });
  }

  _DriverPosition? _extrairePositionDepuisMap(dynamic raw) {
    if (raw is! Map) return null;
    final lat = raw['latitude'];
    final lon = raw['longitude'];
    if (lat == null || lon == null) return null;
    final ts = raw['updatedAt'] ?? raw['lastHeartbeat'];
    return _DriverPosition(
      latitude: (lat as num).toDouble(),
      longitude: (lon as num).toDouble(),
      miseAJour: ts is Timestamp ? ts.toDate() : DateTime.now(),
    );
  }

  String _formateurHeure(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 10) return 'À l\'instant';
    if (diff.inSeconds < 60) return 'Il y a ${diff.inSeconds}s';
    if (diff.inMinutes < 60) return 'Il y a ${diff.inMinutes}min';
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }
}

class _DriverPosition {
  final double latitude;
  final double longitude;
  final DateTime miseAJour;

  const _DriverPosition({
    required this.latitude,
    required this.longitude,
    required this.miseAJour,
  });
}
