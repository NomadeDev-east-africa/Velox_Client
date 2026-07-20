import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'dart:math' show cos, sqrt, asin;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/secrets.dart';

/// Cause précise d'un échec de localisation. Permet à l'UI de proposer la
/// bonne action (ouvrir les réglages GPS vs les réglages de l'app) au lieu
/// d'un message d'erreur générique.
enum LocationFailure {
  /// GPS désactivé sur l'appareil → réglages système de localisation.
  serviceDisabled,

  /// Permission refusée pour cette fois → on peut redemander.
  permissionDenied,

  /// Permission refusée définitivement → seuls les réglages de l'app aident.
  permissionDeniedForever,

  /// GPS activé et autorisé mais position introuvable (timeout, pas de signal).
  unavailable,
}

class LocationException implements Exception {
  final LocationFailure reason;
  final String message;

  const LocationException(this.reason, this.message);

  @override
  String toString() => message;
}

/// Entrée de cache avec timestamp
class CacheEntry {
  final String address;
  final DateTime timestamp;
  static const Duration cacheDuration = Duration(days: 30);

  CacheEntry(this.address, this.timestamp);

  bool get isValid => DateTime.now().difference(timestamp) < cacheDuration;

  Map<String, dynamic> toMap() => {
        'address': address,
        'timestamp': timestamp.toIso8601String(),
      };

  static CacheEntry fromMap(Map<String, dynamic> map) => CacheEntry(
        map['address'],
        DateTime.parse(map['timestamp']),
      );
}

/// Service de géolocalisation et routing
///
/// BUG 5 CORRIGÉ : Miroirs Nominatim morts tentés en premier
///
/// PROBLÈME ORIGINAL :
///   La liste _nominatimMirrors avait .org en index 0, MAIS _getNextMirror()
///   incrémentait AVANT de retourner → premier appel retournait index 1
///   (letsintegrate.de), mort depuis Djibouti → 2s de délai inutile.
///
/// FIX :
///   1. Liste réduite à un seul miroir : nominatim.openstreetmap.org
///      (seul fonctionnel depuis Djibouti d'après les logs).
///   2. _getNextMirror() remplacé par _getCurrentMirror() qui NE tourne plus
///      — inutile avec un seul miroir fiable.
///   3. _maxMirrorAttempts réduit à 1 (pas de rotation inutile).
///   4. _hasInternetConnection() utilise le même miroir pour le test de connectivité.
class LocationService {
  static const String _openRouteServiceKey = AppSecrets.openRouteServiceKey;

  // ════════════════════════════════════════════════════════════
  // BUG 5 FIX — Miroirs Nominatim
  // ════════════════════════════════════════════════════════════
  //
  // AVANT (cassé) :
  //   static const List<String> _nominatimMirrors = [
  //     'https://nominatim.openstreetmap.org',   ← index 0
  //     'https://nominatim.letsintegrate.de',    ← index 1 (MORT depuis Djibouti)
  //     'https://nominatim.openstreetmap.fr',    ← index 2 (MORT depuis Djibouti)
  //     'https://nominatim.openstreetmap.ch',    ← index 3 (MORT depuis Djibouti)
  //   ];
  //   static int _currentMirrorIndex = 0;
  //   static String _getNextMirror() {
  //     _currentMirrorIndex = (_currentMirrorIndex + 1) % 4; // ← incrémente AVANT
  //     return _nominatimMirrors[_currentMirrorIndex]; // → retourne index 1 au 1er appel !
  //   }
  //
  // APRÈS (correct) :
  //   Un seul miroir fiable → pas de rotation, pas de délai.
  //   Si .org est down (rare), le fallback local géographique prend le relais.
  // ════════════════════════════════════════════════════════════

  static const String _nominatimBaseUrl =
      'https://nominatim.openstreetmap.org';

  // Rate limiting Nominatim : 1 req/seconde max (règles OSM)
  static DateTime? _lastNominatimRequest;
  static const Duration _rateLimitDelay = Duration(seconds: 1);

  // ── Cache local ───────────────────────────────────────────────
  static final Map<String, CacheEntry> _addressCache = {};
  static SharedPreferences? _prefs;
  static bool _cacheCleanedThisSession = false;

  // ════════════════════════════════════════════════════════════
  // CACHE
  // ════════════════════════════════════════════════════════════

  static Future<void> _initCache() async {
    if (_prefs != null) return;
    _prefs = await SharedPreferences.getInstance();
    final cachedData = _prefs!.getString('address_cache_v2');
    if (cachedData != null) {
      try {
        final Map<String, dynamic> cache = jsonDecode(cachedData);
        cache.forEach((key, value) {
          try {
            final entry =
                CacheEntry.fromMap(Map<String, dynamic>.from(value as Map));
            if (entry.isValid) _addressCache[key] = entry;
          } catch (e) {
            debugPrint('⚠️ Erreur chargement cache $key: $e');
          }
        });
        debugPrint(
            '📦 Cache chargé: ${_addressCache.length} adresses valides');
      } catch (e) {
        debugPrint('❌ Erreur décodage cache: $e');
      }
    }
  }

  static Future<void> _saveCache() async {
    await _initCache();
    final cacheMap = <String, dynamic>{};
    _addressCache.forEach((key, entry) {
      cacheMap[key] = entry.toMap();
    });
    await _prefs!.setString('address_cache_v2', jsonEncode(cacheMap));
  }

  static Future<void> _cleanExpiredCache() async {
    await _initCache();
    final expiredKeys = _addressCache.entries
        .where((e) => !e.value.isValid)
        .map((e) => e.key)
        .toList();
    for (final key in expiredKeys) {
      _addressCache.remove(key);
    }
    if (expiredKeys.isNotEmpty) {
      debugPrint(
          '🧹 Cache nettoyé: ${expiredKeys.length} entrées expirées');
      await _saveCache();
    }
  }

  // ════════════════════════════════════════════════════════════
  // GPS
  // ════════════════════════════════════════════════════════════

  Future<LocationData> getCurrentLocation() async {
    debugPrint('📍 Début getCurrentLocation');

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw const LocationException(
        LocationFailure.serviceDisabled,
        'Les services de localisation sont désactivés',
      );
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      debugPrint('🔒 Demande de permission...');
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw const LocationException(
          LocationFailure.permissionDenied,
          'Permissions de localisation refusées',
        );
      }
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationException(
        LocationFailure.permissionDeniedForever,
        'Permissions de localisation refusées définitivement',
      );
    }

    try {
      debugPrint('📡 Récupération position GPS...');
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          timeLimit: Duration(seconds: 25),
        ),
      );

      debugPrint(
          '✅ GPS obtenu: ${position.latitude}, ${position.longitude}');
      return LocationData(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
      );
    } catch (e) {
      debugPrint('❌ Erreur getCurrentLocation: $e');
      throw LocationException(
        LocationFailure.unavailable,
        'Position introuvable. Vérifiez que vous captez le GPS.',
      );
    }
  }

  /// Ouvre les réglages système de localisation de l'appareil.
  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();

  /// Ouvre la fiche réglages de l'app (permission refusée définitivement).
  Future<bool> openAppSettings() => Geolocator.openAppSettings();

  Stream<LocationData> watchLocation() {
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).map((position) => LocationData(
          latitude: position.latitude,
          longitude: position.longitude,
          accuracy: position.accuracy,
        ));
  }

  double calculateDistance(
      double lat1, double lon1, double lat2, double lon2) {
    const p = 0.017453292519943295;
    final a = 0.5 -
        cos((lat2 - lat1) * p) / 2 +
        cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(a));
  }

  int calculateETA(double distanceKm,
      {double averageSpeedKmh = 40.0}) {
    return ((distanceKm / averageSpeedKmh) * 60).round();
  }

  // ════════════════════════════════════════════════════════════
  // RATE LIMITING
  // ════════════════════════════════════════════════════════════

  Future<void> _checkRateLimit() async {
    final now = DateTime.now();
    if (_lastNominatimRequest != null) {
      final elapsed = now.difference(_lastNominatimRequest!);
      if (elapsed < _rateLimitDelay) {
        final wait = _rateLimitDelay - elapsed;
        debugPrint('⏳ Rate limiting: attente de ${wait.inMilliseconds}ms');
        await Future.delayed(wait);
      }
    }
    _lastNominatimRequest = DateTime.now();
  }

  // ════════════════════════════════════════════════════════════
  // CONNECTIVITÉ
  // ════════════════════════════════════════════════════════════

  Future<bool> _hasInternetConnection() async {
    try {
      // ✅ BUG 5 FIX : teste directement _nominatimBaseUrl
      final response = await http
          .get(
            Uri.parse(_nominatimBaseUrl),
            headers: {'User-Agent': 'Nomade253App/1.0'},
          )
          .timeout(const Duration(seconds: 4));
      return response.statusCode < 500;
    } catch (e) {
      debugPrint('🌐 Pas de connexion Internet: $e');
      return false;
    }
  }

  // ════════════════════════════════════════════════════════════
  // GEOCODING INVERSE (coordonnées → adresse)
  // ════════════════════════════════════════════════════════════

  Future<String> getAddressFromCoordinates(
      double lat, double lon) async {
    debugPrint('📍 getAddressFromCoordinates: $lat, $lon');

    await _initCache();
    if (!_cacheCleanedThisSession) {
      _cacheCleanedThisSession = true;
      await _cleanExpiredCache();
    }

    // toStringAsFixed(3) = précision ~111m, absorbe le drift GPS sans changer de rue
    final cacheKey =
        '${lat.toStringAsFixed(3)}_${lon.toStringAsFixed(3)}';

    // 1. Cache local
    if (_addressCache.containsKey(cacheKey)) {
      final cached = _addressCache[cacheKey]!;
      debugPrint('📦 Cache hit: "${cached.address}"');
      return cached.address;
    }

    // 2. Connectivité
    final hasInternet = await _hasInternetConnection();
    if (!hasInternet) {
      debugPrint('📡 Pas de connexion — fallback local');
      return _getLocalFallbackAddress(lat, lon);
    }

    // 3. ✅ BUG 5 FIX : appel direct à _nominatimBaseUrl (pas de rotation)
    debugPrint(
        '🌐 Nominatim: $_nominatimBaseUrl');

    try {
      await _checkRateLimit();

      final url = Uri.parse(
        '$_nominatimBaseUrl/reverse'
        '?lat=$lat&lon=$lon&format=json&addressdetails=1',
      );
      debugPrint('🔗 URL: $url');

      final response = await http.get(
        url,
        headers: {
          'User-Agent': 'Nomade253App/1.0',
          'Accept': 'application/json',
          'Accept-Language': 'fr',
        },
      ).timeout(const Duration(seconds: 10));

      debugPrint('📡 Réponse Nominatim: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data =
            jsonDecode(response.body) as Map<String, dynamic>;
        final address = _extractAddressFromData(data, lat, lon);
        debugPrint('✅ Adresse extraite: "$address"');

        _addressCache[cacheKey] = CacheEntry(address, DateTime.now());
        await _saveCache();
        debugPrint('💾 Adresse mise en cache');
        return address;
      } else if (response.statusCode == 429) {
        debugPrint('⚠️ Rate limit 429 — fallback local');
      } else {
        debugPrint(
            '❌ Erreur HTTP ${response.statusCode} — fallback local');
      }
    } on TimeoutException {
      debugPrint('⏰ Timeout Nominatim — fallback local');
    } catch (e) {
      debugPrint('💥 Erreur Nominatim: $e — fallback local');
    }

    return _getLocalFallbackAddress(lat, lon);
  }

  String _extractAddressFromData(
      Map<String, dynamic> data, double lat, double lon) {
    try {
      final displayName = data['display_name'] as String?;
      if (displayName != null && displayName.isNotEmpty) {
        return displayName;
      }

      final address = data['address'] as Map<String, dynamic>?;
      if (address != null) {
        final parts = <String>[];
        if (address['house_number'] != null) {
          parts.add(address['house_number'].toString());
        }
        if (address['road'] != null) parts.add(address['road'].toString());

        if (parts.isNotEmpty) {
          final locality = address['city'] ??
              address['town'] ??
              address['village'] ??
              address['municipality'];
          if (locality != null) {
            final postcode = address['postcode'];
            parts.add(postcode != null
                ? '$postcode $locality'
                : locality.toString());
          }
          return parts.join(', ');
        }
      }
    } catch (e) {
      debugPrint('⚠️ Erreur extraction adresse: $e');
    }
    return '${lat.toStringAsFixed(6)}, ${lon.toStringAsFixed(6)}';
  }

  String _getLocalFallbackAddress(double lat, double lon) {
    if (lat >= 11.5 && lat <= 11.7 && lon >= 43.1 && lon <= 43.2) {
      if (lat < 11.57) return 'Balbala, Djibouti';
      if (lat < 11.58) return 'Quartier 3, Djibouti';
      if (lat < 11.59) return 'Quartier 4, Djibouti';
      if (lat < 11.6)  return 'Plateau du Serpent, Djibouti';
      return 'Centre-ville, Djibouti';
    }
    return '${lat.toStringAsFixed(6)}, ${lon.toStringAsFixed(6)}';
  }

  // ════════════════════════════════════════════════════════════
  // GEOCODING DIRECT (adresse → coordonnées)
  // ════════════════════════════════════════════════════════════

  Future<List<PlaceResult>> searchPlaces(String query) async {
    debugPrint('🔍 searchPlaces: "$query"');

    final hasInternet = await _hasInternetConnection();
    if (!hasInternet) {
      debugPrint('📡 Pas de connexion pour la recherche');
      return [];
    }

    try {
      final encodedQuery = Uri.encodeQueryComponent(query);

      // Priorité aux adresses de Djibouti (résultats restreints via countrycodes=dj)
      await _checkRateLimit();
      final djiboutiResults =
          await _fetchNominatimResults(encodedQuery, restrictToDjibouti: true);
      if (djiboutiResults.isNotEmpty) return djiboutiResults;

      // Fallback mondial : seulement si rien trouvé à Djibouti
      debugPrint('🌍 Aucun résultat à Djibouti — fallback recherche mondiale');
      await _checkRateLimit();
      return await _fetchNominatimResults(encodedQuery, restrictToDjibouti: false);
    } catch (e) {
      debugPrint('⚠️ Erreur searchPlaces: $e');
    }

    debugPrint('❌ searchPlaces échoué');
    return [];
  }

  // ✅ BUG 5 FIX : appel direct à _nominatimBaseUrl
  // Priorise les adresses de Djibouti via countrycodes=dj (le service ne couvre
  // que Djibouti) tout en gardant un fallback mondial pour éviter les recherches
  // "aucun résultat" si Nominatim ne référence pas encore un lieu local précis.
  Future<List<PlaceResult>> _fetchNominatimResults(
    String encodedQuery, {
    required bool restrictToDjibouti,
  }) async {
    final countryFilter = restrictToDjibouti ? '&countrycodes=dj' : '';
    final url = Uri.parse(
      '$_nominatimBaseUrl/search'
      '?q=$encodedQuery&format=json&limit=5&addressdetails=1$countryFilter',
    );
    debugPrint('🔗 URL recherche (${restrictToDjibouti ? "Djibouti" : "monde"}): $url');

    final response = await http.get(
      url,
      headers: {'User-Agent': 'Nomade253App/1.0'},
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) return [];

    final List data = jsonDecode(response.body);
    debugPrint('📦 ${data.length} résultats trouvés');

    final results = data.map<PlaceResult>((item) {
      final name = item['display_name'] ?? 'Lieu inconnu';
      final lat  = double.tryParse(item['lat'].toString()) ?? 0.0;
      final lon  = double.tryParse(item['lon'].toString()) ?? 0.0;

      final cacheKey =
          '${lat.toStringAsFixed(6)}_${lon.toStringAsFixed(6)}';
      if (!_addressCache.containsKey(cacheKey)) {
        _addressCache[cacheKey] = CacheEntry(name, DateTime.now());
      }

      return PlaceResult(name: name, latitude: lat, longitude: lon);
    }).toList();

    await _saveCache();
    return results;
  }

  // ════════════════════════════════════════════════════════════
  // ITINÉRAIRE
  // ════════════════════════════════════════════════════════════

  Future<RouteResult> getRoute({
    required double startLat,
    required double startLon,
    required double endLat,
    required double endLon,
  }) async {
    try {
      final hasInternet = await _hasInternetConnection();
      if (!hasInternet || _openRouteServiceKey.isEmpty) {
        return _getSimpleRoute(startLat, startLon, endLat, endLon);
      }

      debugPrint('🚗 Calcul itinéraire OpenRouteService');
      // ⚠️ Endpoint /geojson : renvoie la géométrie en coordonnées GeoJSON.
      // L'endpoint de base /driving-car renvoie une polyline ENCODÉE (String),
      // que l'ancien code tentait de lire comme un Map → exception → fallback
      // ligne droite traversant bâtiments/rivières. Le suffixe /geojson corrige ça.
      final url = Uri.parse(
          'https://api.openrouteservice.org/v2/directions/driving-car/geojson');

      final response = await http
          .post(
            url,
            headers: {
              'Authorization': _openRouteServiceKey,
              'Content-Type': 'application/json; charset=utf-8',
              'Accept': 'application/json, application/geo+json',
            },
            body: jsonEncode({
              'coordinates': [
                [startLon, startLat],
                [endLon, endLat],
              ],
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data     = jsonDecode(response.body) as Map<String, dynamic>;
        final features = data['features'] as List?;

        if (features != null && features.isNotEmpty) {
          final feature  = features.first as Map<String, dynamic>;
          final geometry = feature['geometry']['coordinates'] as List;

          final coordinates = geometry
              .map((coord) => LocationData(
                    latitude:  (coord[1] as num).toDouble(),
                    longitude: (coord[0] as num).toDouble(),
                  ))
              .toList();

          final summary = (feature['properties']
                  as Map<String, dynamic>?)?['summary']
              as Map<String, dynamic>?;
          final distanceM = (summary?['distance'] as num?)?.toDouble() ?? 0;
          final durationS = (summary?['duration'] as num?)?.toDouble() ?? 0;

          if (coordinates.length >= 2) {
            return RouteResult(
              coordinates: coordinates,
              distance:    distanceM / 1000,
              duration:    (durationS / 60).round(),
            );
          }
        }
        debugPrint('⚠️ Géométrie ORS vide — fallback ligne droite');
      } else {
        debugPrint('⚠️ ORS HTTP ${response.statusCode} — fallback ligne droite');
      }
    } catch (e) {
      debugPrint('⚠️ Route fallback: $e');
    }
    return _getSimpleRoute(startLat, startLon, endLat, endLon);
  }

  RouteResult _getSimpleRoute(
      double startLat, double startLon, double endLat, double endLon) {
    final distance = calculateDistance(startLat, startLon, endLat, endLon);
    return RouteResult(
      coordinates: [
        LocationData(latitude: startLat, longitude: startLon),
        LocationData(latitude: endLat,   longitude: endLon),
      ],
      distance: distance,
      duration: calculateETA(distance),
    );
  }

  // ════════════════════════════════════════════════════════════
  // UTILITAIRES CACHE
  // ════════════════════════════════════════════════════════════

  static Future<void> clearCache() async {
    await _initCache();
    _addressCache.clear();
    await _prefs!.remove('address_cache_v2');
    debugPrint('🗑️ Cache vidé');
  }

  static Future<Map<String, dynamic>> getCacheStats() async {
    await _initCache();
    await _cleanExpiredCache();
    return {
      'total_entries':   _addressCache.length,
      'valid_entries':   _addressCache.values.where((e) => e.isValid).length,
      'expired_entries': _addressCache.values.where((e) => !e.isValid).length,
      'cache_size':      jsonEncode(_addressCache).length,
    };
  }
}

// ════════════════════════════════════════════════════════════
// DATA CLASSES
// ════════════════════════════════════════════════════════════

class LocationData {
  final double latitude;
  final double longitude;
  final double? accuracy;

  const LocationData({
    required this.latitude,
    required this.longitude,
    this.accuracy,
  });
}

class RouteResult {
  final List<LocationData> coordinates;
  final double distance; // km
  final int    duration; // minutes

  const RouteResult({
    required this.coordinates,
    required this.distance,
    required this.duration,
  });
}

class PlaceResult {
  final String name;
  final double latitude;
  final double longitude;

  const PlaceResult({
    required this.name,
    required this.latitude,
    required this.longitude,
  });
}
