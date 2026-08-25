import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/mock_taxi_data.dart';
import '../models/ride_choice.dart';
import '../services/taxi_pricing_service.dart';

final taxiPricingServiceProvider =
    Provider<TaxiPricingService>((ref) => TaxiPricingService());

/// Flux brut du document `config/taxiPricing`.
final taxiPricingStreamProvider = StreamProvider<List<RideChoice>>((ref) {
  return ref.watch(taxiPricingServiceProvider).watchRideChoices();
});

/// Catalogue des véhicules avec leurs tarifs — **le seul point de lecture pour
/// l'UI**.
///
/// Pendant le chargement, en erreur de lecture, ou tant que le document
/// `config/taxiPricing` n'existe pas, renvoie le catalogue de repli local
/// (identique au repli Android et à celui des Cloud Functions), afin que
/// l'écran VTC reste utilisable en toutes circonstances.
final rideChoicesProvider = Provider<List<RideChoice>>((ref) {
  return ref.watch(taxiPricingStreamProvider).asData?.value ??
      MockTaxiData.rideChoices;
});

/// Véhicule proposé par défaut à l'ouverture de l'écran VTC.
final defaultRideChoiceProvider = Provider<RideChoice>((ref) {
  return ref.watch(rideChoicesProvider).first;
});
