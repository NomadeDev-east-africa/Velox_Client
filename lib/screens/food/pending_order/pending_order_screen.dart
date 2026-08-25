import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:nomade_client/providers/all_providers.dart';
import 'package:nomade_client/screens/food/food_tracking/order_tracking_screen.dart';
import 'package:nomade_client/theme/app_colors.dart';
import 'package:nomade_client/translations/app_translations.dart';

class PendingOrderScreen extends ConsumerStatefulWidget {
  const PendingOrderScreen({
    super.key,
    required this.userId,
    required this.paymentMethod,
    required this.deliveryAddress,
    required this.deliveryLocation,
    this.addressDetails,
    this.customerName,
    this.customerPhone,
    required this.pointsUsed,
    this.promoCode,
    this.promoDiscount = 0,
    required this.subtotal,
    required this.deliveryFee,
    required this.total,
  });

  final String userId;
  final String paymentMethod;
  final String deliveryAddress;
  final LatLng deliveryLocation;
  final String? addressDetails;
  final String? customerName;
  final String? customerPhone;
  final int pointsUsed;
  final String? promoCode;
  final int promoDiscount;
  final double subtotal;
  final double deliveryFee;
  final double total;

  @override
  ConsumerState<PendingOrderScreen> createState() => _PendingOrderScreenState();
}

class _PendingOrderScreenState extends ConsumerState<PendingOrderScreen>
    with SingleTickerProviderStateMixin {
  static const _countdownSeconds = 60;

  late int _secondsLeft;
  Timer? _timer;
  bool _isCreating = false;
  late AnimationController _progressController;

  @override
  void initState() {
    super.initState();
    _secondsLeft = _countdownSeconds;
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: _countdownSeconds),
    )..forward();

    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() {
        _secondsLeft--;
        if (_secondsLeft <= 0) {
          t.cancel();
          _createOrder();
        }
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _progressController.dispose();
    super.dispose();
  }

  Future<void> _createOrder() async {
    if (_isCreating) return;
    _timer?.cancel();
    setState(() => _isCreating = true);

    try {
      final orderId = await ref.read(cartProvider.notifier).createOrder(
            userId: widget.userId,
            paymentMethod: widget.paymentMethod,
            deliveryAddress: widget.deliveryAddress,
            deliveryLocation: widget.deliveryLocation,
            addressDetails: widget.addressDetails,
            customerName: widget.customerName,
            customerPhone: widget.customerPhone,
            pointsUsed: widget.pointsUsed,
            promoCode: widget.promoCode,
            promoDiscount: widget.promoDiscount,
          );

      if (!mounted) return;

      if (orderId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('order_creation_error'))),
        );
        Navigator.of(context).pop();
        return;
      }

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => OrderTrackingScreen(orderId: orderId)),
        (route) => route.isFirst,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${tr('error')}: $e')),
        );
        Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ref.watch(themeNotifierProvider).isDarkMode;
    final c = isDark ? AppColors.dark : AppColors.light;

    return PopScope(
      canPop: !_isCreating,
      child: Scaffold(
        backgroundColor: c.bg,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: _isCreating
                ? _buildCreatingView(c)
                : _buildCountdownView(c),
          ),
        ),
      ),
    );
  }

  Widget _buildCountdownView(AppColors c) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Spacer(),

        // Countdown circle
        SizedBox(
          width: 180,
          height: 180,
          child: Stack(
            fit: StackFit.expand,
            children: [
              AnimatedBuilder(
                animation: _progressController,
                builder: (_, child) => CircularProgressIndicator(
                  value: 1 - _progressController.value,
                  strokeWidth: 8,
                  backgroundColor: c.outlineVariant.withValues(alpha: 0.3),
                  color: c.primary,
                ),
              ),
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '$_secondsLeft',
                      style: TextStyle(
                        fontSize: 56,
                        fontWeight: FontWeight.w900,
                        color: c.onSurface,
                      ),
                    ),
                    Text(
                      'sec',
                      style: TextStyle(fontSize: 16, color: c.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 32),

        Text(
          'Votre commande sera envoyée dans',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18, color: c.onSurface, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          'Commande en cours de préparation…',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: c.onSurfaceVariant),
        ),

        const SizedBox(height: 40),

        // Order summary
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              _summaryRow(c, 'Sous-total', '${widget.subtotal.toStringAsFixed(0)} FDJ'),
              const SizedBox(height: 8),
              _summaryRow(c, 'Livraison', '${widget.deliveryFee.toStringAsFixed(0)} FDJ'),
              if (widget.pointsUsed > 0) ...[
                const SizedBox(height: 8),
                _summaryRow(c, 'Points utilisés', '- ${widget.pointsUsed} pts',
                    valueColor: Colors.green),
              ],
              if (widget.promoDiscount > 0) ...[
                const SizedBox(height: 8),
                _summaryRow(c, 'Code ${widget.promoCode ?? ''}'.trim(),
                    '- ${widget.promoDiscount} FDJ',
                    valueColor: Colors.green),
              ],
              const Divider(height: 24),
              _summaryRow(c, 'Total', '${widget.total.toStringAsFixed(0)} FDJ',
                  isBold: true),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // Confirm now button
        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            onPressed: _createOrder,
            style: ElevatedButton.styleFrom(
              backgroundColor: c.primary,
              foregroundColor: c.onPrimary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(
              'ENVOYER MAINTENANT',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
                color: c.onPrimary,
              ),
            ),
          ),
        ),

        const SizedBox(height: 12),

        // Cancel button
        SizedBox(
          width: double.infinity,
          height: 48,
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Annuler',
              style: TextStyle(fontSize: 15, color: c.onSurfaceVariant),
            ),
          ),
        ),

        const Spacer(),
      ],
    );
  }

  Widget _buildCreatingView(AppColors c) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CircularProgressIndicator(color: c.primary),
        const SizedBox(height: 24),
        Text(
          'Envoi de la commande…',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: c.onSurface),
        ),
      ],
    );
  }

  Widget _summaryRow(AppColors c, String label, String value,
      {bool isBold = false, Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(
                color: c.onSurfaceVariant,
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
        Text(value,
            style: TextStyle(
                color: valueColor ?? c.onSurface,
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
      ],
    );
  }
}
