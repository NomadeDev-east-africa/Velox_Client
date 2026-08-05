import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nomade_client/models/order.dart';
import 'package:nomade_client/providers/all_providers.dart';
import 'package:nomade_client/theme/app_colors.dart';
import 'order_completed_screen.dart';
import 'track_delivery_screen.dart';

class OrderTrackingScreen extends ConsumerStatefulWidget {
  final String? orderId;
  const OrderTrackingScreen({super.key, this.orderId});

  @override
  ConsumerState<OrderTrackingScreen> createState() => _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends ConsumerState<OrderTrackingScreen> {
  // Couleurs courantes — mises à jour à chaque build
  late AppColors _c;

  bool   _attachTriggered = false;
  Order? _completedOrder;

  @override
  void initState() {
    super.initState();
    if (widget.orderId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _tryAttachOrder());
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _tryAttachOrder() {
    if (_attachTriggered || !mounted) return;
    final currentState = ref.read(activeOrderProvider);
    if (currentState.order == null &&
        !currentState.isLoading &&
        widget.orderId != null) {
      _attachTriggered = true;
      debugPrint('📎 [OrderTracking] Auto-attach orderId: ${widget.orderId}');
      ref.read(activeOrderProvider.notifier).attachOrder(widget.orderId!);
    }
  }

  // ── HELPERS ───────────────────────────────────────────────────────────────

  int _getCurrentStepIndex(String status) {
    switch (status) {
      case Order.statusPending:
      case Order.statusConfirmed:
      case Order.statusAccepted:   return 0;
      case Order.statusPreparing:  return 1;
      case Order.statusReady:      return 2;
      case Order.statusDelivering: return 3;
      case Order.statusCompleted:  return 4;
      default:                     return 0;
    }
  }

  String _sessionId(String orderId) =>
      '#${orderId.substring(0, 8).toUpperCase()}';

  // ── BUILD ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = ref.watch(themeNotifierProvider).isDarkMode;
    _c = isDark ? AppColors.dark : AppColors.light;
    final orderState = ref.watch(activeOrderProvider);

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: _c.bg,
        appBar: _buildAppBar(orderState.order),
        body: _buildBody(orderState),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(Order? order) {
    return AppBar(
      backgroundColor: _c.bg,
      elevation: 0,
      automaticallyImplyLeading: false,
      // Vrai bouton retour (l'AppBar n'en avait aucun → l'utilisateur restait
      // piégé sur le suivi). Quitter est sûr : la commande continue et reste
      // accessible via la pastille flottante globale.
      leading: IconButton(
        icon: Icon(Icons.arrow_back_ios_new, color: _c.onSurface, size: 20),
        onPressed: _leaveTracking,
      ),
      title: const Text(
        'Velox',
        style: TextStyle(
          color: Color(0xFF9FFF88),
          fontWeight: FontWeight.bold,
          fontSize: 20,
        ),
      ),
      centerTitle: true,
    );
  }

  /// Quitte l'écran de suivi. `PopScope(canPop:false)` bloque le retour système
  /// accidentel (swipe) ; ce bouton fait un pop explicite (non bloqué) et
  /// rappelle que la commande continue via la pastille.
  void _leaveTracking() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        content: Text(
          'Votre commande continue — suivez-la depuis la pastille en bas.',
        ),
        behavior: SnackBarBehavior.floating,
      ));
    final nav = Navigator.of(context);
    // canPop est toujours vrai ici (le suivi est poussé au-dessus de l'accueil) ;
    // le garde évite juste un pop sur une route racine improbable.
    if (nav.canPop()) nav.pop();
  }

  // ── BODY ROUTING ─────────────────────────────────────────────────────────

  Widget _buildBody(ActiveOrderState orderState) {
    if (orderState.order != null &&
        orderState.order!.status == Order.statusCompleted) {
      _completedOrder = orderState.order;
    }

    if (orderState.isLoading ||
        (widget.orderId != null &&
            orderState.order == null &&
            !orderState.isTerminated &&
            _completedOrder == null)) {
      return _buildLoadingView();
    }

    if (orderState.error != null &&
        orderState.order == null &&
        _completedOrder == null) {
      return _buildErrorView(orderState.error!);
    }

    if (orderState.order == null && _completedOrder != null) {
      return _buildMainContent(_completedOrder!, isCompletedCache: true);
    }

    if (orderState.order == null && _attachTriggered) {
      return _buildTerminalView();
    }

    if (orderState.order == null) {
      return _buildLoadingView();
    }

    return _buildMainContent(orderState.order!, isWatching: orderState.isWatching);
  }

  // ── MAIN CONTENT ─────────────────────────────────────────────────────────

  Widget _buildMainContent(
    Order order, {
    bool isWatching = false,
    bool isCompletedCache = false,
  }) {
    final isDelivering = order.status == Order.statusDelivering;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildPageHeader(order, isDelivering: isDelivering),
                _buildMapPlaceholder(order, isDelivering: isDelivering, isWatching: isWatching),
                _buildStepper(order),
                _buildProviderOrDetails(order, isDelivering: isDelivering),
                if (!isDelivering) _buildManifest(order),
                if (isDelivering) _buildDetailsCard(order),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
        _buildBottomActions(order, isCompletedCache: isCompletedCache),
      ],
    );
  }

  // ── PAGE HEADER ──────────────────────────────────────────────────────────

  Widget _buildPageHeader(Order order, {required bool isDelivering}) {
    if (!isDelivering) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(width: 3, color: _c.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'CURRENT OPERATION',
                          style: TextStyle(
                            color: _c.onSurfaceVariant,
                            fontSize: 11,
                            letterSpacing: 2,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'SUIVI DE\nCOMMANDE',
                          style: TextStyle(
                            color: _c.onSurface,
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -1,
                            height: 1.05,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'SESSION ID',
                      style: TextStyle(
                        color: _c.onSurfaceVariant,
                        fontSize: 10,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      _sessionId(order.id),
                      style: TextStyle(
                        color: _c.primary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SUIVI DE COMMANDE',
            style: TextStyle(
              color: _c.onSurface,
              fontSize: 28,
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildInfoCol('IDENTIFICATION', _sessionId(order.id))),
              Expanded(child: _buildInfoCol('ETABLISSEMENT', order.restaurantName)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCol(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: _c.onSurfaceVariant,
            fontSize: 10,
            letterSpacing: 1.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        IntrinsicHeight(
          child: Row(
            children: [
              Container(width: 2, color: _c.primary),
              const SizedBox(width: 6),
              Text(
                value,
                style: TextStyle(
                  color: _c.onSurface,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── MAP PLACEHOLDER ───────────────────────────────────────────────────────

  Widget _buildMapPlaceholder(
    Order order, {
    required bool isDelivering,
    required bool isWatching,
  }) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      height: isDelivering ? 200 : 140,
      decoration: BoxDecoration(
        color: _c.surfaceLow,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: _c.outlineVariant.withValues(alpha: 0.2)),
      ),
      clipBehavior: Clip.hardEdge,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(painter: _GridPainter(_c.primary)),
          Center(
            child: Icon(
              isDelivering ? Icons.delivery_dining : Icons.map_outlined,
              color: _c.primary.withValues(alpha: 0.15),
              size: 64,
            ),
          ),
          Positioned(
            top: 10,
            right: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _c.surfaceHigh,
                border: Border.all(color: _c.primary.withValues(alpha: 0.5)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6, height: 6,
                    decoration: BoxDecoration(
                      color: _c.primary, shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    isDelivering ? 'LIVE TELEMETRY ACTIVE' : 'SIGNAL: OPTIMAL',
                    style: TextStyle(
                      color: _c.primary,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── STEPPER ───────────────────────────────────────────────────────────────

  Widget _buildStepper(Order order) {
    final steps = [
      _StepData(label: 'Confirmée',    subLabel: 'Order validated by system',          subLabelDelivering: 'Order received by system'),
      _StepData(label: 'Préparation',  subLabel: 'Chef is assembling your order',      subLabelDelivering: 'Chef is currently processing the order'),
      _StepData(label: 'Prête',        subLabel: 'Awaiting pick-up',                   subLabelDelivering: 'Packaging completed. Awaiting pick-up'),
      _StepData(label: 'En livraison', subLabel: 'En route vers vous',                 subLabelDelivering: 'Driver is on the way to your location'),
      _StepData(label: 'Livrée',       subLabel: '',                                   subLabelDelivering: ''),
    ];

    final currentIndex  = _getCurrentStepIndex(order.status);
    final isDelivering  = order.status == Order.statusDelivering;
    const deliveringIdx = 3;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _c.surfaceLow,
          border: Border.all(color: _c.outlineVariant.withValues(alpha: 0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'PROCESS STATUS',
              style: TextStyle(
                color: _c.onSurfaceVariant,
                fontSize: 10,
                letterSpacing: 2,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            ...steps.asMap().entries.map((entry) {
              final i         = entry.key;
              final step      = entry.value;
              final isDone    = i < currentIndex;
              final isCurrent = i == currentIndex;
              final isLast    = i == steps.length - 1;

              final showVoirLivreur = i == deliveringIdx &&
                  order.status == Order.statusDelivering &&
                  order.deliveryDriverId != null;

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    children: [
                      _buildStepIcon(isDone: isDone, isCurrent: isCurrent),
                      if (!isLast)
                        Container(
                          width: 2,
                          height: 36,
                          color: isDone
                              ? _c.primary
                              : _c.outlineVariant.withValues(alpha: 0.3),
                        ),
                    ],
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(bottom: isLast ? 0 : 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  step.label.toUpperCase(),
                                  style: TextStyle(
                                    color: isCurrent
                                        ? _c.primary
                                        : isDone
                                            ? _c.onSurface
                                            : _c.outlineVariant,
                                    fontSize: 13,
                                    fontWeight: isCurrent || isDone
                                        ? FontWeight.w800
                                        : FontWeight.w500,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                              if (showVoirLivreur)
                                GestureDetector(
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => TrackDeliveryScreen(
                                        orderId:          order.id,
                                        livreurId:        order.deliveryDriverId!,
                                        livreurName:      order.deliveryDriverName,
                                        deliveryLocation: order.deliveryLocation,
                                      ),
                                    ),
                                  ),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                          color: _c.onSurface.withValues(alpha: 0.5)),
                                    ),
                                    child: Text(
                                      'VOIR LIVREUR',
                                      style: TextStyle(
                                        color: _c.onSurface,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          if ((isCurrent || isDone) &&
                              (isDelivering
                                      ? step.subLabelDelivering
                                      : step.subLabel)
                                  .isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                isDelivering
                                    ? step.subLabelDelivering
                                    : step.subLabel,
                                style: TextStyle(
                                  color: _c.onSurfaceVariant.withValues(alpha: 0.7),
                                  fontSize: 11,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildStepIcon({required bool isDone, required bool isCurrent}) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: Colors.transparent,
        border: Border.all(
          color: isDone || isCurrent ? _c.primary : _c.outlineVariant,
          width: 1.5,
        ),
      ),
      child: isDone
          ? Icon(Icons.check, color: _c.onPrimary, size: 14)
          : isCurrent
              ? Container(margin: const EdgeInsets.all(4), color: _c.primary)
              : null,
    );
  }

  // ── PROVIDER (non-delivering) ─────────────────────────────────────────────

  Widget _buildProviderOrDetails(Order order, {required bool isDelivering}) {
    if (isDelivering) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _c.surfaceLow,
          border: Border.all(color: _c.outlineVariant.withValues(alpha: 0.15)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _c.surfaceHigh,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Icon(Icons.restaurant, color: _c.onSurfaceVariant, size: 22),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PROVIDER',
                  style: TextStyle(
                    color: _c.onSurfaceVariant,
                    fontSize: 10,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  order.restaurantName.toUpperCase(),
                  style: TextStyle(
                    color: _c.onSurface,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── MANIFEST (non-delivering) ─────────────────────────────────────────────

  Widget _buildManifest(Order order) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'MANIFEST CONTENT',
            style: TextStyle(
              color: _c.onSurfaceVariant,
              fontSize: 10,
              letterSpacing: 2,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          ...order.items.map((item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Text(
                      '${item.quantity}x  ${item.name.toUpperCase()}',
                      style: TextStyle(color: _c.onSurface, fontSize: 13),
                    ),
                    const Spacer(),
                    Text(
                      '${item.totalPrice} FDJ',
                      style: TextStyle(color: _c.onSurface, fontSize: 13),
                    ),
                  ],
                ),
              )),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Text('LIVRAISON',
                    style: TextStyle(color: _c.onSurfaceVariant, fontSize: 13)),
                const Spacer(),
                Text('${order.deliveryFee} FDJ',
                    style: TextStyle(color: _c.onSurfaceVariant, fontSize: 13)),
              ],
            ),
          ),
          Divider(color: _c.outlineVariant.withValues(alpha: 0.3), height: 20),
          Row(
            children: [
              Text(
                'TOTAL PAYLOAD',
                style: TextStyle(
                  color: _c.onSurfaceVariant,
                  fontSize: 11,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '${order.total} FDJ',
                style: TextStyle(
                  color: _c.primary,
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              'AUTHORIZED COMMAND ONLY · REF ${_sessionId(order.id)}',
              style: TextStyle(
                color: _c.onSurfaceVariant.withValues(alpha: 0.4),
                fontSize: 9,
                letterSpacing: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── DETAILS CARD (delivering) ─────────────────────────────────────────────

  Widget _buildDetailsCard(Order order) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _c.surfaceLow,
          border: Border.all(color: _c.outlineVariant.withValues(alpha: 0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'DÉTAILS DE LA COMMANDE',
              style: TextStyle(
                color: _c.onSurfaceVariant,
                fontSize: 10,
                letterSpacing: 1.8,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            ...order.items.map((item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Text('${item.quantity}x ${item.name.toLowerCase()}',
                          style: TextStyle(color: _c.onSurface, fontSize: 13)),
                      const Spacer(),
                      Text('${item.totalPrice}  FDJ',
                          style: TextStyle(color: _c.onSurface, fontSize: 13)),
                    ],
                  ),
                )),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Text('Livraison',
                      style: TextStyle(color: _c.onSurfaceVariant, fontSize: 13)),
                  const Spacer(),
                  Text('${order.deliveryFee}  FDJ',
                      style: TextStyle(color: _c.onSurfaceVariant, fontSize: 13)),
                ],
              ),
            ),
            Divider(color: _c.outlineVariant.withValues(alpha: 0.3), height: 20),
            Row(
              children: [
                Text(
                  'TOTAL',
                  style: TextStyle(
                    color: _c.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
                const Spacer(),
                Text(
                  '${order.total} FDJ',
                  style: TextStyle(
                    color: _c.primary,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── BOTTOM ACTIONS ────────────────────────────────────────────────────────

  Widget _buildBottomActions(Order order, {bool isCompletedCache = false}) {
    if (order.status != Order.statusCompleted && !isCompletedCache) {
      return const SizedBox.shrink();
    }
    return Container(
      color: _c.bg,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      child: GestureDetector(
        onTap: () => Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => OrderCompletedScreen(
                order: isCompletedCache ? _completedOrder! : order),
          ),
        ),
        child: Container(
          width: double.infinity,
          height: 54,
          color: _c.primary,
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle, color: _c.onPrimary, size: 18),
              const SizedBox(width: 8),
              Text(
                'CONFIRMER LA LIVRAISON',
                style: TextStyle(
                  color: _c.onPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── STATES ────────────────────────────────────────────────────────────────

  Widget _buildLoadingView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: _c.primary, strokeWidth: 2),
          const SizedBox(height: 16),
          Text('Chargement de votre commande...',
              style: TextStyle(color: _c.onSurfaceVariant, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildTerminalView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64, height: 64,
            color: _c.primary.withValues(alpha: 0.1),
            child: Icon(Icons.check, color: _c.primary, size: 36),
          ),
          const SizedBox(height: 16),
          Text(
            'COMMANDE TERMINÉE',
            style: TextStyle(
              color: _c.onSurface,
              fontSize: 16,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: _c.error),
            const SizedBox(height: 16),
            Text('Erreur: $error',
                textAlign: TextAlign.center,
                style: TextStyle(color: _c.onSurfaceVariant)),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () => Navigator.of(context).popUntil((r) => r.isFirst),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                color: _c.primary,
                child: Text(
                  'RETOUR À L\'ACCUEIL',
                  style: TextStyle(
                    color: _c.onPrimary,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Data class pour les étapes ────────────────────────────────────────────────

class _StepData {
  final String label;
  final String subLabel;
  final String subLabelDelivering;
  const _StepData({
    required this.label,
    required this.subLabel,
    required this.subLabelDelivering,
  });
}

// ── Painter grille map ────────────────────────────────────────────────────────

class _GridPainter extends CustomPainter {
  final Color color;
  const _GridPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.04)
      ..strokeWidth = 0.5;

    const step = 24.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => old.color != color;
}
