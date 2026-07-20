import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nomade_client/providers/all_providers.dart';
import 'package:nomade_client/screens/auth-firebase/auth/sign_in_screen.dart';
import 'package:nomade_client/screens/taxi/taxi_home_screen.dart';
import 'package:nomade_client/screens/food/home_food/home_screen_food.dart';
import 'package:nomade_client/screens/profile/profile_screen.dart';
import 'package:nomade_client/screens/history/order_history_screen.dart';
import 'package:nomade_client/theme/app_colors.dart';
import 'package:nomade_client/translations/app_translations.dart';

class HomeScreenApp extends ConsumerStatefulWidget {
  const HomeScreenApp({super.key});

  @override
  ConsumerState<HomeScreenApp> createState() => _HomeScreenAppState();
}

class _HomeScreenAppState extends ConsumerState<HomeScreenApp> {
  int _selectedIndex = 0;
  final PageController _pageController = PageController();

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goToTaxi() {
    if (!mounted) return;
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => const TaxiHomeScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            SlideTransition(
              position: Tween(begin: const Offset(1, 0), end: Offset.zero)
                  .chain(CurveTween(curve: Curves.easeInOut))
                  .animate(animation),
              child: child,
            ),
      ),
    );
  }

  void _goToRestaurants() {
    if (!mounted) return;
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => const HomeScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  void _onItemTapped(int index) {
    if (!mounted) return;
    if (index == 1) {
      Navigator.push(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => const ProfileScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) =>
              SlideTransition(
                position: Tween(begin: const Offset(0, 1), end: Offset.zero)
                    .chain(CurveTween(curve: Curves.easeInOut))
                    .animate(animation),
                child: child,
              ),
        ),
      );
    } else {
      setState(() => _selectedIndex = index);
      if (_pageController.hasClients) {
        _pageController.animateToPage(index,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut);
      }
    }
  }

  // ── HEADER ───────────────────────────────────────────────────────────────
  Widget _buildHeader(String firstName, AppColors c) {
    final userState = ref.watch(userNotifierProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.surfaceHigh,
              border: Border.all(color: c.primary.withValues(alpha: 0.4), width: 2),
            ),
            child: ClipOval(
              child: userState.displayPhotoUrl != null
                  ? Image.network(
                      userState.displayPhotoUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          Icon(Icons.person, color: c.primary, size: 26),
                    )
                  : Icon(Icons.person, color: c.primary, size: 26),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.location_on, color: c.onSurfaceVariant, size: 12),
                    const SizedBox(width: 3),
                    Text(
                      'DJIBOUTI',
                      style: TextStyle(
                        color: c.onSurfaceVariant,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  firstName.isEmpty ? tr('welcome') : '${tr('hello')} $firstName',
                  style: GoogleFonts.poppins(
                    color: c.onSurface,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
          ),
          Image.asset(
            'assets/images/velox-logo-sansBG.png',
            height: 90,
            fit: BoxFit.contain,
          ),
        ],
      ),
    );
  }

  // ── TAGLINE ───────────────────────────────────────────────────────────────
  Widget _buildTagline(AppColors c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: Text(
        '✦  ${tr('tagline')}',
        style: GoogleFonts.inter(
          color: c.primary,
          fontSize: 15,
          fontStyle: FontStyle.italic,
          fontWeight: FontWeight.w300,
          letterSpacing: 1.4,
          height: 1.3,
        ),
      ),
    );
  }

  // ── POINTS FIDÉLITÉ (invité) ──────────────────────────────────────────────
  Widget _buildLoyaltyGuestPrompt(AppColors c) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const SignInScreen()),
      ),
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
        decoration: BoxDecoration(
          color: c.surfaceLow,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: c.outlineVariant.withValues(alpha: 0.15)),
        ),
        child: Row(
          children: [
            Icon(Icons.card_giftcard_rounded, color: c.primary, size: 28),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                tr('login_for_loyalty_points'),
                style: TextStyle(color: c.onSurface, fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
            Icon(Icons.chevron_right, color: c.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  // ── POINTS FIDÉLITÉ ───────────────────────────────────────────────────────
  Widget _buildLoyaltyCard(AppColors c) {
    // Solde DISPONIBLE = gagnés − dépensés
    final points = ref.watch(availablePointsProvider);
    final displayPts = _formatNumber(points.toDouble(), isInt: true);

    // Badge basé sur le cumul GAGNÉ (à vie) — ne régresse pas après dépense
    final earned =
        ref.watch(orderStatsProvider).whenOrNull(data: (s) => s.loyaltyPoints) ??
            0;
    String badge;
    if (earned >= 500) {
      badge = 'VIP';
    } else if (earned >= 100) {
      badge = 'GOLD';
    } else {
      badge = 'MEMBER';
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      decoration: BoxDecoration(
        color: c.surfaceLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.outlineVariant.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('loyalty_points').toUpperCase(),
                  style: TextStyle(
                    color: c.onSurfaceVariant,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.8,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      displayPts,
                      style: TextStyle(
                        color: c.onSurface,
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -1,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'pts',
                      style: TextStyle(
                        color: c.onSurfaceVariant,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  tr('one_order_points'),
                  style: TextStyle(
                    color: c.primary.withValues(alpha: 0.7),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: c.primary,
              borderRadius: BorderRadius.circular(50),
            ),
            child: Text(
              badge,
              style: TextStyle(
                color: c.onPrimary,
                fontSize: 13,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── SERVICE CARD ──────────────────────────────────────────────────────────
  Widget _buildServiceCard({
    required String title,
    required String subtitle,
    required String imageAsset,
    required VoidCallback onTap,
    required AppColors c,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: c.outlineVariant.withValues(alpha: 0.12)),
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: c.surfaceHigh,
                borderRadius: BorderRadius.circular(14),
              ),
              padding: const EdgeInsets.all(10),
              child: Image.asset(imageAsset, fit: BoxFit.contain),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: c.onSurface,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: c.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Row(
              children: [
                Icon(Icons.star, color: c.primary, size: 14),
                const SizedBox(width: 3),
                Text(
                  '4.8',
                  style: TextStyle(
                    color: c.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── STATISTIQUES ──────────────────────────────────────────────────────────
  Widget _buildStats(AppColors c) {
    final statsAsync = ref.watch(orderStatsProvider);
    final totalOrders = statsAsync.whenOrNull(data: (s) => s.totalOrders) ?? 0;
    final totalSpent  = statsAsync.whenOrNull(data: (s) => s.totalSpent)  ?? 0.0;
    final isLoading   = statsAsync is AsyncLoading;

    final ridesAsync = ref.watch(completedRidesCountProvider);
    final totalRides = ridesAsync.whenOrNull(data: (r) => r) ?? 0;
    final isRidesLoading = ridesAsync is AsyncLoading;

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 28, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr('statistics').toUpperCase(),
            style: TextStyle(
              color: c.onSurfaceVariant,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.8,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildStatItem(isRidesLoading ? '—' : '$totalRides', tr('rides').toUpperCase(), c),
              _buildVerticalDivider(c),
              _buildStatItem(isLoading ? '—' : '$totalOrders', tr('orders').toUpperCase(), c),
              _buildVerticalDivider(c),
              _buildStatItem(
                isLoading ? '—' : _formatNumber(totalSpent),
                '${tr('expenses').toUpperCase()}\n(FDJ)',
                c,
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatNumber(double value, {bool isInt = false}) {
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(1)}M';
    } else if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(1)}K';
    } else if (isInt) {
      return value.toInt().toString();
    } else {
      return value.toStringAsFixed(0);
    }
  }

  Widget _buildStatItem(String value, String label, AppColors c) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: c.onSurface,
              fontSize: 28,
              fontWeight: FontWeight.bold,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: c.onSurfaceVariant,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerticalDivider(AppColors c) {
    return Container(
      width: 1,
      height: 40,
      color: c.outlineVariant.withValues(alpha: 0.3),
    );
  }

  // ── ACTIONS RAPIDES ───────────────────────────────────────────────────────
  Widget _buildQuickActions(AppColors c) {
    final isAuthenticated = ref.watch(userNotifierProvider).isAuthenticated;
    final actions = [
      {
        'icon': Icons.history_rounded,
        'label': tr('history'),
        'onTap': () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => isAuthenticated
                ? const OrderHistoryScreen()
                : const SignInScreen(),
          ),
        ),
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 16),
          child: Text(
            tr('quick_actions'),
            style: TextStyle(
              color: c.onSurface,
              fontSize: 20,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: actions.map((action) {
              return Expanded(
                child: GestureDetector(
                  onTap: action['onTap'] as VoidCallback,
                  child: Container(
                    margin: EdgeInsets.only(
                      right: action == actions.last ? 0 : 10,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: c.outlineVariant.withValues(alpha: 0.12)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(action['icon'] as IconData,
                            color: c.primary, size: 26),
                        const SizedBox(height: 8),
                        Text(
                          action['label'] as String,
                          style: TextStyle(
                            color: c.onSurface,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  // ── FOOTER ────────────────────────────────────────────────────────────────
  Widget _buildFooter(AppColors c) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Center(
        child: Text(
          'VELOX Corp since 2026',
          style: TextStyle(
            color: c.onSurfaceVariant,
            fontSize: 10,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  // ── HOME PAGE ─────────────────────────────────────────────────────────────
  Widget _buildHomePage(String firstName, AppColors c) {
    final isAuthenticated = ref.watch(userNotifierProvider).isAuthenticated;
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(firstName, c),
          _buildTagline(c),
          isAuthenticated ? _buildLoyaltyCard(c) : _buildLoyaltyGuestPrompt(c),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 14),
            child: Text(
              tr('our_services'),
              style: TextStyle(
                color: c.onSurface,
                fontSize: 20,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.5,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                _buildServiceCard(
                  title: 'VTC DJIB',
                  subtitle: tr('vtc_subtitle'),
                  imageAsset: 'assets/vehicule/taxi-B.png',
                  onTap: _goToTaxi,
                  c: c,
                ),
                _buildServiceCard(
                  title: tr('restaurants_fastfood'),
                  subtitle: tr('food_subtitle'),
                  imageAsset: 'assets/images/fast-food.png',
                  onTap: _goToRestaurants,
                  c: c,
                ),
              ],
            ),
          ),
          _buildStats(c),
          _buildQuickActions(c),
          _buildFooter(c),
        ],
      ),
    );
  }

  // ── BOTTOM NAV ────────────────────────────────────────────────────────────
  Widget _buildBottomNav(AppColors c) {
    return Container(
      height: 72,
      decoration: BoxDecoration(
        color: c.surfaceLow,
        border: Border(
          top: BorderSide(color: c.outlineVariant.withValues(alpha: 0.15)),
        ),
      ),
      child: Row(
        children: [
          _buildNavItem(0, Icons.home_rounded, tr('home_food'), c),
          _buildNavItem(1, Icons.person_rounded, tr('profile'), c),
        ],
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label, AppColors c) {
    final isActive = _selectedIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => _onItemTapped(index),
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 48,
              height: 48,
              decoration: isActive
                  ? BoxDecoration(
                      color: c.primary,
                      shape: BoxShape.circle,
                    )
                  : null,
              child: Icon(
                icon,
                color: isActive ? c.onPrimary : c.onSurfaceVariant,
                size: 24,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = ref.watch(themeNotifierProvider).isDarkMode;
    final c = isDark ? AppColors.dark : AppColors.light;
    final userState = ref.watch(userNotifierProvider);

    if (userState.isLoading) {
      return Scaffold(
        backgroundColor: c.bg,
        body: Center(
          child: CircularProgressIndicator(color: c.primary, strokeWidth: 2),
        ),
      );
    }

    // Invités : pas de compte requis pour parcourir l'app (accueil, VTC,
    // restaurants) — la connexion n'est demandée qu'au moment de réserver/
    // commander (voir order_details_screen.dart et ride_confirmation_screen.dart).
    final firstName = userState.isAuthenticated
        ? userState.displayName.split(' ').first
        : '';

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: PageView(
          controller: _pageController,
          onPageChanged: (i) => setState(() => _selectedIndex = i),
          children: [
            _buildHomePage(firstName, c),
            const ProfileScreen(),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: _buildBottomNav(c),
      ),
    );
  }
}
