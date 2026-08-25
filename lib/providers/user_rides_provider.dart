import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nomade_client/models/ride.dart';
import 'package:nomade_client/services/ride_service.dart';
import 'user_notifier.dart';

/// Historique des courses VTC du client connecté.
///
/// `getUserRideHistory` est une lecture ponctuelle (pas un stream) : la liste se
/// rafraîchit au `ref.invalidate` / pull-to-refresh de l'écran historique. Le
/// suivi temps réel d'une course en cours reste le rôle d'`activeRideProvider`.
final userRidesProvider = FutureProvider.autoDispose<List<Ride>>((ref) async {
  final userId = ref.watch(userNotifierProvider).userId;
  if (userId == null) return const <Ride>[];
  return RideService().getUserRideHistory(userId);
});
