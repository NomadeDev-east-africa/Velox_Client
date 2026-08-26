import 'package:cloud_firestore/cloud_firestore.dart';

/// Famille d'une notification, utilisée pour l'icône et le regroupement.
enum NotificationType { promo, order, ride }

/// Action déclenchée au tap sur une notification de l'historique.
enum NotificationAction { none, order, ride, restaurant, url, whatsapp }

/// Notification persistée, telle qu'écrite par les Cloud Functions dans
/// `users/{uid}/notifications/{id}`.
///
/// Le push FCM reste le canal d'alerte ; cette collection n'existe que pour
/// conserver un historique consultable — une notification balayée ou purgée par
/// iOS était jusqu'ici définitivement perdue.
///
/// Le client ne peut que basculer `read`/`readAt` : la création et la
/// suppression sont réservées à l'Admin SDK (cf. règles Firestore).
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.read,
    required this.actionType,
    this.actionValue,
    this.imageUrl,
    this.campaignId,
  });

  final String id;
  final NotificationType type;
  final String title;

  /// Texte intégral, non tronqué — c'est ce qui rend l'agrandissement utile.
  final String body;

  final DateTime createdAt;
  final bool read;

  final NotificationAction actionType;

  /// Cible de l'action : `orderId`, `rideId`, `restaurantId`, URL ou numéro
  /// WhatsApp selon [actionType].
  final String? actionValue;

  final String? imageUrl;
  final String? campaignId;

  bool get isTappable =>
      actionType != NotificationAction.none &&
      (actionValue?.trim().isNotEmpty ?? false);

  factory AppNotification.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? const {};

    return AppNotification(
      id: doc.id,
      type: _parseType(data['type']),
      title: data['title'] as String? ?? '',
      body: data['body'] as String? ?? '',
      // Une notification sans date valide remonterait en tête du tri : on la
      // date de l'époque plutôt que de « maintenant ».
      createdAt: _parseDate(data['createdAt']),
      read: data['read'] as bool? ?? false,
      actionType: _parseAction(data['actionType']),
      actionValue: (data['actionValue'] as String?)?.trim(),
      imageUrl: (data['imageUrl'] as String?)?.trim(),
      campaignId: data['campaignId'] as String?,
    );
  }

  static DateTime _parseDate(dynamic raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
    if (raw is String) {
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) return parsed;
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  static NotificationType _parseType(dynamic raw) {
    switch (raw) {
      case 'order':
        return NotificationType.order;
      case 'ride':
        return NotificationType.ride;
      default:
        return NotificationType.promo;
    }
  }

  static NotificationAction _parseAction(dynamic raw) {
    switch (raw) {
      case 'order':
        return NotificationAction.order;
      case 'ride':
        return NotificationAction.ride;
      case 'restaurant':
        return NotificationAction.restaurant;
      case 'url':
        return NotificationAction.url;
      case 'whatsapp':
        return NotificationAction.whatsapp;
      default:
        return NotificationAction.none;
    }
  }
}
