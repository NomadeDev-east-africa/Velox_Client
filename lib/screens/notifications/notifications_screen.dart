import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:nomade_client/models/app_notification.dart';
import 'package:nomade_client/providers/all_providers.dart';
import 'package:nomade_client/screens/food/details/details_screen.dart';
import 'package:nomade_client/screens/food/food_tracking/order_tracking_screen.dart';
import 'package:nomade_client/services/restaurant_service.dart';
import 'package:nomade_client/services/ride_service.dart';
import 'package:nomade_client/theme/app_colors.dart';

/// Historique des notifications reçues.
///
/// Les notifications iOS disparaissent dès qu'elles sont balayées ou purgées :
/// cet écran est la seule façon de retrouver une promo passée.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  /// IDs dépliés. Une notification longue s'affiche tronquée puis se déroule
  /// au tap — le corps complet est en base, non tronqué.
  final Set<String> _expanded = <String>{};

  late AppColors _c;

  @override
  Widget build(BuildContext context) {
    final isDark = ref.watch(themeNotifierProvider).isDarkMode;
    _c = isDark ? AppColors.dark : AppColors.light;

    final async = ref.watch(notificationHistoryProvider);
    final unread = ref.watch(unreadNotificationsCountProvider);

    return Scaffold(
      backgroundColor: _c.bg,
      appBar: AppBar(
        backgroundColor: _c.bg,
        foregroundColor: _c.onSurface,
        elevation: 0,
        title: Text(
          'Notifications',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: _c.onSurface,
            fontSize: 18,
          ),
        ),
        actions: [
          if (unread > 0)
            TextButton(
              onPressed: _markAllAsRead,
              child: Text(
                'Tout marquer comme lu',
                style: TextStyle(color: _c.primary, fontSize: 12),
              ),
            ),
        ],
      ),
      body: async.when(
        loading: () =>
            Center(child: CircularProgressIndicator(color: _c.primary)),
        error: (e, _) => _buildError(),
        data: (items) {
          if (items.isEmpty) return _buildEmpty();
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (_, i) => _buildCard(items[i]),
          );
        },
      ),
    );
  }

  // ── Carte ─────────────────────────────────────────────────────

  Widget _buildCard(AppNotification n) {
    final isExpanded = _expanded.contains(n.id);
    final accent = _typeColor(n.type);

    return GestureDetector(
      onTap: () => _onTap(n),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          // Une non-lue est teintée et bordée : elle doit se distinguer d'un
          // coup d'œil dans une liste longue.
          color: n.read ? _c.surface : accent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: n.read
                ? _c.outlineVariant.withValues(alpha: 0.3)
                : accent.withValues(alpha: 0.45),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(_typeIcon(n.type), color: accent, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              n.title,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: n.read
                                    ? FontWeight.w600
                                    : FontWeight.w800,
                                color: _c.onSurface,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (!n.read) ...[
                            const SizedBox(width: 8),
                            Container(
                              width: 9,
                              height: 9,
                              decoration: BoxDecoration(
                                color: accent,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _relativeDate(n.createdAt),
                        style: TextStyle(
                            fontSize: 11, color: _c.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (n.body.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                n.body,
                maxLines: isExpanded ? null : 2,
                overflow:
                    isExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: _c.onSurfaceVariant,
                ),
              ),
            ],
            if (isExpanded && (n.imageUrl?.isNotEmpty ?? false)) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CachedNetworkImage(
                  imageUrl: n.imageUrl!,
                  width: double.infinity,
                  fit: BoxFit.fitWidth,
                  placeholder: (_, _) => Container(
                    height: 120,
                    color: _c.surfaceLow,
                  ),
                  errorWidget: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ],
            if (isExpanded && n.isTappable) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    _actionLabel(n.actionType),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: accent,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_forward_ios, size: 11, color: accent),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Interaction ───────────────────────────────────────────────

  /// Premier tap : déplier et marquer comme lu. Second tap sur une
  /// notification déjà dépliée : exécuter son action.
  ///
  /// Ce double temps évite qu'un simple coup d'œil à une promo fasse quitter
  /// l'écran.
  Future<void> _onTap(AppNotification n) async {
    final wasExpanded = _expanded.contains(n.id);

    if (!wasExpanded) {
      setState(() => _expanded.add(n.id));
      if (!n.read) _markAsRead(n.id);
      return;
    }

    if (!n.isTappable) {
      setState(() => _expanded.remove(n.id));
      return;
    }

    await _runAction(n);
  }

  Future<void> _runAction(AppNotification n) async {
    final value = n.actionValue!.trim();

    switch (n.actionType) {
      case NotificationAction.order:
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => OrderTrackingScreen(orderId: value),
          ),
        );
      case NotificationAction.ride:
        // `TrackingScreen` suit la course ACTIVE (`activeRideProvider`) et
        // ignore l'ID transmis : y envoyer depuis une notification de course
        // terminée — la majorité de l'historique — affichait un écran sans
        // rapport. On vérifie donc l'état réel avant de naviguer.
        final ride = await RideService().getRideById(value);
        if (!mounted) return;
        if (ride == null) {
          _snack('Course introuvable');
          return;
        }
        if (!ride.isActive) {
          _snack('Cette course est terminée');
          return;
        }
        await Navigator.of(context)
            .pushNamed('/ride-tracking', arguments: {'rideId': value});
      case NotificationAction.restaurant:
        final restaurant = await RestaurantService().getRestaurantById(value);
        if (!mounted) return;
        if (restaurant == null) {
          _snack('Restaurant introuvable');
          return;
        }
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DetailsScreen(restaurant: restaurant),
          ),
        );
      case NotificationAction.whatsapp:
        await _openExternal('https://wa.me/$value');
      case NotificationAction.url:
        await _openExternal(value);
      case NotificationAction.none:
        break;
    }
  }

  /// launchUrl peut lever si aucune app ne gère le lien — WhatsApp absent, par
  /// exemple.
  Future<void> _openExternal(String rawUrl) async {
    final uri = Uri.tryParse(rawUrl);
    var launched = false;
    if (uri != null) {
      try {
        launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        launched = false;
      }
    }
    if (!launched) _snack('Impossible d\'ouvrir ce lien');
  }

  void _markAsRead(String id) {
    final uid = ref.read(userNotifierProvider).userId;
    if (uid == null) return;
    ref.read(notificationHistoryServiceProvider).markAsRead(uid, id);
  }

  void _markAllAsRead() {
    final uid = ref.read(userNotifierProvider).userId;
    if (uid == null) return;
    ref.read(notificationHistoryServiceProvider).markAllAsRead(uid);
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── États vides / erreur ──────────────────────────────────────

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: _c.primary.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.notifications_none,
                size: 60, color: _c.primary),
          ),
          const SizedBox(height: 20),
          Text(
            'Aucune notification',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: _c.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Vos promotions et le suivi de vos commandes apparaîtront ici.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: _c.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 56, color: _c.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              'Impossible de charger vos notifications',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: _c.onSurface,
              ),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () => ref.invalidate(notificationHistoryProvider),
              icon: Icon(Icons.refresh, color: _c.primary),
              label: Text('Réessayer', style: TextStyle(color: _c.primary)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: _c.primary),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Présentation ──────────────────────────────────────────────

  IconData _typeIcon(NotificationType t) {
    switch (t) {
      case NotificationType.order:
        return Icons.receipt_long;
      case NotificationType.ride:
        return Icons.local_taxi;
      case NotificationType.promo:
        return Icons.local_offer;
    }
  }

  Color _typeColor(NotificationType t) {
    switch (t) {
      case NotificationType.order:
        return const Color(0xFF2196F3);
      case NotificationType.ride:
        return const Color(0xFF9C27B0);
      case NotificationType.promo:
        return _c.primary;
    }
  }

  String _actionLabel(NotificationAction a) {
    switch (a) {
      case NotificationAction.order:
        return 'VOIR LA COMMANDE';
      case NotificationAction.ride:
        return 'SUIVRE LA COURSE';
      case NotificationAction.restaurant:
        return 'VOIR LE RESTAURANT';
      case NotificationAction.whatsapp:
        return 'OUVRIR WHATSAPP';
      case NotificationAction.url:
        return 'EN SAVOIR PLUS';
      case NotificationAction.none:
        return '';
    }
  }

  String _relativeDate(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'À l\'instant';
    if (diff.inMinutes < 60) return 'Il y a ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Il y a ${diff.inHours} h';
    if (diff.inDays < 7) return 'Il y a ${diff.inDays} j';
    return DateFormat('dd MMM · HH:mm', 'fr_FR').format(date);
  }
}
