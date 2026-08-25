import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:nomade_client/models/order.dart';
import 'package:nomade_client/models/ride.dart';
import 'package:nomade_client/providers/all_providers.dart';
import 'package:nomade_client/theme/app_colors.dart';
import 'package:nomade_client/translations/app_translations.dart';
import 'package:nomade_client/screens/food/food_tracking/order_tracking_screen.dart';

class OrderHistoryScreen extends ConsumerStatefulWidget {
  const OrderHistoryScreen({super.key});

  @override
  ConsumerState<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends ConsumerState<OrderHistoryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late AppColors _c;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ref.watch(themeNotifierProvider).isDarkMode;
    _c = isDark ? AppColors.dark : AppColors.light;

    final ordersAsync = ref.watch(userOrdersProvider);
    final ridesAsync  = ref.watch(userRidesProvider);

    return Scaffold(
      backgroundColor: _c.bg,
      appBar: AppBar(
        backgroundColor: _c.bg,
        foregroundColor: _c.onSurface,
        elevation: 0,
        title: Text(
          tr('my_orders'),
          style: TextStyle(
            color: _c.onSurface,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _c.surfaceHigh,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.arrow_back_ios_new, color: _c.onSurface, size: 15),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: _c.primary,
          unselectedLabelColor: _c.onSurfaceVariant,
          indicatorColor: _c.primary,
          indicatorSize: TabBarIndicatorSize.label,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          tabs: [
            Tab(text: tr('in_progress')),
            Tab(text: tr('history')),
          ],
        ),
      ),
      body: ordersAsync.when(
        loading: () => Center(child: CircularProgressIndicator(color: _c.primary)),
        error: (e, _) => _buildError(e),
        data: (orders) {
          // Les courses ne bloquent pas l'affichage des commandes : en cours de
          // chargement ou en erreur, la section courses est simplement absente.
          final rides = ridesAsync.asData?.value ?? const <Ride>[];

          final activeOrders = orders.where((o) => o.isActive).toList();
          final pastOrders   = orders.where((o) => !o.isActive).toList();
          final activeRides  = rides.where((r) => r.isActive).toList();
          final pastRides    = rides.where((r) => !r.isActive).toList();

          return TabBarView(
            controller: _tabController,
            children: [
              _buildTab(activeOrders, activeRides, isActive: true),
              _buildTab(pastOrders,   pastRides,   isActive: false),
            ],
          );
        },
      ),
    );
  }

  // ── Error state ───────────────────────────────────────────────

  Widget _buildError(Object e) {
    final isIndexBuilding = e.toString().toLowerCase().contains('index');
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isIndexBuilding ? Icons.build_circle_outlined : Icons.error_outline,
              size: 56,
              color: _c.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              isIndexBuilding ? tr('setup_in_progress') : tr('loading_error'),
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: _c.onSurface,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              isIndexBuilding
                  ? tr('index_building_msg')
                  : tr('unexpected_error'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: _c.onSurfaceVariant, height: 1.5),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () => ref.invalidate(userOrdersProvider),
              icon: Icon(Icons.refresh, color: _c.primary),
              label: Text(tr('retry'), style: TextStyle(color: _c.primary)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: _c.primary),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Liste ─────────────────────────────────────────────────────

  /// Un onglet = section commandes food + section courses VTC, chacune
  /// précédée de son en-tête (icône + compteur) et masquée si vide.
  Widget _buildTab(List<Order> orders, List<Ride> rides,
      {required bool isActive}) {
    if (orders.isEmpty && rides.isEmpty) {
      return RefreshIndicator(
        color: _c.primary,
        backgroundColor: _c.surfaceLow,
        onRefresh: _refresh,
        // Le pull-to-refresh exige une zone défilable même quand elle est vide.
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.6,
              child: _buildEmpty(isActive),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: _c.primary,
      backgroundColor: _c.surfaceLow,
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          if (orders.isNotEmpty) ...[
            _sectionHeader(
                Icons.restaurant_menu, tr('my_orders'), orders.length),
            const SizedBox(height: 12),
            ...orders.map((o) => _buildOrderCard(o, isActive: isActive)),
          ],
          if (orders.isNotEmpty && rides.isNotEmpty)
            const SizedBox(height: 12),
          if (rides.isNotEmpty) ...[
            _sectionHeader(Icons.local_taxi, 'Mes courses', rides.length),
            const SizedBox(height: 12),
            ...rides.map((r) => _buildRideCard(r, isActive: isActive)),
          ],
        ],
      ),
    );
  }

  Future<void> _refresh() async {
    ref.invalidate(userRidesProvider);
    await ref.read(userRidesProvider.future);
  }

  Widget _sectionHeader(IconData icon, String label, int count) {
    return Row(
      children: [
        Icon(icon, size: 18, color: _c.primary),
        const SizedBox(width: 8),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: _c.onSurface,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: _c.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: _c.primary,
            ),
          ),
        ),
      ],
    );
  }

  // ── Empty state ───────────────────────────────────────────────

  Widget _buildEmpty(bool isActive) {
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
            child: Icon(
              isActive ? Icons.pending_actions : Icons.receipt_long,
              size: 60,
              color: _c.primary,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            isActive ? tr('no_active_orders') : tr('no_past_orders'),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: _c.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isActive
                ? tr('active_orders_hint')
                : tr('history_hint'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: _c.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  // ── Carte commande ────────────────────────────────────────────

  Widget _buildOrderCard(Order order, {required bool isActive}) {
    final statusColor = _statusColor(order.status);
    final date = DateFormat('dd MMM · HH:mm', 'fr_FR')
        .format(order.createdAt.toDate());

    return GestureDetector(
      onTap: () => isActive
          ? Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => OrderTrackingScreen(orderId: order.id),
              ),
            )
          : _showOrderDetail(order),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: _c.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _c.outlineVariant.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            // ── Header ─────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: CachedNetworkImage(
                      imageUrl: order.restaurantImageUrl,
                      width: 52,
                      height: 52,
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) => Container(
                        width: 52,
                        height: 52,
                        color: _c.surfaceHigh,
                        child: Icon(Icons.restaurant, color: _c.primary, size: 26),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          order.restaurantName,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: _c.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${order.itemCount} ${tr('items')} · ${order.total} FDJ',
                          style: TextStyle(fontSize: 13, color: _c.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    date,
                    style: TextStyle(fontSize: 11, color: _c.onSurfaceVariant),
                  ),
                ],
              ),
            ),

            // ── Séparateur ─────────────────────────────────────
            Divider(height: 1, color: _c.outlineVariant.withValues(alpha: 0.25)),

            // ── Footer statut ──────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_statusIcon(order.status),
                            size: 13, color: statusColor),
                        const SizedBox(width: 6),
                        Text(
                          Order.getStatusText(order.status),
                          style: TextStyle(
                            fontSize: 12,
                            color: statusColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  if (isActive)
                    Row(
                      children: [
                        Text(
                          tr('track'),
                          style: TextStyle(
                            fontSize: 12,
                            color: _c.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.arrow_forward_ios, size: 12, color: _c.primary),
                      ],
                    )
                  else
                    Row(
                      children: [
                        Text(
                          tr('details'),
                          style: TextStyle(
                            fontSize: 12,
                            color: _c.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.arrow_forward_ios, size: 12, color: _c.onSurfaceVariant),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Bottom sheet détail ───────────────────────────────────────

  void _showOrderDetail(Order order) {
    final c = _c;
    showModalBottomSheet(
      context: context,
      backgroundColor: c.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.92,
        minChildSize: 0.4,
        expand: false,
        builder: (_, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: c.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Header resto
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: CachedNetworkImage(
                    imageUrl: order.restaurantImageUrl,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    errorWidget: (_, _, _) => Container(
                      width: 48,
                      height: 48,
                      color: c.surfaceHigh,
                      child: Icon(Icons.restaurant, color: c.primary),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order.restaurantName,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: c.onSurface,
                        ),
                      ),
                      Text(
                        DateFormat('dd MMMM yyyy · HH:mm', 'fr_FR')
                            .format(order.createdAt.toDate()),
                        style: TextStyle(fontSize: 12, color: c.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _statusColor(order.status).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    Order.getStatusText(order.status),
                    style: TextStyle(
                      fontSize: 12,
                      color: _statusColor(order.status),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),
            Divider(color: c.outlineVariant.withValues(alpha: 0.3)),
            const SizedBox(height: 12),

            // Articles
            Text(
              tr('ordered_items'),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: c.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            ...order.items.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: c.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        '×${item.quantity}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: c.primary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item.name,
                      style: TextStyle(fontSize: 14, color: c.onSurface),
                    ),
                  ),
                  Text(
                    '${item.totalPrice} FDJ',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: c.onSurface,
                    ),
                  ),
                ],
              ),
            )),

            const SizedBox(height: 12),
            Divider(color: c.outlineVariant.withValues(alpha: 0.3)),
            const SizedBox(height: 12),

            // Totaux
            _detailRow(tr('subtotal'), '${order.subtotal} FDJ', c),
            const SizedBox(height: 6),
            _detailRow(tr('delivery'), '${order.deliveryFee} FDJ', c),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  tr('total'),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: c.onSurface,
                  ),
                ),
                Text(
                  '${order.total} FDJ',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: c.primary,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),
            Divider(color: c.outlineVariant.withValues(alpha: 0.3)),
            const SizedBox(height: 12),

            // Infos livraison
            _infoRow(Icons.location_on_outlined, tr('address'), order.deliveryAddress, c),
            const SizedBox(height: 8),
            _infoRow(
              _paymentIcon(order.paymentMethod),
              tr('payment'),
              _paymentLabel(order.paymentMethod),
              c,
            ),
            if (order.deliveryDriverName != null) ...[
              const SizedBox(height: 8),
              _infoRow(Icons.delivery_dining, tr('driver'), order.deliveryDriverName!, c),
            ],
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value, AppColors c) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 14, color: c.onSurfaceVariant)),
        Text(value, style: TextStyle(fontSize: 14, color: c.onSurface)),
      ],
    );
  }

  String _paymentLabel(String method) {
    switch (method) {
      case 'cash':    return tr('cash_label');
      case 'waafi':   return 'Waafi';
      case 'd_money': return 'D-Money';
      case 'cac_pay': return 'CAC Pay';
      case 'bci':        return 'BCI';
      case 'exim':       return 'EXIM Bank';
      case 'dahab_plus': return 'Dahab+';
      case 'card':    return 'Carte bancaire';
      case 'mobile_wallet': return 'Mobile Money';
      default:        return tr('cash_label');
    }
  }

  IconData _paymentIcon(String method) {
    switch (method) {
      case 'waafi':
      case 'd_money':
      case 'cac_pay':
      case 'dahab_plus':
      case 'mobile_wallet': return Icons.account_balance_wallet;
      case 'bci':
      case 'exim':          return Icons.account_balance;
      case 'card':          return Icons.credit_card;
      default:              return Icons.payments_outlined;
    }
  }

  Widget _infoRow(IconData icon, String label, String value, AppColors c) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: c.onSurfaceVariant),
        const SizedBox(width: 8),
        Text('$label : ', style: TextStyle(fontSize: 13, color: c.onSurfaceVariant)),
        Expanded(
          child: Text(
            value,
            style: TextStyle(fontSize: 13, color: c.onSurface, fontWeight: FontWeight.w500),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  // ── Helpers ───────────────────────────────────────────────────

  // ── Carte course VTC ──────────────────────────────────────────

  Widget _buildRideCard(Ride ride, {required bool isActive}) {
    final statusColor = _rideStatusColor(ride.status);
    final date = DateFormat('dd MMM · HH:mm', 'fr_FR').format(ride.requestedAt);
    final fare = (ride.finalFare ?? ride.estimatedFare).round();
    final destination = ride.destination.placeName?.trim().isNotEmpty == true
        ? ride.destination.placeName!
        : ride.destination.address;

    return GestureDetector(
      // TrackingScreen lit la course depuis `activeRideProvider` : la route
      // n'a de sens que pour la course en cours, d'où le tap inactif sur
      // l'historique terminé.
      onTap: isActive
          ? () => Navigator.of(context).pushNamed('/ride-tracking',
              arguments: {'rideId': ride.rideId})
          : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: _c.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _c.outlineVariant.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: _c.surfaceHigh,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.local_taxi, color: _c.primary, size: 26),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          destination,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: _c.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${ride.distance.toStringAsFixed(1)} km · $fare FDJ',
                          style: TextStyle(
                              fontSize: 13, color: _c.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    date,
                    style: TextStyle(fontSize: 11, color: _c.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: _c.outlineVariant.withValues(alpha: 0.25)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_rideStatusIcon(ride.status),
                            size: 13, color: statusColor),
                        const SizedBox(width: 6),
                        Text(
                          _rideStatusText(ride.status),
                          style: TextStyle(
                            fontSize: 12,
                            color: statusColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  if (isActive)
                    Row(
                      children: [
                        Text(
                          tr('track'),
                          style: TextStyle(
                            fontSize: 12,
                            color: _c.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.arrow_forward_ios,
                            size: 12, color: _c.primary),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Statuts ───────────────────────────────────────────────────

  IconData _statusIcon(String status) {
    switch (status) {
      case Order.statusPending:    return Icons.hourglass_empty;
      case Order.statusConfirmed:
      case Order.statusAccepted:   return Icons.thumb_up_alt_outlined;
      case Order.statusPreparing:  return Icons.soup_kitchen_outlined;
      case Order.statusReady:      return Icons.shopping_bag_outlined;
      case Order.statusDelivering: return Icons.delivery_dining;
      case Order.statusCompleted:  return Icons.check_circle;
      case Order.statusCancelled:  return Icons.cancel;
      default:                     return Icons.help_outline;
    }
  }

  String _rideStatusText(RideStatus status) {
    switch (status) {
      case RideStatus.requested:         return 'Recherche d\'un chauffeur';
      case RideStatus.accepted:          return 'Chauffeur en route';
      case RideStatus.arriving:          return 'Chauffeur en approche';
      case RideStatus.arrived:           return 'Chauffeur arrivé';
      case RideStatus.started:           return 'Course en cours';
      case RideStatus.completed:         return 'Terminée';
      case RideStatus.cancelled:         return 'Annulée';
      case RideStatus.noDriverAvailable: return 'Aucun chauffeur disponible';
    }
  }

  IconData _rideStatusIcon(RideStatus status) {
    switch (status) {
      case RideStatus.requested:         return Icons.hourglass_empty;
      case RideStatus.accepted:
      case RideStatus.arriving:          return Icons.directions_car;
      case RideStatus.arrived:           return Icons.pin_drop_outlined;
      case RideStatus.started:           return Icons.navigation_outlined;
      case RideStatus.completed:         return Icons.check_circle;
      case RideStatus.cancelled:         return Icons.cancel;
      case RideStatus.noDriverAvailable: return Icons.person_off_outlined;
    }
  }

  Color _rideStatusColor(RideStatus status) {
    switch (status) {
      case RideStatus.requested:         return const Color(0xFFFF9800);
      case RideStatus.accepted:
      case RideStatus.arriving:
      case RideStatus.arrived:           return const Color(0xFF2196F3);
      case RideStatus.started:           return const Color(0xFF9C27B0);
      case RideStatus.completed:         return const Color(0xFF4CAF50);
      case RideStatus.cancelled:         return const Color(0xFFF44336);
      case RideStatus.noDriverAvailable: return const Color(0xFF757575);
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case Order.statusPending:    return const Color(0xFFFF9800);
      case Order.statusConfirmed:
      case Order.statusAccepted:
      case Order.statusPreparing:
      case Order.statusReady:      return const Color(0xFF2196F3);
      case Order.statusDelivering: return const Color(0xFF9C27B0);
      case Order.statusCompleted:  return const Color(0xFF4CAF50);
      case Order.statusCancelled:  return const Color(0xFFF44336);
      default:                     return const Color(0xFF757575);
    }
  }
}
