import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../main.dart' show appNavigatorKey;
import '../models/order.dart';
import '../providers/all_providers.dart';
import '../theme/app_colors.dart';
import '../utils/route_tracker.dart';

/// Pastille flottante globale de suivi de commande.
///
/// Montée une seule fois dans `MaterialApp.builder`, elle survit à la navigation
/// impérative (accueil / fiche resto / panier / profil…). Elle possède SA PROPRE
/// fenêtre de visibilité : elle reste affichée **8 s après livraison**, comptées
/// depuis `deliveredAt` et non depuis l'instant où le widget découvre la
/// commande — une commande livrée il y a longtemps et restaurée depuis Hive ne
/// doit pas réapparaître. Indépendante du nettoyage à 4 s de
/// `ActiveOrderNotifier` (qu'on ne touche pas). Masquée sur les écrans de suivi
/// eux-mêmes et si l'utilisateur n'est pas connecté. Tap → ouvre
/// `OrderTrackingScreen`.
class GlobalActiveOrderWidget extends ConsumerStatefulWidget {
  const GlobalActiveOrderWidget({super.key});

  @override
  ConsumerState<GlobalActiveOrderWidget> createState() =>
      _GlobalActiveOrderWidgetState();
}

class _GlobalActiveOrderWidgetState
    extends ConsumerState<GlobalActiveOrderWidget>
    with SingleTickerProviderStateMixin {
  static const _postDeliveryWindow = Duration(seconds: 8);

  /// Commande actuellement affichée (active OU livrée dans la fenêtre de 8 s).
  Order? _displayOrder;
  DateTime? _completedAt;
  Timer? _hideTimer;

  late final AnimationController _pulseController;
  Timer? _pulseTimer;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
      lowerBound: 0.0,
      upperBound: 1.0,
    );
    // Micro-pulse discret toutes les 5 s.
    _pulseTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_displayOrder != null && mounted) {
        _pulseController.forward(from: 0).then((_) {
          if (mounted) _pulseController.reverse();
        });
      }
    });
    // État initial (commande restaurée depuis Hive au lancement).
    _applyState(ref.read(activeOrderProvider), silent: true);
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _pulseTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  /// Met à jour la commande affichée + la fenêtre 8 s à partir de l'état du
  /// notifier. `silent` (initState) évite un setState avant le premier build.
  void _applyState(ActiveOrderState next, {bool silent = false}) {
    final order = next.order;

    if (order == null) {
      // Notifier vidé (4 s après terminal). On NE cache que si on n'est pas
      // dans la fenêtre post-livraison — sinon le Timer 8 s s'en charge.
      if (_completedAt == null) {
        _clearDisplay(silent: silent);
      }
      return;
    }

    if (order.status == Order.statusCancelled) {
      _clearDisplay(silent: silent); // annulée → disparition immédiate
      return;
    }

    if (order.status == Order.statusCompleted) {
      // Fenêtre comptée depuis `deliveredAt` : au lancement, une commande
      // livrée hier et restaurée depuis Hive doit rester masquée.
      final deliveredAt = order.deliveredAt?.toDate() ?? DateTime.now();
      final remaining = _postDeliveryWindow - DateTime.now().difference(deliveredAt);
      if (remaining <= Duration.zero) {
        _clearDisplay(silent: silent);
        return;
      }
      _displayOrder = order;
      _completedAt ??= deliveredAt;
      _hideTimer ??= Timer(remaining, () => _clearDisplay());
    } else {
      // Commande active (pending → delivering).
      _displayOrder = order;
      _completedAt = null;
      _hideTimer?.cancel();
      _hideTimer = null;
    }
    if (!silent && mounted) setState(() {});
  }

  void _clearDisplay({bool silent = false}) {
    _hideTimer?.cancel();
    _hideTimer = null;
    _completedAt = null;
    _displayOrder = null;
    if (!silent && mounted) setState(() {});
  }

  void _openTracking() {
    final id = _displayOrder?.id;
    if (id == null) return;
    appNavigatorKey.currentState
        ?.pushNamed('/order-tracking', arguments: {'orderId': id});
  }

  // ── Mapping statut → phase / icône ──────────────────────────────
  int _phase(String status) {
    switch (status) {
      case Order.statusReady:
        return 1;
      case Order.statusDelivering:
      case Order.statusCompleted:
        return 2;
      default:
        return 0; // pending / confirmed / accepted / preparing
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case Order.statusReady:
        return Icons.fastfood_rounded;
      case Order.statusDelivering:
        return Icons.delivery_dining_rounded;
      case Order.statusCompleted:
        return Icons.check_circle_rounded;
      default:
        return Icons.restaurant_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Réagit aux changements du notifier (le stream met à jour le statut).
    ref.listen<ActiveOrderState>(activeOrderProvider, (prev, next) {
      _applyState(next);
    });

    // Déconnexion / changement de compte : `user_notifier` invalide bien
    // `activeOrderProvider`, mais la fenêtre post-livraison locale survivrait à
    // cette invalidation et afficherait la commande du compte précédent.
    ref.listen(userNotifierProvider, (prev, next) {
      if (prev != null && prev.isAuthenticated && !next.isAuthenticated) {
        _clearDisplay();
      }
    });

    final isDark = ref.watch(themeNotifierProvider).isDarkMode;
    final c = isDark ? AppColors.dark : AppColors.light;
    final isAuth = ref.watch(userNotifierProvider).isAuthenticated;

    return ValueListenableBuilder<String?>(
      valueListenable: currentRouteName,
      builder: (context, routeName, _) {
        final onTrackingScreen =
            routeName == '/order-tracking' || routeName == '/ride-tracking';
        final order = _displayOrder;
        final show = order != null && isAuth && !onTrackingScreen;

        return Positioned(
          right: 16,
          // Au-dessus des barres du bas (bottom nav ~72, bouton panier…).
          bottom: 96,
          child: IgnorePointer(
            ignoring: !show,
            child: AnimatedSlide(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutCubic,
              offset: show ? Offset.zero : const Offset(0, 1.6),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 260),
                opacity: show ? 1 : 0,
                child: order == null
                    ? const SizedBox.shrink()
                    : _buildPill(c, order),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPill(AppColors c, Order order) {
    final phase = _phase(order.status);
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final scale = 1 + 0.04 * _pulseController.value;
        return Transform.scale(scale: scale, child: child);
      },
      child: Material(
        color: Colors.transparent,
        child: GestureDetector(
          onTap: _openTracking,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 260),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: c.surfaceHigh,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: c.primary.withValues(alpha: 0.35)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: c.primary.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(_statusIcon(order.status),
                      color: c.primary, size: 19),
                ),
                const SizedBox(width: 10),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      Order.getStatusText(order.status),
                      style: TextStyle(
                        color: c.onSurface,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    _buildDots(c, phase),
                  ],
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right_rounded,
                    color: c.onSurfaceVariant, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDots(AppColors c, int phase) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        final filled = i <= phase;
        return Container(
          margin: EdgeInsets.only(right: i < 2 ? 4 : 0),
          width: filled ? 16 : 8,
          height: 4,
          decoration: BoxDecoration(
            color: filled ? c.primary : c.outlineVariant.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }
}
