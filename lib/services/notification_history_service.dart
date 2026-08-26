import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/app_notification.dart';

/// Historique des notifications d'un utilisateur
/// (`users/{uid}/notifications`).
///
/// Lecture seule côté client, à une exception près : basculer `read`/`readAt`,
/// les seuls champs que les règles Firestore autorisent à modifier.
class NotificationHistoryService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _col(String uid) =>
      _db.collection('users').doc(uid).collection('notifications');

  /// Flux temps réel, plus récentes en tête.
  ///
  /// La limite évite qu'un compte ancien charge des centaines de documents à
  /// l'ouverture de l'écran ; la purge serveur à 90 jours borne déjà le volume,
  /// ceci n'est qu'un garde-fou d'affichage.
  Stream<List<AppNotification>> watch(String uid, {int limit = 100}) {
    return _col(uid)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(AppNotification.fromFirestore).toList());
  }

  /// Marque une notification comme lue. Sans effet si elle l'est déjà.
  Future<void> markAsRead(String uid, String notificationId) async {
    try {
      await _col(uid).doc(notificationId).update({
        'read': true,
        'readAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      // Échec non bloquant : l'utilisateur a vu la notification, seul le
      // compteur restera décalé jusqu'à la prochaine tentative.
      debugPrint('⚠️ [NotificationHistory] markAsRead: $e');
    }
  }

  /// Marque toutes les notifications non lues comme lues.
  ///
  /// Écritures groupées par 500, la limite d'un `WriteBatch` Firestore.
  Future<void> markAllAsRead(String uid) async {
    try {
      final unread =
          await _col(uid).where('read', isEqualTo: false).get();
      if (unread.docs.isEmpty) return;

      for (var i = 0; i < unread.docs.length; i += 500) {
        final batch = _db.batch();
        final slice = unread.docs.skip(i).take(500);
        for (final doc in slice) {
          batch.update(doc.reference, {
            'read': true,
            'readAt': FieldValue.serverTimestamp(),
          });
        }
        await batch.commit();
      }
    } catch (e) {
      debugPrint('⚠️ [NotificationHistory] markAllAsRead: $e');
    }
  }
}
