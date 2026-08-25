import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
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

  /// Construit un barème en repartant du véhicule local pour tout champ absent.
  ///
  /// Repli **champ par champ** et non tout-ou-rien : un document admin qui ne
  /// renseigne qu'une partie des valeurs doit quand même appliquer ce qu'il
  /// contient. Seul un `basePrice` nul ou négatif fait rejeter le barème —
  /// `pricePerKm` à 0 est légitime (tarif forfaitaire) et ne doit surtout pas
  /// provoquer un retour silencieux aux prix codés en dur.
  static TaxiTariff? fromMap(dynamic raw, RideChoice fallback) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);

    final tariff = TaxiTariff(
      basePrice:
          (map['basePrice'] as num?)?.toDouble() ?? fallback.basePrice,
      includedKm:
          (map['includedKm'] as num?)?.toDouble() ?? fallback.includedKm,
      pricePerKm:
          (map['pricePerKm'] as num?)?.toDouble() ?? fallback.pricePerKm,
    );

    if (tariff.basePrice <= 0 || tariff.pricePerKm < 0 ||
        tariff.includedKm < 0) {
      if (kDebugMode) {
        debugPrint('⚠️ [TaxiPricing] barème rejeté (valeurs invalides): $map');
      }
      return null;
    }
    return tariff;
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
        .map((doc) {
      if (!doc.exists) {
        if (kDebugMode) {
          debugPrint('⚠️ [TaxiPricing] config/taxiPricing INEXISTANT '
              '→ repli local (prix codés en dur)');
        }
        return MockTaxiData.rideChoices;
      }
      final data = doc.data();
      if (kDebugMode) {
        debugPrint('✅ [TaxiPricing] config/taxiPricing lu, clés: '
            '${data?.keys.toList()}');
      }
      return merge(data);
    }).transform(
      // `handleError` avalait l'erreur sans rien émettre : Firestore terminant
      // le flux sur échec, le provider restait indéfiniment en chargement et
      // aucun consommateur ne pouvait voir la panne. On journalise PUIS on
      // émet explicitement le repli, pour que l'app reste utilisable.
      StreamTransformer<List<RideChoice>, List<RideChoice>>.fromHandlers(
        handleError: (error, stackTrace, sink) {
          if (kDebugMode) {
            debugPrint('❌ [TaxiPricing] lecture échouée: $error');
          }
          sink.add(MockTaxiData.rideChoices);
        },
      ),
    );
  }

  /// Applique le barème Firestore au catalogue local (images, noms, places et
  /// options restent locaux ; seuls les prix viennent de la config).
  @visibleForTesting
  static List<RideChoice> merge(Map<String, dynamic>? data) {
    return MockTaxiData.rideChoices.map((choice) {
      final key = _tierKeys[choice.type];
      final tariff = (key == null || data == null)
          ? null
          : TaxiTariff.fromMap(data[key], choice);
      if (tariff == null) {
        if (kDebugMode) {
          debugPrint('⚠️ [TaxiPricing] pas de barème exploitable pour "$key" '
              '→ repli local ${choice.basePrice}/${choice.includedKm}km/'
              '${choice.pricePerKm}');
        }
        return choice; // repli local pour CE véhicule
      }
      if (kDebugMode) {
        debugPrint('✅ [TaxiPricing] $key = ${tariff.basePrice} base, '
            '${tariff.includedKm} km inclus, ${tariff.pricePerKm}/km');
      }
      return choice.copyWith(
        basePrice: tariff.basePrice,
        includedKm: tariff.includedKm,
        pricePerKm: tariff.pricePerKm,
      );
    }).toList();
  }
}
