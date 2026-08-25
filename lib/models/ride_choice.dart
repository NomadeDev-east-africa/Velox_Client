/// Représente un choix de véhicule pour la course
class RideChoice {
  /// Constructeur
  const RideChoice({
    required this.id,
    required this.name,
    required this.type,
    required this.imagePath,
    required this.seats,
    required this.basePrice,
    required this.pricePerKm,
    this.includedKm = 0,
    this.estimatedArrivalTime,
    this.description,
    this.features,
  });

  /// ID unique du type de véhicule
  final String id;

  /// Nom du type (ex: "Taxi Standard")
  final String name;

  /// Type de véhicule
  final RideType type;

  /// Chemin de l'image du véhicule
  final String imagePath;

  /// Nombre de places
  final int seats;

  /// Prix de base (FDJ)
  final double basePrice;

  /// Prix par kilomètre (FDJ), facturé au-delà de [includedKm]
  final double pricePerKm;

  /// Kilomètres déjà couverts par [basePrice]
  final double includedKm;

  /// Temps d'arrivée estimé (ex: "5 min")
  final String? estimatedArrivalTime;

  /// Description courte
  final String? description;

  /// Caractéristiques (ex: ["Climatisation", "WiFi"])
  final List<String>? features;

  /// Calculer le prix total selon la distance.
  ///
  /// Formule partagée avec l'app Android et les Cloud Functions
  /// (`onTaxiRideCreated` / `onRideUpdated` recalculent `estimatedFare` et
  /// `finalFare` avec exactement ce calcul) : toute divergence ferait afficher
  /// au client un prix différent de celui qui lui est facturé.
  double calculatePrice(double distanceKm) {
    final billableKm = distanceKm - includedKm;
    return basePrice + pricePerKm * (billableKm > 0 ? billableKm : 0);
  }

  /// Copie avec modifications
  RideChoice copyWith({
    String? id,
    String? name,
    RideType? type,
    String? imagePath,
    int? seats,
    double? basePrice,
    double? pricePerKm,
    double? includedKm,
    String? estimatedArrivalTime,
    String? description,
    List<String>? features,
  }) {
    return RideChoice(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      imagePath: imagePath ?? this.imagePath,
      seats: seats ?? this.seats,
      basePrice: basePrice ?? this.basePrice,
      pricePerKm: pricePerKm ?? this.pricePerKm,
      includedKm: includedKm ?? this.includedKm,
      estimatedArrivalTime: estimatedArrivalTime ?? this.estimatedArrivalTime,
      description: description ?? this.description,
      features: features ?? this.features,
    );
  }
}

/// Types de véhicules disponibles
enum RideType {
  /// Taxi standard (économique)
  standard,

  /// Taxi confort (milieu de gamme)
  comfort,

  /// Taxi van (pour groupes)
  van,

  /// Taxi premium (luxe)
  premium,
}
