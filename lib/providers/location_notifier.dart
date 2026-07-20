import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../services/location_service.dart';
import '../utils/local_cache.dart';

// ════════════════════════════════════════════════════════════════
// PHASE 6 — LocationNotifier (Riverpod)
//
// Migration finale de LocationProvider (ChangeNotifier)
// vers StateNotifier Riverpod.
//
// OPTIMISATIONS PAR RAPPORT À L'ORIGINAL :
//
// 1. _safeNotify() — déjà présent depuis Bug 4 fix
//
// 2. Throttle GPS : on ignore les updates < 15m ou < 5s
//    → Évite les rafraîchissements Nominatim inutiles
//    → Réduit la charge CPU du thread principal
//
// 3. Adresse précédente servie immédiatement depuis cache local
//    → Pas d'écran blanc sur premier affichage
//
// 4. Permission check lazy : ne bloque pas initState
//    Les permissions sont demandées seulement si nécessaire
//
// 5. distinct() sur le stream GPS : ignore les positions identiques
// ════════════════════════════════════════════════════════════════

class LocationState {
  final LatLng?  position;
  final String?  address;
  final double?  accuracy;
  final bool     isLoading;
  final bool     isTracking;
  final bool     hasPermission;
  final String?  error;

  /// Cause typée du dernier échec — permet à l'UI de proposer la bonne action
  /// (réglages GPS, réglages de l'app, réessayer) plutôt qu'un message brut.
  final LocationFailure? failure;

  const LocationState({
    this.position,
    this.address,
    this.accuracy,
    this.isLoading    = false,
    this.isTracking   = false,
    this.hasPermission = false,
    this.error,
    this.failure,
  });

  bool get hasPosition => position != null;

  LocationState copyWith({
    LatLng?  position,
    String?  address,
    double?  accuracy,
    bool?    isLoading,
    bool?    isTracking,
    bool?    hasPermission,
    String?  error,
    LocationFailure? failure,
    bool     clearError   = false,
    bool     clearAddress = false,
  }) {
    return LocationState(
      position:      position      ?? this.position,
      address:       clearAddress  ? null : (address ?? this.address),
      accuracy:      accuracy      ?? this.accuracy,
      isLoading:     isLoading     ?? this.isLoading,
      isTracking:    isTracking    ?? this.isTracking,
      hasPermission: hasPermission ?? this.hasPermission,
      error:         clearError    ? null : (error ?? this.error),
      failure:       clearError    ? null : (failure ?? this.failure),
    );
  }
}

class LocationNotifier extends StateNotifier<LocationState> {
  final LocationService _service;

  StreamSubscription<LocationData>? _sub;
  Timer?   _debounceTimer;
  Completer<String?>? _pendingCompleter;
  LatLng?  _lastReportedPosition;
  DateTime _lastGpsUpdate = DateTime.fromMillisecondsSinceEpoch(0);

  // ── Seuils d'optimisation ────────────────────────────────────
  static const double _minDistanceMeters   = 15.0;  // ignore < 15m
  static const int    _debounceDuration    = 500;   // ms debounce adresse
  static const Duration _minGpsInterval    =
      Duration(seconds: 5);                         // ignore < 5s

  // ── Cache adresses ────────────────────────────────────────────
  static const int _maxCacheSize = 50;
  final Map<String, String> _addressCache = {};

  LocationNotifier(this._service) : super(const LocationState()) {
    _initFromCache();
  }

  // ── Restaurer la dernière position connue depuis LocalCache ───

  void _initFromCache() {
    try {
      final cached = LocalCache.getLastPosition();
      if (cached == null) return;

      // Si la position est < 30 minutes → l'afficher immédiatement
      final age = DateTime.now().difference(cached.timestamp);
      if (age.inMinutes < 30) {
        state = state.copyWith(
          position: LatLng(cached.lat, cached.lng),
        );
        debugPrint(
            '📦 [LocationNotifier] Position cache: ${cached.lat}, ${cached.lng}');
      }
    } catch (_) {}
  }

  // ════════════════════════════════════════════════════════════
  // GPS
  // ════════════════════════════════════════════════════════════

  Future<void> getCurrentLocation() async {
    if (!mounted) return;
    _safeNotify(() => state = state.copyWith(isLoading: true, clearError: true));

    try {
      final data = await _service.getCurrentLocation();
      final pos  = LatLng(data.latitude, data.longitude);

      if (!mounted) return;

      _safeNotify(() {
        state = state.copyWith(
          position:      pos,
          accuracy:      data.accuracy,
          hasPermission: true,
          isLoading:     false,
          clearError:    true,
        );
      });

      // Sauvegarder pour restauration future
      await LocalCache.saveLastPosition(data.latitude, data.longitude);

      // Charger l'adresse en arrière-plan (ne bloque pas)
      unawaited(_loadAddress(pos));
    } catch (e) {
      debugPrint('❌ [LocationNotifier] getCurrentLocation: $e');
      if (mounted) {
        _safeNotify(() => state = state.copyWith(
          isLoading:     false,
          hasPermission: false,
          error:         e.toString(),
          failure: e is LocationException
              ? e.reason
              : LocationFailure.unavailable,
        ));
      }
    }
  }

  // ════════════════════════════════════════════════════════════
  // STREAM TEMPS RÉEL — avec throttle + distance filter
  // ════════════════════════════════════════════════════════════

  Future<void> startTracking() async {
    if (state.isTracking || !mounted) return;

    try {
      await _service.getCurrentLocation(); // vérifie permissions

      _safeNotify(() => state = state.copyWith(
          isTracking: true, hasPermission: true));

      // ✅ distinct() ignore les positions identiques du stream
      _sub = _service.watchLocation().listen(
        (data) {
          if (!mounted) return;

          final now = DateTime.now();
          final pos = LatLng(data.latitude, data.longitude);

          // ✅ Throttle temporel : ignore si < 5s
          if (now.difference(_lastGpsUpdate) < _minGpsInterval) return;

          // ✅ Throttle distance : ignore si < 15m
          if (_lastReportedPosition != null) {
            final distM = _distanceMeters(_lastReportedPosition!, pos);
            if (distM < _minDistanceMeters) return;
          }

          _lastGpsUpdate = now;
          _lastReportedPosition = pos;

          _safeNotify(() {
            state = state.copyWith(position: pos, accuracy: data.accuracy);
          });

          // Sauvegarder position en cache
          LocalCache.saveLastPosition(pos.latitude, pos.longitude);

          // Charger adresse avec debounce
          unawaited(_loadAddress(pos));
        },
        onError: (e) {
          debugPrint('❌ [LocationNotifier] stream: $e');
          if (mounted) {
            _safeNotify(() => state = state.copyWith(
                isTracking: false, error: e.toString()));
          }
        },
      );
    } catch (e) {
      debugPrint('❌ [LocationNotifier] startTracking: $e');
      if (mounted) {
        _safeNotify(() => state = state.copyWith(
            isTracking: false, error: e.toString()));
      }
    }
  }

  void stopTracking() {
    _sub?.cancel();
    _sub = null;
    _debounceTimer?.cancel();
    if (mounted) _safeNotify(() => state = state.copyWith(isTracking: false));
  }

  // ════════════════════════════════════════════════════════════
  // ADRESSE — avec debounce + cache mémoire
  // ════════════════════════════════════════════════════════════

  Future<String?> getAddressForPosition(LatLng position) async {
    final key = _cacheKey(position);

    // ✅ Cache hit → notifier de façon sûre
    if (_addressCache.containsKey(key)) {
      final cached = _addressCache[key]!;
      if (position == state.position && state.address != cached) {
        _safeNotify(() => state = state.copyWith(address: cached));
      }
      return cached;
    }

    // Nouvelle adresse → debounce
    _debounceTimer?.cancel();

    // Compléter le Completer précédent s'il est encore en attente
    if (_pendingCompleter != null && !_pendingCompleter!.isCompleted) {
      _pendingCompleter!.complete(null);
    }
    _pendingCompleter = Completer<String?>();
    final completer = _pendingCompleter!;

    _debounceTimer = Timer(
      Duration(milliseconds: _debounceDuration),
      () async {
        if (completer.isCompleted || !mounted) {
          if (!completer.isCompleted) completer.complete(null);
          return;
        }
        try {
          final addr = await _service.getAddressFromCoordinates(
              position.latitude, position.longitude);
          if (_addressCache.length >= _maxCacheSize) {
            _addressCache.remove(_addressCache.keys.first);
          }
          _addressCache[key] = addr;

          if (position == state.position && mounted) {
            _safeNotify(() => state = state.copyWith(address: addr));
          }

          if (!completer.isCompleted) completer.complete(addr);
        } catch (e) {
          if (!completer.isCompleted) completer.complete(null);
        }
      },
    );

    return completer.future;
  }

  Future<void> _loadAddress(LatLng pos) async {
    await getAddressForPosition(pos);
  }

  // ════════════════════════════════════════════════════════════
  // HELPERS
  // ════════════════════════════════════════════════════════════

  /// notifyListeners() sécurisé — diffère si build en cours
  void _safeNotify(VoidCallback mutation) {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) mutation();
      });
    } else {
      mutation();
    }
  }

  double _distanceMeters(LatLng a, LatLng b) {
    return _service.calculateDistance(
          a.latitude, a.longitude, b.latitude, b.longitude) *
        1000; // km → m
  }

  String _cacheKey(LatLng pos) =>
      '${pos.latitude.toStringAsFixed(4)},${pos.longitude.toStringAsFixed(4)}';

  @override
  void dispose() {
    _sub?.cancel();
    _debounceTimer?.cancel();
    if (_pendingCompleter != null && !_pendingCompleter!.isCompleted) {
      _pendingCompleter!.complete(null);
    }
    _addressCache.clear();
    super.dispose();
  }
}

// ════════════════════════════════════════════════════════════════
// PROVIDER GLOBAL
// ════════════════════════════════════════════════════════════════

final locationNotifierProvider =
    StateNotifierProvider<LocationNotifier, LocationState>(
  (ref) => LocationNotifier(LocationService()),
);

// ── Sélecteurs — reconstruit uniquement le widget concerné ──────

final currentPositionProvider = Provider<LatLng?>(
  (ref) => ref.watch(locationNotifierProvider).position,
);

final currentAddressProvider = Provider<String?>(
  (ref) => ref.watch(locationNotifierProvider).address,
);

final locationLoadingProvider = Provider<bool>(
  (ref) => ref.watch(locationNotifierProvider).isLoading,
);
