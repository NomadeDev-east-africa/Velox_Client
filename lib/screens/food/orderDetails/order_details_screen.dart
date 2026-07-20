import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import 'package:nomade_client/constants.dart';
import 'package:nomade_client/translations/app_translations.dart';
import 'package:nomade_client/models/order_item.dart';
import 'package:nomade_client/providers/all_providers.dart';
import 'package:nomade_client/screens/auth-firebase/auth/complete_phone_screen.dart';
import 'package:nomade_client/screens/auth-firebase/auth/sign_in_screen.dart';
import 'package:nomade_client/screens/food/food_tracking/delivery_address_picker_screen.dart';
import 'package:nomade_client/screens/food/pending_order/pending_order_screen.dart';
import 'package:nomade_client/services/restaurant_service.dart';
import 'package:nomade_client/theme/app_colors.dart';

// ✅ PHASE 4 : cart_provider.dart SUPPRIMÉ — remplacé par cartProvider Riverpod
// ✅ Navigation déplacée ici (CartNotifier ne navigue plus)

class OrderDetailsScreen extends ConsumerStatefulWidget {
  const OrderDetailsScreen({super.key});

  @override
  ConsumerState<OrderDetailsScreen> createState() =>
      _OrderDetailsScreenState();
}

class _OrderDetailsScreenState extends ConsumerState<OrderDetailsScreen> {
  final bool _isProcessing = false;
  String _selectedPaymentMethod = 'cash';
  int _pointsApplied = 0;

  String? _deliveryAddress;
  String? _deliveryAddressName;
  LatLng? _deliveryLocation;

  // ── Palette dynamique (light / dark) ──────────────────────
  late Color _accent;
  late Color _onAccent;
  late Color _bg;
  late Color _card;
  late Color _itemCard;
  late Color _mapBg;
  late Color _textPrimary;
  late Color _textSecondary;
  late Color _disabledBg;

  // ════════════════════════════════════════════════════════════
  // BUILD
  // ════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final isDark = ref.watch(themeNotifierProvider).isDarkMode;
    final c = isDark ? AppColors.dark : AppColors.light;
    _accent       = c.primary;
    _onAccent     = c.onPrimary;
    _bg           = isDark ? const Color(0xFF121212) : const Color(0xFFFFF5EE);
    _card         = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFFEEDE4);
    _itemCard     = isDark ? const Color(0xFF2A2A2A) : Colors.white;
    _mapBg        = isDark ? const Color(0xFF241A10) : const Color(0xFFE8C9B0);
    _textPrimary   = isDark ? Colors.white : const Color(0xFF1A1A1A);
    _textSecondary = isDark ? Colors.grey.shade400 : Colors.grey.shade600;
    _disabledBg    = isDark ? const Color(0xFF424242) : Colors.grey.shade300;

    final cart = ref.watch(cartProvider);

    if (cart.isEmpty) return _buildEmptyCart();

    // ── Fidélité : points utilisables plafonnés aux frais de livraison ──
    final available = ref.watch(availablePointsProvider);
    final maxByDelivery = cart.deliveryFee ~/ kPointValue;
    final maxUsable = available < maxByDelivery ? available : maxByDelivery;
    final pointsApplied = _pointsApplied.clamp(0, maxUsable);
    final discount = pointsApplied * kPointValue;

    return Scaffold(
      backgroundColor: _bg,
      body: Column(
        children: [
          _buildHeader(cart),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDeliverySection(),
                  const SizedBox(height: 24),
                  _buildSelectionSection(cart),
                  const SizedBox(height: 24),
                  _buildPaymentSection(),
                  const SizedBox(height: 24),
                  _buildPointsSection(available, maxUsable, pointsApplied),
                  const SizedBox(height: 24),
                  _buildSummarySection(cart, pointsApplied, discount),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
          _buildPlaceOrderButton(cart),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════
  // HEADER
  // ════════════════════════════════════════════════════════════

  Widget _buildHeader(CartState cart) {
    final restaurantName = cart.selectedRestaurant?.name ?? 'Votre commande';

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Icon(Icons.arrow_back_ios_rounded, color: _accent, size: 20),
                ),
                const SizedBox(width: 6),
                Icon(Icons.location_on, color: _accent, size: 16),
                const SizedBox(width: 4),
                Text(
                  tr('checkout'),
                  style: TextStyle(
                    color: _accent,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    letterSpacing: 0.3,
                  ),
                ),
                const Spacer(),
                Icon(Icons.search, color: _textSecondary, size: 22),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              restaurantName,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                fontStyle: FontStyle.italic,
                color: _textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════
  // DELIVERY ADDRESS
  // ════════════════════════════════════════════════════════════

  Widget _buildDeliverySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              tr('delivery_address'),
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: _textPrimary),
            ),
            GestureDetector(
              onTap: _pickAddress,
              child: Text(
                tr('change').toUpperCase(),
                style: TextStyle(
                  color: _accent,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: _pickAddress,
          child: Container(
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Aperçu carte
                ClipRRect(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(16)),
                  child: SizedBox(
                    height: 90,
                    width: double.infinity,
                    child: _deliveryLocation != null
                        ? Stack(
                            children: [
                              Container(color: _mapBg),
                              CustomPaint(
                                size: const Size(double.infinity, 90),
                                painter: _MapGridPainter(),
                              ),
                              Center(
                                child: Icon(Icons.location_on,
                                    color: _accent, size: 30),
                              ),
                            ],
                          )
                        : Container(
                            color: _mapBg,
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.map_outlined,
                                      color: Colors.brown.shade300, size: 28),
                                  const SizedBox(height: 4),
                                  Text(
                                    tr('tap_to_pick_map'),
                                    style: TextStyle(
                                        color: Colors.brown.shade400,
                                        fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                          ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _deliveryAddressName ?? tr('no_address_selected'),
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14, color: _textPrimary),
                      ),
                      if (_deliveryAddress != null &&
                          _deliveryAddress != _deliveryAddressName) ...[
                        const SizedBox(height: 2),
                        Text(
                          _deliveryAddress!,
                          style: TextStyle(
                              color: _textSecondary, fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.access_time,
                              size: 13, color: _textSecondary),
                          const SizedBox(width: 4),
                          Text(
                            tr('est_delivery'),
                            style: TextStyle(
                                color: _textSecondary, fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ════════════════════════════════════════════════════════════
  // YOUR SELECTION
  // ════════════════════════════════════════════════════════════

  Widget _buildSelectionSection(CartState cart) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr('your_selection'),
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: _textPrimary),
        ),
        const SizedBox(height: 12),
        ...cart.items.map((item) => _buildItemCard(item)),
      ],
    );
  }

  Widget _buildItemCard(OrderItem item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _itemCard,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          // Image circulaire
          ClipOval(
            child: item.imageUrl.isNotEmpty
                ? Image.network(
                    item.imageUrl,
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => _itemPlaceholder(),
                  )
                : _itemPlaceholder(),
          ),
          const SizedBox(width: 12),
          // Nom + contrôles quantité
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14, color: _textPrimary),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _qtyBtn(
                      icon: Icons.remove,
                      onTap: () => ref
                          .read(cartProvider.notifier)
                          .decrementQuantity(item),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        '${tr('qty')}: ${item.quantity}',
                        style: TextStyle(
                            color: _textSecondary, fontSize: 12),
                      ),
                    ),
                    _qtyBtn(
                      icon: Icons.add,
                      onTap: () => ref
                          .read(cartProvider.notifier)
                          .incrementQuantity(item),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Prix + retirer
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${item.totalPrice} FDJ',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _accent,
                    fontSize: 14),
              ),
              const SizedBox(height: 4),
              GestureDetector(
                onTap: () =>
                    ref.read(cartProvider.notifier).removeItem(item),
                child: Text(
                  tr('remove'),
                  style: TextStyle(color: Colors.red[300], fontSize: 11),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _qtyBtn({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(color: _card, shape: BoxShape.circle),
        child: Icon(icon, size: 13, color: _accent),
      ),
    );
  }

  Widget _itemPlaceholder() {
    return Container(
      width: 56,
      height: 56,
      color: _card,
      child: Icon(Icons.fastfood, color: _accent, size: 28),
    );
  }

  // ════════════════════════════════════════════════════════════
  // PAYMENT METHOD
  // ════════════════════════════════════════════════════════════

  Widget _buildPaymentSection() {
    final methods = [
      {'value': 'cash', 'label': tr('cash_label'), 'icon': Icons.payments_outlined},
      {'value': 'waafi', 'label': 'Waafi', 'icon': Icons.account_balance_wallet},
      {'value': 'd_money', 'label': 'D-Money', 'icon': Icons.account_balance_wallet},
      {'value': 'cac_pay', 'label': 'CAC Pay', 'icon': Icons.account_balance_wallet},
      {'value': 'bci', 'label': 'BCI', 'icon': Icons.account_balance},
      {'value': 'exim', 'label': 'EXIM Bank', 'icon': Icons.account_balance},
      {'value': 'dahab_plus', 'label': 'Dahab+', 'icon': Icons.account_balance_wallet},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr('payment_method'),
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: _textPrimary),
        ),
        const SizedBox(height: 12),
        ...methods.map((method) {
          final value = method['value'] as String;
          final selected = _selectedPaymentMethod == value;
          return GestureDetector(
            onTap: () => setState(() => _selectedPaymentMethod = value),
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: _card,
                borderRadius: BorderRadius.circular(14),
                border: selected
                    ? Border.all(
                        color: _accent.withValues(alpha: 0.5), width: 1.5)
                    : null,
              ),
              child: Row(
                children: [
                  Icon(method['icon'] as IconData,
                      color: _accent, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      method['label'] as String,
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w500, color: _textPrimary),
                    ),
                  ),
                  // Radio visuel
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected ? _accent : Colors.grey.shade400,
                        width: 2,
                      ),
                    ),
                    child: selected
                        ? Center(
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                  color: _accent, shape: BoxShape.circle),
                            ),
                          )
                        : null,
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  // ════════════════════════════════════════════════════════════
  // POINTS FIDÉLITÉ
  // ════════════════════════════════════════════════════════════

  Widget _buildPointsSection(int available, int maxUsable, int pointsApplied) {
    final hasPoints = available > 0;
    final canApply = maxUsable > 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.stars_rounded, color: _accent, size: 20),
              const SizedBox(width: 8),
              Text(
                tr('loyalty_points'),
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: _textPrimary),
              ),
              const Spacer(),
              Text(
                '$available pts',
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: _accent, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            hasPoints
                ? '1 point = $kPointValue FDJ · ${tr('usable_on_delivery')}'
                : tr('earn_points_hint'),
            style: TextStyle(color: _textSecondary, fontSize: 12),
          ),
          if (hasPoints) ...[
            const SizedBox(height: 14),
            if (pointsApplied > 0)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '$pointsApplied ${tr('points_applied')} · −${pointsApplied * kPointValue} FDJ',
                      style: TextStyle(
                          color: _accent,
                          fontWeight: FontWeight.w600,
                          fontSize: 13),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => setState(() => _pointsApplied = 0),
                    child: Text(tr('remove'),
                        style: TextStyle(color: Colors.red[300], fontSize: 12)),
                  ),
                ],
              )
            else
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: canApply
                      ? () => setState(() => _pointsApplied = maxUsable)
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: _onAccent,
                    minimumSize: const Size(0, 44),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                    disabledBackgroundColor: _disabledBg,
                    disabledForegroundColor: _textSecondary,
                  ),
                  child: Text(
                    canApply
                        ? '${tr('use')} $maxUsable ${tr('points_short')} (−${maxUsable * kPointValue} FDJ)'
                        : tr('amount_too_low'),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════
  // SUMMARY
  // ════════════════════════════════════════════════════════════

  Widget _buildSummarySection(
      CartState cart, int pointsApplied, int discount) {
    final total = cart.total - discount;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          _summaryRow(tr('subtotal'), '${cart.subtotal} FDJ'),
          const SizedBox(height: 10),
          _summaryRow(tr('delivery_fee'), '${cart.deliveryFee} FDJ'),
          if (discount > 0) ...[
            const SizedBox(height: 10),
            _summaryRow(
                '${tr('delivery_discount')} ($pointsApplied ${tr('points_short')})', '−$discount FDJ'),
          ],
          const Divider(height: 24, color: Color(0xFFE0C4B4)),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(tr('total'),
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 17, color: _textPrimary)),
              Text(
                '$total FDJ',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                    color: _accent),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(color: _textSecondary, fontSize: 14)),
        Text(value, style: TextStyle(fontSize: 14, color: _textPrimary)),
      ],
    );
  }

  // ════════════════════════════════════════════════════════════
  // PLACE ORDER BUTTON
  // ════════════════════════════════════════════════════════════

  Widget _buildPlaceOrderButton(CartState cart) {
    final hasAddress =
        _deliveryAddressName != null && _deliveryLocation != null;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      color: _bg,
      child: SafeArea(
        child: _isProcessing
            ? Center(
                child: CircularProgressIndicator(color: _accent))
            : SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: hasAddress ? _processOrder : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        hasAddress ? _accent : _disabledBg,
                    foregroundColor:
                        hasAddress ? Colors.white : _textSecondary,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28)),
                    elevation: 0,
                    disabledBackgroundColor: _disabledBg,
                    disabledForegroundColor: _textSecondary,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        hasAddress
                            ? tr('place_order')
                            : tr('choose_an_address'),
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      if (hasAddress) ...[
                        const SizedBox(width: 8),
                        const Icon(Icons.arrow_forward, size: 18),
                      ],
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════
  // EMPTY CART
  // ════════════════════════════════════════════════════════════

  Widget _buildEmptyCart() {
    return Scaffold(
      backgroundColor: _bg,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(color: _card, shape: BoxShape.circle),
                child: Icon(Icons.shopping_cart_outlined,
                    size: 80, color: _accent.withValues(alpha: 0.6)),
              ),
              const SizedBox(height: 24),
              Text(tr('cart_empty'),
                  style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold, color: _textPrimary)),
              const SizedBox(height: 8),
              Text(tr('add_dishes_continue'),
                  style: TextStyle(fontSize: 14, color: _textSecondary)),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: _onAccent,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28)),
                    elevation: 0,
                  ),
                  child: Text(tr('back_to_restaurants'),
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════
  // TRAITEMENT COMMANDE (logique métier inchangée)
  // ════════════════════════════════════════════════════════════

  Future<void> _processOrder() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      _showSnack(tr('must_login_order'), backgroundColor: Colors.red);
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const SignInScreen()),
      );
      return;
    }

    final userStateCheck = ref.read(userNotifierProvider);
    final hasPhone = (userStateCheck.phone?.trim().isNotEmpty ?? false) ||
        (userStateCheck.firebaseUser?.phoneNumber?.isNotEmpty ?? false);
    if (!hasPhone) {
      _showSnack('Merci de renseigner votre numéro de téléphone avant de commander',
          backgroundColor: Colors.orange);
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const CompletePhoneScreen()),
      );
      return;
    }

    final cart = ref.read(cartProvider);
    if (cart.isEmpty) {
      _showSnack(tr('cart_empty'), backgroundColor: Colors.orange);
      return;
    }
    // Garde-fou final : le restaurant a pu fermer entre l'ajout au panier et la
    // validation. On relit le statut FRAIS depuis Firestore plutôt que
    // `cart.selectedRestaurant`, qui — restauré depuis Hive après un
    // redémarrage — perd `isOpen` (défaut true) et laisserait passer la commande.
    final cartRestaurant = cart.selectedRestaurant;
    if (cartRestaurant != null) {
      final fresh =
          await RestaurantService().getRestaurantById(cartRestaurant.id);
      // fresh == null (resto introuvable/hors ligne) : on ne bloque pas sur une
      // simple erreur réseau, le backend reste le garde-fou ultime.
      if (fresh != null && !fresh.canOrder) {
        if (!mounted) return;
        final reopen = fresh.reopeningLabel;
        _showSnack(
          reopen == null
              ? '${fresh.name} est fermé, commande impossible.'
              : '${fresh.name} est fermé. $reopen.',
          backgroundColor: Colors.red,
        );
        return;
      }
    }
    // Après l'await ci-dessus, on ne réutilise le context que si toujours monté.
    if (!mounted) return;
    if (_deliveryAddressName == null || _deliveryLocation == null) {
      _showSnack(tr('please_choose_address'),
          backgroundColor: Colors.orange);
      return;
    }

    final userState = ref.read(userNotifierProvider);
    final customerName  = userState.name  ?? userState.firebaseUser?.displayName ?? 'Client';
    final customerPhone = userState.phone ?? userState.firebaseUser?.phoneNumber  ?? 'Non renseigné';

    final cartState = ref.read(cartProvider);
    final subtotal = cartState.items.fold<double>(0, (s, i) => s + i.totalPrice);
    final deliveryFee = cartState.deliveryFee.toDouble();
    final pointsDiscount = _pointsApplied * kPointValue;
    final total = (subtotal + deliveryFee - pointsDiscount).clamp(0.0, double.infinity);

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PendingOrderScreen(
          userId: user.uid,
          paymentMethod: _selectedPaymentMethod,
          deliveryAddress: _deliveryAddressName!,
          deliveryLocation: _deliveryLocation!,
          addressDetails: _deliveryAddress,
          customerName: customerName,
          customerPhone: customerPhone,
          pointsUsed: _pointsApplied,
          subtotal: subtotal,
          deliveryFee: deliveryFee,
          total: total,
        ),
      ),
    );
  }

  Future<void> _pickAddress() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
          builder: (_) => const DeliveryAddressPickerScreen()),
    );
    if (result != null && mounted) {
      setState(() {
        _deliveryAddressName = result['address'] as String?;
        _deliveryAddress = result['address'] as String?;
        _deliveryLocation = result['location'] as LatLng?;
      });
    }
  }

  void _showSnack(String msg, {Color? backgroundColor}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: backgroundColor),
    );
  }
}

// ════════════════════════════════════════════════════════════
// PAINTER — grille simulant une carte
// ════════════════════════════════════════════════════════════

class _MapGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFD4A882).withValues(alpha: 0.4)
      ..strokeWidth = 1;

    for (double x = 0; x < size.width; x += 28) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += 18) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_) => false;
}
