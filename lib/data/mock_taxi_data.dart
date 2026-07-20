import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:nomade_client/models/place.dart';
import 'package:nomade_client/models/ride_choice.dart';

/// Données mockées pour le module Taxi
/// Ces données seront remplacées par de vraies données GPS/API plus tard
class MockTaxiData {
  // ========== POSITIONS GPS ==========

  /// Position par défaut : Centre de Djibouti-Ville
  static const djiboutiCenter = LatLng(11.5721, 43.1456);

  /// Position actuelle de l'utilisateur (mockée)
  static const currentUserPosition = LatLng(11.5880, 43.1450);

  // ========== LIEUX POPULAIRES ==========

  /// Liste des lieux populaires à Djibouti
  static final List<Place> popularPlaces = [
    Place(
      id: 'place_1',
      name: 'Place Mahmoud Harbi',
      location: const LatLng(11.5947, 43.1486),
      address: 'Centre-ville, Djibouti',
      type: PlaceType.suggestion,
      icon: Icons.location_city,
      distance: 2.1,
    ),
    Place(
      id: 'place_2',
      name: 'Port de Djibouti',
      location: const LatLng(11.5913, 43.1547),
      address: 'Zone portuaire, Djibouti',
      type: PlaceType.suggestion,
      icon: Icons.directions_boat,
      distance: 3.5,
    ),
    Place(
      id: 'place_3',
      name: 'Aéroport International',
      location: const LatLng(11.5473, 43.1595),
      address: 'Aéroport Ambouli, Djibouti',
      type: PlaceType.suggestion,
      icon: Icons.flight,
      distance: 8.2,
    ),
    Place(
      id: 'place_4',
      name: 'Stade du Ville',
      location: const LatLng(11.5850, 43.1520),
      address: 'Quartier 7, Djibouti',
      type: PlaceType.suggestion,
      icon: Icons.stadium,
      distance: 1.8,
    ),
    Place(
      id: 'place_5',
      name: 'Marché Central',
      location: const LatLng(11.5920, 43.1470),
      address: 'Centre commercial, Djibouti',
      type: PlaceType.suggestion,
      icon: Icons.shopping_bag,
      distance: 1.5,
    ),
    Place(
      id: 'place_6',
      name: 'Palais du Peuple',
      location: const LatLng(11.5895, 43.1455),
      address: 'Plateau du Serpent, Djibouti',
      type: PlaceType.suggestion,
      icon: Icons.account_balance,
      distance: 1.2,
    ),
  ];

  // ========== LIEUX RÉCENTS ==========

  /// Liste des lieux récents de l'utilisateur
  static final List<Place> recentPlaces = [
    Place(
      id: 'recent_1',
      name: 'Marché Central',
      location: const LatLng(11.5920, 43.1470),
      address: 'Centre commercial, Djibouti',
      type: PlaceType.recent,
      icon: Icons.access_time,
      distance: 1.5,
    ),
    Place(
      id: 'recent_2',
      name: 'Aéroport International',
      location: const LatLng(11.5473, 43.1595),
      address: 'Aéroport Ambouli, Djibouti',
      type: PlaceType.recent,
      icon: Icons.access_time,
      distance: 8.2,
    ),
    Place(
      id: 'recent_3',
      name: 'Port de Djibouti',
      location: const LatLng(11.5913, 43.1547),
      address: 'Zone portuaire, Djibouti',
      type: PlaceType.recent,
      icon: Icons.access_time,
      distance: 3.5,
    ),
  ];

  // ========== LIEUX SAUVEGARDÉS ==========

  /// Lieux sauvegardés de l'utilisateur
  static final List<Place> savedPlaces = [
    Place(
      id: 'saved_home',
      name: 'Maison',
      location: const LatLng(11.5880, 43.1450),
      address: 'Quartier 4, Djibouti',
      type: PlaceType.saved,
      icon: Icons.home,
      distance: 0.0,
    ),
    Place(
      id: 'saved_work',
      name: 'Travail',
      location: const LatLng(11.5947, 43.1486),
      address: 'Place Mahmoud Harbi, Djibouti',
      type: PlaceType.saved,
      icon: Icons.work,
      distance: 2.1,
    ),
  ];

  // ========== TYPES DE VÉHICULES ==========

  /// Liste des types de véhicules disponibles
  static final List<RideChoice> rideChoices = [
    const RideChoice(
      id: 'taxi_standard',
      name: 'Taxi Standard',
      type: RideType.standard,
      imagePath: 'assets/vehicule/taxi-B.png',
      seats: 4,
      basePrice: 500,
      pricePerKm: 200,
      estimatedArrivalTime: '~5 min',
      description: 'Économique et rapide',
      features: ['4 places'],
    ),
    const RideChoice(
      id: 'taxi_comfort',
      name: 'Taxi Confort',
      type: RideType.comfort,
      imagePath: 'assets/vehicule/taxi-A.png',
      seats: 4,
      basePrice: 650,
      pricePerKm: 200,
      estimatedArrivalTime: '~7 min',
      description: 'Plus de confort pour vos trajets',
      features: ['Climatisation', 'WiFi', 'Eau fraîche'],
    ),
  ];

  // ========== SUGGESTIONS DE DESTINATIONS ==========

  /// Suggestions basées sur l'heure et la popularité
  static List<Place> getSuggestions() {
    // Pour l'instant, on retourne juste les 4 premiers lieux populaires
    return popularPlaces.take(4).toList();
  }

  // ========== RECHERCHE MOCKÉE ==========

  /// Recherche de lieux (version mockée)
  /// Retourne des résultats filtrés selon la query
  static List<Place> searchPlaces(String query) {
    if (query.isEmpty) return [];

    final lowerQuery = query.toLowerCase();

    // Filtrer tous les lieux selon la recherche
    final allPlaces = [
      ...popularPlaces,
      ...savedPlaces,
    ];

    return allPlaces
        .where((place) =>
            place.name.toLowerCase().contains(lowerQuery) ||
            (place.address?.toLowerCase().contains(lowerQuery) ?? false))
        .toList();
  }

  // ========== TRAJET MOCKÉ ==========

  /// Obtenir un trajet mocké entre 2 points
  static Map<String, dynamic> getMockedTrip({
    required LatLng departure,
    required LatLng destination,
  }) {
    // Calcul simple de distance (à vol d'oiseau)
    final distance = _calculateDistance(departure, destination);

    // Estimation du temps (50 km/h en moyenne)
    final durationMinutes = (distance / 50 * 60).round();

    return {
      'distance': distance,
      'duration': durationMinutes,
    };
  }

  // ========== CALCULS ==========

  /// Calculer la distance entre 2 points (formule de Haversine simplifiée)
  static double _calculateDistance(LatLng from, LatLng to) {
    const Distance distance = Distance();
    return distance.as(LengthUnit.Kilometer, from, to);
  }

  /// Obtenir le véhicule par défaut
  static RideChoice get defaultRideChoice => rideChoices.first;

  /// Obtenir tous les véhicules
  static List<RideChoice> get allRideChoices => rideChoices;
}
