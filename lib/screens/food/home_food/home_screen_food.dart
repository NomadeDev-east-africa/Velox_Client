import 'dart:async';
import 'dart:math';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nomade_client/components/floating_cart_button.dart';
import 'package:nomade_client/models/menu_item.dart';
import 'package:nomade_client/models/restaurant.dart';
import 'package:nomade_client/screens/food/details/details_screen.dart';
import 'package:nomade_client/screens/food/home_food/category_items_screen.dart';
import 'package:nomade_client/screens/food/featured/featured_screen.dart';
import 'package:nomade_client/screens/food/search/food_search_screen.dart';
import 'package:nomade_client/models/promo_banner.dart';
import 'package:nomade_client/services/menu_service.dart';
import 'package:nomade_client/services/restaurant_service.dart';
import 'package:nomade_client/translations/app_translations.dart';
import 'package:nomade_client/providers/all_providers.dart';
import 'package:nomade_client/theme/app_colors.dart';
import 'package:url_launcher/url_launcher.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = ref.read(restaurantNotifierProvider);
      if (state.restaurants.isEmpty && !state.isLoading) {
        ref.read(restaurantNotifierProvider.notifier).loadAll();
      }
    });
  }

  Future<void> _refresh() async {
    await ref.read(restaurantNotifierProvider.notifier).loadAll();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ref.watch(themeNotifierProvider).isDarkMode;
    final c = isDark ? AppColors.dark : AppColors.light;

    return Scaffold(
      backgroundColor: c.bg,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(64),
        child: Container(
          color: c.surfaceLow,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: SafeArea(
            bottom: false,
            child: SizedBox(
              height: 64,
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Icon(Icons.arrow_back, color: c.primary, size: 22),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'LIVRER À',
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: c.onSurfaceVariant,
                            letterSpacing: 2.0,
                          ),
                        ),
                        Text(
                          'Ville de Djibouti',
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: c.primary,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 20),
                  GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const FoodSearchScreen(),
                      ),
                    ),
                    child: Icon(Icons.search, color: c.primary, size: 22),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: c.primary,
          backgroundColor: c.surfaceLow,
          onRefresh: _refresh,
          child: Stack(
            children: [
              SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 24),
                    _sectionHeader(
                      'PAR CATÉGORIES',
                      c: c,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const FeaturedScreen()),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _CategoryRow(c: c),
                    const SizedBox(height: 28),
                    _PromoBannerSection(c: c),
                    const SizedBox(height: 28),
                    _sectionHeader(
                      'MEILLEURS CHOIX',
                      c: c,
                    ),
                    const SizedBox(height: 16),
                    _PopularList(c: c),
                    const SizedBox(height: 28),
                    _sectionHeader(
                      tr('all_restaurants').toUpperCase(),
                      c: c,
                    ),
                    const SizedBox(height: 16),
                    _AllRestaurantsList(c: c),
                    const SizedBox(height: 100),
                  ],
                ),
              ),
              const Positioned(
                left: 0,
                right: 0,
                bottom: 20,
                child: FloatingCartButton(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// SECTION HEADER
// ════════════════════════════════════════════════════════════

Widget _sectionHeader(String title, {VoidCallback? onTap, required AppColors c}) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: GoogleFonts.spaceGrotesk(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: c.onSurface,
            letterSpacing: -0.5,
          ),
        ),
        if (onTap != null)
          GestureDetector(
            onTap: onTap,
            child: Text(
              'VOIR TOUT',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: c.primary,
                letterSpacing: 2,
              ),
            ),
          ),
      ],
    ),
  );
}

// ════════════════════════════════════════════════════════════
// AUTO-SCROLL CAROUSEL — défilement auto + swipe manuel + dots
// ════════════════════════════════════════════════════════════

class _AutoScrollCarousel extends StatefulWidget {
  final int itemCount;
  final double height;
  final double viewportFraction;
  final IndexedWidgetBuilder itemBuilder;
  final AppColors c;

  const _AutoScrollCarousel({
    required this.itemCount,
    required this.height,
    required this.viewportFraction,
    required this.itemBuilder,
    required this.c,
  });

  @override
  State<_AutoScrollCarousel> createState() => _AutoScrollCarouselState();
}

class _AutoScrollCarouselState extends State<_AutoScrollCarousel> {
  late final PageController _pageController;
  Timer? _autoTimer;
  Timer? _resumeTimer;
  int _currentPage = 0;
  bool _paused = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: widget.viewportFraction);
    _startAutoScroll();
  }

  /// Dernière page réellement atteignable.
  ///
  /// Avec `viewportFraction < 1`, plusieurs éléments tiennent à l'écran : les
  /// derniers ne peuvent pas se caler en tête, faute d'espace pour défiler.
  /// Avec 4 éléments à 0.5, la page 3 n'existe pas — `animateToPage(3)` était
  /// plafonné à 2, le carrousel se figeait là et ne revenait jamais à 0.
  int get _maxPage {
    final visible = 1 / widget.viewportFraction;
    final last = (widget.itemCount - visible).floor();
    return last < 0 ? 0 : last;
  }

  void _startAutoScroll() {
    _autoTimer?.cancel();
    // Rien à faire défiler : tout le contenu tient dans le viewport.
    if (_maxPage <= 0) return;
    _autoTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (_paused || !_pageController.hasClients) return;
      final next = _currentPage >= _maxPage ? 0 : _currentPage + 1;
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    });
  }

  // L'utilisateur a interagi : on met en pause puis on reprend après 5 s.
  void _pauseTemporarily() {
    _paused = true;
    _resumeTimer?.cancel();
    _resumeTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) _paused = false;
    });
  }

  @override
  void didUpdateWidget(covariant _AutoScrollCarousel old) {
    super.didUpdateWidget(old);
    if (old.itemCount != widget.itemCount) {
      if (_currentPage > _maxPage) _currentPage = 0;
      _startAutoScroll();
    }
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _resumeTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    return Column(
      children: [
        SizedBox(
          height: widget.height,
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) {
              // dragDetails != null ⇒ scroll initié par l'utilisateur (pas auto)
              if (n is ScrollStartNotification && n.dragDetails != null) {
                _pauseTemporarily();
              }
              return false;
            },
            child: PageView.builder(
              controller: _pageController,
              padEnds: false,
              onPageChanged: (i) => setState(() => _currentPage = i),
              itemCount: widget.itemCount,
              itemBuilder: widget.itemBuilder,
            ),
          ),
        ),
        // Une pastille par position atteignable, pas par élément : sinon les
        // dernières ne s'allument jamais, et une longue liste produit une
        // rangée de points illisible.
        if (_maxPage > 0) const SizedBox(height: 10),
        if (_maxPage > 0)
        Wrap(
          alignment: WrapAlignment.center,
          children: List.generate(
            _maxPage + 1,
            (i) => AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: _currentPage == i ? 20 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: _currentPage == i
                    ? c.primary
                    : c.onSurfaceVariant.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════
// CATEGORIES — horizontal scroll, square tiles
// ════════════════════════════════════════════════════════════

class _CategoryRow extends StatefulWidget {
  final AppColors c;
  const _CategoryRow({required this.c});

  @override
  State<_CategoryRow> createState() => _CategoryRowState();
}

class _CategoryRowState extends State<_CategoryRow> {
  final MenuService _menuService = MenuService();
  Map<String, MenuItem> _categoryMenus = {};
  List<String> _categoryKeys = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final allMenus = await _menuService.getAllMenus();
      if (!mounted) return;
      if (allMenus.isEmpty) {
        setState(() => _isLoading = false);
        return;
      }
      final Map<String, List<MenuItem>> byCategory = {};
      for (final m in allMenus) {
        byCategory.putIfAbsent(m.category, () => []).add(m);
      }
      final rng = Random();
      final Map<String, MenuItem> picked = {};
      for (final entry in byCategory.entries) {
        final withImg = entry.value
            .where((m) => m.imageUrl != null && m.imageUrl!.isNotEmpty)
            .toList();
        if (withImg.isNotEmpty) {
          picked[entry.key] = withImg[rng.nextInt(withImg.length)];
        }
      }
      if (!mounted) return;
      setState(() {
        _categoryMenus = picked;
        _categoryKeys = picked.keys.toList();
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;

    if (_isLoading) {
      return SizedBox(
        height: 128,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: 5,
          itemBuilder: (_, _) => Container(
            width: 128,
            margin: const EdgeInsets.only(right: 12),
            color: c.surfaceLow,
          ),
        ),
      );
    }

    if (_categoryMenus.isEmpty) return const SizedBox.shrink();

    return _AutoScrollCarousel(
      itemCount: _categoryKeys.length,
      height: 128,
      viewportFraction: 0.42,
      c: c,
      itemBuilder: (context, i) {
        final cat = _categoryKeys[i];
        final menu = _categoryMenus[cat]!;
        final imageUrl = menu.imageUrl;
        final hasImage = imageUrl != null && imageUrl.isNotEmpty;

        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => CategoryItemsScreen(category: cat)),
            );
          },
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 6),
            color: c.surfaceLow,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (hasImage)
                  CachedNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.cover,
                    memCacheWidth:
                        (160 * MediaQuery.of(context).devicePixelRatio)
                            .toInt(),
                    placeholder: (_, _) => Container(color: c.surfaceLow),
                    errorWidget: (_, _, _) => Container(
                      color: c.surfaceHigh,
                      child: Icon(Icons.fastfood,
                          size: 32, color: c.onSurfaceVariant),
                    ),
                  )
                else
                  Container(
                    color: c.surfaceHigh,
                    child: Icon(Icons.fastfood,
                        size: 32, color: c.onSurfaceVariant),
                  ),
                // Gradient overlay — toujours sombre pour lisibilité du texte
                const Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Color(0xCC000000)],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 8,
                  bottom: 8,
                  right: 8,
                  child: Text(
                    cat.toUpperCase(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: 1,
                      height: 1.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════
// PROMO BANNERS — pilotées par l'admin (collection `banners`)
// ════════════════════════════════════════════════════════════

/// Hauteur commune à toutes les bannières (le carrousel impose une hauteur
/// fixe, et le texte s'adapte à l'intérieur plutôt que l'inverse).
const double _kBannerHeight = 160;

/// Carrousel de bannières lu en temps réel depuis Firestore.
///
/// Pendant le chargement, en erreur (invité non connecté, réseau) ou si l'admin
/// n'a publié aucune bannière active, on affiche la bannière par défaut plutôt
/// qu'un trou dans l'accueil.
class _PromoBannerSection extends ConsumerWidget {
  final AppColors c;
  const _PromoBannerSection({required this.c});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final banners = ref.watch(bannersProvider);

    final list = banners.asData?.value ?? const <PromoBanner>[];
    if (list.isEmpty) return _DefaultPromoBanner(c: c);

    if (list.length == 1) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: _BannerCard(banner: list.first, c: c),
      );
    }

    return _AutoScrollCarousel(
      itemCount: list.length,
      height: _kBannerHeight,
      viewportFraction: 1,
      c: c,
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: _BannerCard(banner: list[i], c: c),
      ),
    );
  }
}

/// Bannière de repli, affichée quand aucune bannière admin n'est disponible.
class _DefaultPromoBanner extends StatelessWidget {
  final AppColors c;
  const _DefaultPromoBanner({required this.c});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SizedBox(
        width: double.infinity,
        height: _kBannerHeight,
        child: Container(
          color: c.primary,
          padding: const EdgeInsets.all(24),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                right: -12,
                bottom: -12,
                child: Opacity(
                  opacity: 0.15,
                  child: Icon(Icons.track_changes,
                      size: 120, color: c.onPrimary),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '⏱️ Une appli faite pour vous',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: c.onPrimary,
                      height: 1.1,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Zéro frais caché. Zéro attente. Juste Excellent.',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: c.onPrimary.withValues(alpha: 0.8),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Une bannière admin : rendu texte (fond coloré plein) ou image.
class _BannerCard extends StatelessWidget {
  final PromoBanner banner;
  final AppColors c;
  const _BannerCard({required this.banner, required this.c});

  @override
  Widget build(BuildContext context) {
    final card = ClipRRect(
      // Coins arrondis comme les autres cartes de l'accueil : la bannière était
      // le seul bloc à angles vifs.
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: double.infinity,
        height: _kBannerHeight,
        child: banner.type == BannerType.image ? _buildImage() : _buildText(),
      ),
    );

    if (!banner.isTappable) return card;

    return GestureDetector(
      onTap: () => _handleTap(context),
      child: card,
    );
  }

  Widget _buildImage() {
    return CachedNetworkImage(
      imageUrl: banner.imageUrl,
      // fitWidth : l'image occupe toute la largeur, un léger rognage vertical
      // est accepté. `cover` rognait trop, `contain` laissait des bandes vides.
      fit: BoxFit.fitWidth,
      width: double.infinity,
      placeholder: (_, _) => Container(color: c.surfaceLow),
      errorWidget: (_, _, _) => Container(
        color: c.surfaceLow,
        alignment: Alignment.center,
        child: Icon(Icons.image_not_supported_outlined,
            color: c.onSurfaceVariant, size: 32),
      ),
    );
  }

  Widget _buildText() {
    return Container(
      color: c.primary,
      padding: const EdgeInsets.all(24),
      // stretch : le texte dispose de toute la largeur de la carte, pas
      // seulement de la largeur de ses propres glyphes.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (banner.title.trim().isNotEmpty)
            _ShrinkText(
              text: banner.title,
              maxLines: 2,
              minFontSize: 14,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: c.onPrimary,
                height: 1.1,
                letterSpacing: -0.5,
              ),
            ),
          if (banner.title.trim().isNotEmpty &&
              banner.subtitle.trim().isNotEmpty)
            const SizedBox(height: 10),
          if (banner.subtitle.trim().isNotEmpty)
            _ShrinkText(
              text: banner.subtitle,
              maxLines: 2,
              minFontSize: 10,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: c.onPrimary.withValues(alpha: 0.8),
                height: 1.4,
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _handleTap(BuildContext context) async {
    final value = banner.actionValue!.trim();

    switch (banner.actionType) {
      case BannerActionType.whatsapp:
        await _openExternal(context, 'https://wa.me/$value');
      case BannerActionType.url:
        await _openExternal(context, value);
      case BannerActionType.category:
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CategoryItemsScreen(category: value),
          ),
        );
      case BannerActionType.restaurant:
        final restaurant = await RestaurantService().getRestaurantById(value);
        if (!context.mounted) return;
        if (restaurant == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Restaurant introuvable')),
          );
          return;
        }
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DetailsScreen(restaurant: restaurant),
          ),
        );
      case BannerActionType.none:
        break;
    }
  }

  /// launchUrl peut lever (PlatformException) si aucune app ne gère le lien —
  /// WhatsApp non installé, par exemple.
  Future<void> _openExternal(BuildContext context, String rawUrl) async {
    final uri = Uri.tryParse(rawUrl);
    bool launched = false;
    if (uri != null) {
      try {
        launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        launched = false;
      }
    }
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible d\'ouvrir ce lien')),
      );
    }
  }
}

/// Texte qui réduit sa police jusqu'à [minFontSize] pour tenir sur [maxLines],
/// et ne coupe en ellipsis qu'en tout dernier recours.
///
/// Le texte des bannières est saisi librement par l'admin : sa longueur est
/// inconnue au moment du build, d'où l'ajustement à la mise en page.
class _ShrinkText extends StatelessWidget {
  const _ShrinkText({
    required this.text,
    required this.style,
    required this.maxLines,
    required this.minFontSize,
  });

  final String text;
  final TextStyle style;
  final int maxLines;
  final double minFontSize;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final maxFontSize = style.fontSize ?? 14;
        final textScaler = MediaQuery.textScalerOf(context);
        final direction = Directionality.of(context);

        var fitting = minFontSize;
        for (var size = maxFontSize; size >= minFontSize; size -= 0.5) {
          final painter = TextPainter(
            text: TextSpan(text: text, style: style.copyWith(fontSize: size)),
            maxLines: maxLines,
            textDirection: direction,
            textScaler: textScaler,
          )..layout(maxWidth: maxWidth);
          if (!painter.didExceedMaxLines) {
            fitting = size;
            break;
          }
        }

        return Text(
          text,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          style: style.copyWith(fontSize: fitting),
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════
// POPULAR LIST — horizontal scroll
// ════════════════════════════════════════════════════════════

class _PopularList extends ConsumerWidget {
  final AppColors c;
  const _PopularList({required this.c});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final popular = ref.watch(popularRestaurantsProvider);
    final loading = ref.watch(restaurantsLoadingProvider);

    if (loading && popular.isEmpty) {
      return SizedBox(
        height: 210,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: 3,
          itemBuilder: (_, _) => Container(
            width: 170,
            margin: const EdgeInsets.only(right: 14),
            decoration: BoxDecoration(
              color: c.surfaceLow,
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      );
    }

    if (popular.isEmpty) return const SizedBox.shrink();

    return _AutoScrollCarousel(
      itemCount: popular.length,
      height: 210,
      viewportFraction: 0.5,
      c: c,
      itemBuilder: (context, i) =>
          _PopularCard(restaurant: popular[i], c: c),
    );
  }
}

// ════════════════════════════════════════════════════════════
// POPULAR CARD — compact horizontal card
// ════════════════════════════════════════════════════════════

class _PopularCard extends ConsumerWidget {
  final Restaurant restaurant;
  final AppColors c;
  const _PopularCard({required this.restaurant, required this.c});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFav = ref.watch(
      favoritesNotifierProvider.select((ids) => ids.contains(restaurant.id)),
    );
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => DetailsScreen(restaurant: restaurant)),
      ),
      child: Container(
        width: 170,
        margin: const EdgeInsets.only(right: 14),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.outlineVariant.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Image ────────────────────────────────────────
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: Stack(
                children: [
                  CachedNetworkImage(
                    imageUrl: restaurant.imageUrl,
                    width: 170,
                    height: 115,
                    fit: BoxFit.cover,
                    memCacheWidth: (170 * 2).toInt(),
                    placeholder: (_, _) =>
                        Container(width: 170, height: 115, color: c.surfaceHigh),
                    errorWidget: (_, _, _) => Container(
                      width: 170,
                      height: 115,
                      color: c.surfaceHigh,
                      child: Icon(Icons.restaurant, color: c.onSurfaceVariant, size: 32),
                    ),
                  ),
                  // Favori
                  Positioned(
                    top: 7,
                    right: 7,
                    child: GestureDetector(
                      onTap: () => ref
                          .read(favoritesNotifierProvider.notifier)
                          .toggleFavorite(restaurant.id),
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: c.surfaceTop.withValues(alpha: 0.85),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isFav ? Icons.favorite : Icons.favorite_border,
                          color: isFav ? Colors.redAccent : c.onSurfaceVariant,
                          size: 15,
                        ),
                      ),
                    ),
                  ),
                  // Badge ouvert/fermé
                  Positioned(
                    bottom: 7,
                    left: 7,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: restaurant.isOpen
                            ? c.primary
                            : c.surfaceTop.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        restaurant.isOpen ? 'OUVERT' : 'FERMÉ',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: restaurant.isOpen ? c.onPrimary : c.onSurfaceVariant,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // ── Info ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    restaurant.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: c.onSurface,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Icon(Icons.star, color: c.primary, size: 12),
                      const SizedBox(width: 3),
                      Text(
                        restaurant.rating.toStringAsFixed(1),
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: c.onSurface,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.schedule_outlined, size: 11, color: c.onSurfaceVariant),
                      const SizedBox(width: 3),
                      Text(
                        '35 min',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 10,
                          color: c.onSurfaceVariant,
                          letterSpacing: 0.3,
                        ),
                      ),
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
}

// ════════════════════════════════════════════════════════════
// ALL RESTAURANTS LIST
// ════════════════════════════════════════════════════════════

class _AllRestaurantsList extends ConsumerWidget {
  final AppColors c;
  const _AllRestaurantsList({required this.c});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final restaurants = ref.watch(allRestaurantsProvider);
    final loading = ref.watch(restaurantsLoadingProvider);

    if (loading && restaurants.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(color: c.primary, strokeWidth: 2),
          ),
        ),
      );
    }

    if (restaurants.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Text(
          'Aucun restaurant disponible',
          style: GoogleFonts.inter(color: c.onSurfaceVariant, fontSize: 14),
        ),
      );
    }

    return Column(
      children: restaurants
          .map((r) => RepaintBoundary(child: _RestaurantCard(restaurant: r, c: c)))
          .toList(),
    );
  }
}

// ════════════════════════════════════════════════════════════
// RESTAURANT CARD
// ════════════════════════════════════════════════════════════

class _RestaurantCard extends ConsumerWidget {
  final Restaurant restaurant;
  final AppColors c;

  const _RestaurantCard({required this.restaurant, required this.c});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFav = ref.watch(
      favoritesNotifierProvider.select((ids) => ids.contains(restaurant.id)),
    );
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => DetailsScreen(restaurant: restaurant)),
      ),
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        decoration: BoxDecoration(
          color: c.surfaceLow,
          border: Border(
            left: BorderSide(
              color: restaurant.isOpen ? c.primary : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: restaurant.imageUrl,
                    fit: BoxFit.cover,
                    memCacheWidth: MediaQuery.of(context).size.width.toInt(),
                    placeholder: (_, _) => Container(color: c.surfaceHigh),
                    errorWidget: (_, _, _) => Container(
                      color: c.surfaceHigh,
                      child: Icon(Icons.restaurant,
                          size: 48, color: c.onSurfaceVariant),
                    ),
                  ),
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Container(
                      color: c.surfaceTop.withValues(alpha: 0.8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.star, color: c.primary, size: 12),
                          const SizedBox(width: 4),
                          Text(
                            restaurant.rating.toStringAsFixed(1),
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: c.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: GestureDetector(
                      onTap: () => ref
                          .read(favoritesNotifierProvider.notifier)
                          .toggleFavorite(restaurant.id),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: c.surfaceTop.withValues(alpha: 0.85),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isFav ? Icons.favorite : Icons.favorite_border,
                          color: isFav ? Colors.redAccent : c.onSurfaceVariant,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          restaurant.name.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: c.onSurface,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.schedule_outlined,
                              color: c.onSurfaceVariant, size: 13),
                          const SizedBox(width: 4),
                          Text(
                            '35 MIN',
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: c.onSurfaceVariant,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      _chip(
                        restaurant.isOpen ? 'OUVERT' : 'FERMÉ',
                        active: restaurant.isOpen,
                        c: c,
                      ),
                      _chip('${restaurant.totalOrders} CMDS', c: c),
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

  Widget _chip(String label, {bool active = false, required AppColors c}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      color: active ? c.primary.withValues(alpha: 0.1) : c.surfaceHigh,
      child: Text(
        label,
        style: GoogleFonts.spaceGrotesk(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: active ? c.primary : c.onSurfaceVariant,
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}
