import 'package:cloud_firestore/cloud_firestore.dart';
import '../data/mock_taxi_data.dart';
import '../models/ride_choice.dart';

/// Barème d'un type de véhicule, tel que stocké dans `config/taxiPricing`.
class TaxiTariff {
  const TaxiTariff({
    required this.basePrice,
    required this.includedKm,
    required this.pricePerKm,
  });

  final double basePrice;
  final double includedKm;
  final double pricePerKm;

  /// Un barème incomplet ou à zéro est rejeté au profit du repli local :
  /// mieux vaut un tarif figé correct qu'un tarif nul affiché au client.
  bool get isUsable => basePrice > 0 && pricePerKm > 0 && includedKm >= 0;

  static TaxiTariff? fromMap(dynamic raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final tariff = TaxiTariff(
      basePrice: (map['basePrice'] as num?)?.toDouble() ?? 0,
      includedKm: (map['includedKm'] as num?)?.toDouble() ?? 0,
      pricePerKm: (map['pricePerKm'] as num?)?.toDouble() ?? 0,
    );
    return tariff.isUsable ? tariff : null;
  }
}

/// Tarifs VTC pilotés depuis Firestore (`config/taxiPricing`).
///
/// Les Cloud Functions `onTaxiRideCreated` / `onRideUpdated` recalculent
/// `estimatedFare` et `finalFare` depuis ce même document : lire la config
/// plutôt que coder un barème en dur est ce qui garantit que le prix **affiché**
/// au client correspond au prix **facturé**.
class TaxiPricingService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Clé Firestore correspondant à chaque véhicule du catalogue local.
  static const Map<RideType, String> _tierKeys = {
    RideType.standard: 'standard',
    RideType.comfort: 'comfort',
  };

  /// Flux temps réel du catalogue tarifé.
  ///
  /// Le document peut ne pas exister tant que personne n'a sauvegardé depuis
  /// l'écran admin : dans ce cas — comme en cas de champ manquant ou d'erreur
  /// de lecture — on renvoie le catalogue de repli, véhicule par véhicule.
  Stream<List<RideChoice>> watchRideChoices() {
    return _db
        .collection('config')
        .doc('taxiPricing')
        .snapshots()
        .map((doc) => _merge(doc.data()));
  }

  /// Applique le barème Firestore au catalogue local (images, noms, places et
  /// options restent locaux ; seuls les prix viennent de la config).
  static List<RideChoice> _merge(Map<String, dynamic>? data) {
    return MockTaxiData.rideChoices.map((choice) {
      final key = _tierKeys[choice.type];
      final tariff =
          (key == null || data == null) ? null : TaxiTariff.fromMap(data[key]);
      if (tariff == null) return choice; // repli local pour CE véhicule
      return choice.copyWith(
        basePrice: tariff.basePrice,
        includedKm: tariff.includedKm,
        pricePerKm: tariff.pricePerKm,
      );
    }).toList();
  }
}
