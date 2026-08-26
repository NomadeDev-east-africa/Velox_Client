import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_notification.dart';
import '../services/notification_history_service.dart';
import 'user_notifier.dart';

final notificationHistoryServiceProvider =
    Provider<NotificationHistoryService>((ref) => NotificationHistoryService());

/// Historique des notifications du compte connecté, en temps réel.
///
/// Se vide automatiquement à la déconnexion : le flux est reconstruit dès que
/// `userId` change, donc aucune notification d'un compte précédent ne subsiste.
final notificationHistoryProvider =
    StreamProvider.autoDispose<List<AppNotification>>((ref) {
  final uid = ref.watch(userNotifierProvider).userId;
  if (uid == null) return Stream.value(const <AppNotification>[]);
  return ref.watch(notificationHistoryServiceProvider).watch(uid);
});

/// Nombre de notifications non lues — alimente la pastille.
///
/// Vaut 0 pendant le chargement et en erreur : mieux vaut ne pas afficher de
/// pastille que d'en afficher une fausse.
final unreadNotificationsCountProvider = Provider.autoDispose<int>((ref) {
  final list = ref.watch(notificationHistoryProvider).asData?.value;
  if (list == null) return 0;
  return list.where((n) => !n.read).length;
});
