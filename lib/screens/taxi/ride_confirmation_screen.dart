import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nomade_client/constants.dart';
import 'package:nomade_client/providers/all_providers.dart';
import 'package:nomade_client/screens/auth-firebase/auth/complete_phone_screen.dart';
import 'package:nomade_client/screens/auth-firebase/auth/sign_in_screen.dart';
import 'package:nomade_client/theme/app_colors.dart';
import 'package:nomade_client/translations/app_translations.dart';
import 'package:nomade_client/models/place.dart';
import 'package:nomade_client/models/trip_details.dart';
import 'package:nomade_client/models/ride_choice.dart';
import 'tracking_screen.dart';

class RideConfirmationScreen extends ConsumerStatefulWidget {
  final Place       pickup;
  final Place       destination;
  final TripDetails tripDetails;

  /// Géométrie routière déjà calculée sur l'écran précédent. Vide si l'API
  /// d'itinéraire a échoué : on retombe alors sur la droite départ → arrivée.
  final List<LatLng> routePoints;

  const RideConfirmationScreen({
    super.key,
    required this.pickup,
    required this.destination,
    required this.tripDetails,
    this.routePoints = const [],
  });

  @override
  ConsumerState<RideConfirmationScreen> createState() =>
      _RideConfirmationScreenState();
}

class _RideConfirmationScreenState extends ConsumerState<RideConfirmationScreen> {

  String _selectedPaymentMethod = 'cash';
  late AppColors _c;
  late bool _isDark;

  // ════════════════════════════════════════════════════════════
  // LOGIC
  // ════════════════════════════════════════════════════════════

  Future<void> _confirmRide() async {
    final userState = ref.read(userNotifierProvider);
    if (!userState.isAuthenticated) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('must_login_order')), backgroundColor: _c.error),
      );
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const SignInScreen()),
      );
      return;
    }

    if (userState.verifiedPhone == null || userState.verifiedPhone!.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Merci de renseigner votre numéro de téléphone avant de commander'),
          backgroundColor: _c.error,
        ),
      );
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const CompletePhoneScreen()),
      );
      return;
    }

    try {
      final price = widget.tripDetails.selectedRide
          .calculatePrice(widget.tripDetails.distance);

      await ref.read(activeRideProvider.notifier).createRide(
        userId:               userState.userId!,
        userName:             userState.displayName,
        userPhone:            userState.verifiedPhone ?? '',
        userPhotoUrl:         userState.displayPhotoUrl,
        pickupLatitude:       widget.pickup.location.latitude,
        pickupLongitude:      widget.pickup.location.longitude,
        pickupAddress:        widget.pickup.address ?? widget.pickup.name,
        pickupPlaceName:      widget.pickup.name,
        destinationLatitude:  widget.destination.location.latitude,
        destinationLongitude: widget.destination.location.longitude,
        destinationAddress:   widget.destination.address ?? widget.destination.name,
        destinationPlaceName: widget.destination.name,
        distance:             widget.tripDetails.distance,
        estimatedDuration:    widget.tripDetails.duration,
        estimatedFare:        price,
        paymentMethod:        _selectedPaymentMethod,
        vehicleType:          widget.tripDetails.selectedRide.id,
      );

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const TrackingScreen()),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${tr('error')}: $e'), backgroundColor: _c.error),
        );
      }
    }
  }

  // ════════════════════════════════════════════════════════════
  // VEHICLE HELPERS
  // ════════════════════════════════════════════════════════════

  Widget _vehicleImage(RideChoice rc) {
    final id   = rc.id.toLowerCase();
    final name = rc.name.toLowerCase();
    final path = id.contains('comfort') || name.contains('comfort')
        ? 'assets/vehicule/taxi-A.png'
        : id.contains('van') || name.contains('van') || name.contains('minibus')
            ? 'assets/vehicule/taxiprobox.png'
            : 'assets/vehicule/taxi-B.png';

    return Image.asset(
      path,
      width: 48,
      height: 48,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) =>
          Icon(Icons.directions_car, color: _c.primary, size: 32),
    );
  }

  String _carModel(RideChoice rc) {
    final name = rc.name.toLowerCase();
    if (name.contains('comfort') || name.contains('confort')) return 'Toyota Prius';
    if (name.contains('van')     || name.contains('minibus'))  return 'Toyota Hiace';
    return 'Toyota Corolla';
  }

  // ════════════════════════════════════════════════════════════
  // TEXT STYLE HELPERS
  // ════════════════════════════════════════════════════════════

  TextStyle _label() => GoogleFonts.spaceGrotesk(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: _c.onSurfaceVariant,
        letterSpacing: 2.0,
      );

  TextStyle _mono(double size, Color color) => GoogleFonts.spaceGrotesk(
        fontSize: size,
        fontWeight: FontWeight.w800,
        color: color,
        letterSpacing: -0.5,
      );

  // ════════════════════════════════════════════════════════════
  // BUILD
  // ════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    _isDark = ref.watch(themeNotifierProvider).isDarkMode;
    _c = _isDark ? AppColors.dark : AppColors.light;

    final price      = widget.tripDetails.selectedRide
        .calculatePrice(widget.tripDetails.distance);
    final isCreating = ref.watch(
        activeRideProvider.select((s) => s.isCreating));

    final tileUrl = _isDark
        ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png'
        : 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png';

    return Scaffold(
      backgroundColor: _c.bg,
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildMapSection(tileUrl),
                        const SizedBox(height: 16),
                        _buildDetailsSection(),
                        const SizedBox(height: 12),
                        _buildDriverCard(),
                        const SizedBox(height: 12),
                        _buildPriceCard(price),
                        const SizedBox(height: 120),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          _buildConfirmButton(isCreating),
        ],
      ),
    );
  }

  // ── Header ───────────────────────────────────────────────────

  Widget _buildHeader() {
    return Container(
      color: _c.bg,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Icon(Icons.arrow_back, color: _c.primary),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              'CONFIRMER VOTRE COURSE',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: _c.primary,
                letterSpacing: -0.5,
              ),
            ),
          ),
          Icon(Icons.settings_outlined, color: _c.onSurfaceVariant),
        ],
      ),
    );
  }

  // ── Map ──────────────────────────────────────────────────────

  Widget _buildMapSection(String tileUrl) {
    final midLat = (widget.pickup.location.latitude +
            widget.destination.location.latitude) /
        2;
    final midLng = (widget.pickup.location.longitude +
            widget.destination.location.longitude) /
        2;

    return SizedBox(
      height: 280,
      child: Stack(
        children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: LatLng(midLat, midLng),
              initialZoom: 12.0,
              interactionOptions:
                  const InteractionOptions(flags: InteractiveFlag.none),
            ),
            children: [
              TileLayer(
                urlTemplate: tileUrl,
                subdomains: const ['a', 'b', 'c', 'd'],
              ),
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: widget.routePoints.length >= 2
                        ? widget.routePoints
                        : [
                            widget.pickup.location,
                            widget.destination.location,
                          ],
                    strokeWidth: 3,
                    color: _c.primary.withValues(alpha: 0.6),
                  ),
                ],
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: widget.pickup.location,
                    width: 32,
                    height: 32,
                    child: Container(
                      color: _c.primary,
                      child: Icon(Icons.location_on,
                          color: _c.onPrimary, size: 20),
                    ),
                  ),
                  Marker(
                    point: widget.destination.location,
                    width: 32,
                    height: 32,
                    child: Container(
                      color: _c.onSurface,
                      child: Icon(Icons.flag, color: _c.bg, size: 20),
                    ),
                  ),
                ],
              ),
            ],
          ),
          // SYSTEM_LINK chip — top right
          Positioned(
            top: 16,
            right: 16,
            child: Container(
              color: _c.surfaceTop.withValues(alpha: 0.9),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.satellite_alt, color: _c.primary, size: 12),
                  const SizedBox(width: 6),
                  Text(
                    'SYSTEM_LINK: ACTIVE',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: _c.onSurface,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // GPS chip — bottom left
          Positioned(
            bottom: 16,
            left: 16,
            right: 80,
            child: Container(
              color: _c.surfaceTop.withValues(alpha: 0.9),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('CURRENT_GPS', style: _label()),
                  const SizedBox(height: 2),
                  Text(
                    widget.pickup.name.toUpperCase(),
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _c.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Ride Details ─────────────────────────────────────────────

  Widget _buildDetailsSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      color: _c.surfaceLow,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(tr('ride_details').toUpperCase(), style: _label()),
              Text(
                'v1.0_ID',
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 10, color: _c.primary, letterSpacing: 1),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                    color: _c.outlineVariant.withValues(alpha: 0.4), width: 1),
              ),
            ),
            padding: const EdgeInsets.only(left: 16),
            child: Column(
              children: [
                _locationRow(
                  icon: Icons.radio_button_checked,
                  label: tr('origin').toUpperCase(),
                  value: widget.pickup.address ?? widget.pickup.name,
                ),
                const SizedBox(height: 16),
                _locationRow(
                  icon: Icons.location_on,
                  label: tr('destination').toUpperCase(),
                  value: widget.destination.address ?? widget.destination.name,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Container(height: 1, color: _c.outlineVariant.withValues(alpha: 0.2)),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _metricRow(
                  icon: Icons.schedule_outlined,
                  label: tr('estimation').toUpperCase(),
                  value: '${widget.tripDetails.duration} MIN',
                ),
              ),
              Expanded(
                child: _metricRow(
                  icon: Icons.route_outlined,
                  label: tr('distance').toUpperCase(),
                  value: '${widget.tripDetails.distance.toStringAsFixed(1)} KM',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _locationRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: _c.primary, size: 20),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: _label()),
              const SizedBox(height: 2),
              Text(
                value,
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: _c.onSurface,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _metricRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Icon(icon, color: _c.onSurfaceVariant, size: 20),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: _label()),
            Text(value, style: _mono(14, _c.primary)),
          ],
        ),
      ],
    );
  }

  // ── Driver / Vehicle Card ────────────────────────────────────

  Widget _buildDriverCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      color: _c.surface,
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            color: _c.surfaceHigh,
            child: _vehicleImage(widget.tripDetails.selectedRide),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('assigned_pilot').toUpperCase(), style: _label()),
                const SizedBox(height: 4),
                Text(
                  _carModel(widget.tripDetails.selectedRide).toUpperCase(),
                  style: _mono(18, _c.onSurface),
                ),
              ],
            ),
          ),
          Icon(Icons.directions_car, color: _c.primary, size: 36),
        ],
      ),
    );
  }

  // ── Price Card ───────────────────────────────────────────────

  Widget _buildPriceCard(double price) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _c.surface,
        border: Border(left: BorderSide(color: _c.primary, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('transaction_cost').toUpperCase(), style: _label()),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                price.toStringAsFixed(0),
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 52,
                  fontWeight: FontWeight.w900,
                  color: _c.primary,
                  height: 1,
                  letterSpacing: -2,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'FDJ',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: _c.primary.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: _showPaymentMethods,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _c.primary,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _paymentLabel(_selectedPaymentMethod),
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: _c.primary,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.keyboard_arrow_down, color: _c.primary, size: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _paymentLabel(String method) {
    switch (method) {
      case 'cash':       return 'ESPÈCES';
      case 'waafi':      return 'WAAFI';
      case 'd_money':    return 'D-MONEY';
      case 'cac_pay':    return 'CAC PAY';
      case 'bci':        return 'BCI';
      case 'exim':       return 'EXIM BANK';
      case 'dahab_plus': return 'DAHAB+';
      default:           return method.toUpperCase();
    }
  }

  // ── Confirm Button ───────────────────────────────────────────

  Widget _buildConfirmButton(bool isCreating) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        color: _c.bg,
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: GestureDetector(
          onTap: isCreating ? null : _confirmRide,
          child: Container(
            width: double.infinity,
            height: 64,
            decoration: const BoxDecoration(color: kNeonGreen),
            child: isCreating
                ? const Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                          color: kNeonGreenDark, strokeWidth: 2),
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        tr('confirm').toUpperCase(),
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: kNeonGreenDark,
                          letterSpacing: 3,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Icon(Icons.keyboard_double_arrow_right,
                          color: kNeonGreenDark, size: 24),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  // ── Payment Methods Sheet ────────────────────────────────────

  void _showPaymentMethods() {
    final c = _c;
    showModalBottomSheet(
      context: context,
      backgroundColor: c.surfaceLow,
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 20),
          Text(
            tr('payment_method').toUpperCase(),
            style: GoogleFonts.spaceGrotesk(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: c.onSurfaceVariant,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 12),
          _paymentTile('cash', tr('cash_label'), Icons.payments_outlined, c),
          _paymentTile('waafi', 'Waafi', Icons.account_balance_wallet, c),
          _paymentTile('d_money', 'D-Money', Icons.account_balance_wallet, c),
          _paymentTile('cac_pay', 'CAC Pay', Icons.account_balance_wallet, c),
          _paymentTile('bci', 'BCI', Icons.account_balance, c),
          _paymentTile('exim', 'EXIM Bank', Icons.account_balance, c),
          _paymentTile('dahab_plus', 'Dahab+', Icons.account_balance_wallet, c),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _paymentTile(String value, String title, IconData icon, AppColors c) {
    final selected = _selectedPaymentMethod == value;
    return InkWell(
      onTap: () {
        setState(() => _selectedPaymentMethod = value);
        Navigator.pop(context);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        color: selected
            ? c.primary.withValues(alpha: 0.08)
            : Colors.transparent,
        child: Row(
          children: [
            Icon(icon,
                color: selected ? c.primary : c.onSurfaceVariant, size: 20),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: selected ? c.primary : c.onSurface,
                ),
              ),
            ),
            if (selected)
              Icon(Icons.check, color: c.primary, size: 18),
          ],
        ),
      ),
    );
  }
}
