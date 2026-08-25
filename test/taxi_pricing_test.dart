import 'package:flutter_test/flutter_test.dart';
import 'package:nomade_client/models/ride_choice.dart';
import 'package:nomade_client/services/taxi_pricing_service.dart';

/// Contenu réel de `config/taxiPricing` en production, relevé le 2026-08-25
/// (le client avait fait passer `includedKm` de 3 à 2.3 le jour même).
///
/// Firestore renvoie `integerValue` en `int` et `doubleValue` en `double` :
/// le mélange des deux types est reproduit tel quel, c'est exactement ce que
/// la couche Dart reçoit.
Map<String, dynamic> get _prodDoc => {
      'standard': {
        'basePrice': 600,
        'includedKm': 2.3,
        'pricePerKm': 200,
      },
      'comfort': {
        'basePrice': 750,
        'includedKm': 2.3,
        'pricePerKm': 200,
      },
      'updatedAt': DateTime(2026, 8, 25),
    };

RideChoice _standard(List<RideChoice> l) =>
    l.firstWhere((c) => c.type == RideType.standard);
RideChoice _comfort(List<RideChoice> l) =>
    l.firstWhere((c) => c.type == RideType.comfort);

void main() {
  group('TaxiPricingService.merge', () {
    test('applique le barème réel de production', () {
      final choices = TaxiPricingService.merge(_prodDoc);

      final std = _standard(choices);
      expect(std.basePrice, 600);
      expect(std.includedKm, 2.3);
      expect(std.pricePerKm, 200);

      final cft = _comfort(choices);
      expect(cft.basePrice, 750);
      expect(cft.includedKm, 2.3);
      expect(cft.pricePerKm, 200);
    });

    test('le prix affiché correspond à la formule du serveur', () {
      final std = _standard(TaxiPricingService.merge(_prodDoc));

      // base + pricePerKm * max(0, d - includedKm)
      expect(std.calculatePrice(5), 600 + 200 * (5 - 2.3));
      // En deçà des km inclus : prix de base seul, jamais moins.
      expect(std.calculatePrice(2), 600);
      expect(std.calculatePrice(0), 600);
    });

    test('ce barème diffère bien du repli local — la régression constatée', () {
      final fromDoc = _standard(TaxiPricingService.merge(_prodDoc));
      final fallback = _standard(TaxiPricingService.merge(null));

      // 1140 avec le document, 1000 avec le repli : l'écart exact rapporté
      // entre Android (lecture OK) et iOS (repli) sur un trajet de 5 km.
      expect(fromDoc.calculatePrice(5), 1140);
      expect(fallback.calculatePrice(5), 1000);
    });

    test('document absent : repli local complet', () {
      final choices = TaxiPricingService.merge(null);
      expect(_standard(choices).basePrice, 600);
      expect(_standard(choices).includedKm, 3);
      expect(_standard(choices).pricePerKm, 200);
    });

    test('pricePerKm à 0 est un forfait valide, pas un motif de repli', () {
      final choices = TaxiPricingService.merge({
        'standard': {'basePrice': 900, 'includedKm': 0, 'pricePerKm': 0},
      });
      final std = _standard(choices);
      expect(std.pricePerKm, 0);
      expect(std.calculatePrice(12), 900);
    });

    test('champs partiels : seuls les champs absents retombent sur le local',
        () {
      final choices = TaxiPricingService.merge({
        'standard': {'basePrice': 800},
      });
      final std = _standard(choices);
      expect(std.basePrice, 800); // valeur admin
      expect(std.includedKm, 3); // repli local
      expect(std.pricePerKm, 200); // repli local
    });

    test('barème invalide (basePrice nul) : repli sur le véhicule local', () {
      final choices = TaxiPricingService.merge({
        'standard': {'basePrice': 0, 'includedKm': 1, 'pricePerKm': 50},
      });
      expect(_standard(choices).basePrice, 600);
      expect(_standard(choices).pricePerKm, 200);
    });

    test('un véhicule absent du document garde le barème local', () {
      final choices = TaxiPricingService.merge({
        'standard': {'basePrice': 650, 'includedKm': 1, 'pricePerKm': 150},
      });
      expect(_standard(choices).basePrice, 650);
      expect(_comfort(choices).basePrice, 750); // intact
      expect(_comfort(choices).includedKm, 3);
    });
  });
}
