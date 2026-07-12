import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nomade_client/models/menu_item.dart';
import 'package:nomade_client/models/restaurant.dart';
import 'package:nomade_client/providers/all_providers.dart';
import 'package:nomade_client/screens/food/details/details_screen.dart';
import 'package:nomade_client/screens/food/home_food/category_items_screen.dart';
import 'package:nomade_client/services/menu_service.dart';
import 'package:nomade_client/services/restaurant_service.dart';
import 'package:nomade_client/theme/app_colors.dart';

class FoodSearchScreen extends ConsumerStatefulWidget {
  const FoodSearchScreen({super.key});

  @override
  ConsumerState<FoodSearchScreen> createState() => _FoodSearchScreenState();
}

class _FoodSearchScreenState extends ConsumerState<FoodSearchScreen> {
  final _controller = TextEditingController();
  final _menuService = MenuService();
  final _restaurantService = RestaurantService();

  Timer? _debounce;

  // Données chargées une seule fois, filtrées en mémoire ensuite.
  List<Restaurant> _allRestaurants = [];
  List<MenuItem> _allMenus = [];
  Map<String, Restaurant> _restaurantsById = {};

  List<Restaurant> _restaurantResults = [];
  List<MenuItem> _dishResults = [];
  List<String> _categoryResults = [];

  bool _isLoading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final results = await Future.wait([
      _restaurantService.getRestaurants(),
      _menuService.getAllMenus(),
    ]);
    if (!mounted) return;
    final restaurants = results[0] as List<Restaurant>;
    final menus = results[1] as List<MenuItem>;
    setState(() {
      _allRestaurants = restaurants;
      _allMenus = menus;
      _restaurantsById = {for (final r in restaurants) r.id: r};
      _isLoading = false;
    });
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _runSearch(value);
    });
  }

  void _runSearch(String value) {
    final q = value.trim().toLowerCase();
    if (!mounted) return;
    if (q.isEmpty) {
      setState(() {
        _query = '';
        _restaurantResults = [];
        _dishResults = [];
        _categoryResults = [];
      });
      return;
    }
    setState(() {
      _query = q;
      _restaurantResults = _allRestaurants
          .where((r) => r.name.toLowerCase().contains(q))
          .toList();
      _dishResults = _allMenus
          .where((m) =>
              _restaurantsById.containsKey(m.restaurantId) &&
              (m.name.toLowerCase().contains(q) ||
                  m.description.toLowerCase().contains(q) ||
                  m.category.toLowerCase().contains(q)))
          .toList();
      _categoryResults = _allMenus
          .map((m) => m.category)
          .toSet()
          .where((cat) => cat.toLowerCase().contains(q))
          .toList();
    });
  }

  void _openCategory(String category) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CategoryItemsScreen(category: category)),
    );
  }

  void _openRestaurant(Restaurant restaurant) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DetailsScreen(restaurant: restaurant)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ref.watch(themeNotifierProvider).isDarkMode;
    final c = isDark ? AppColors.dark : AppColors.light;

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        elevation: 0,
        foregroundColor: c.onSurface,
        title: Text(
          'Rechercher',
          style: GoogleFonts.spaceGrotesk(
            color: c.onSurface,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: TextField(
                controller: _controller,
                autofocus: true,
                onChanged: _onChanged,
                textInputAction: TextInputAction.search,
                style: TextStyle(color: c.onSurface),
                decoration: InputDecoration(
                  hintText: 'Restaurant ou plat...',
                  hintStyle: TextStyle(color: c.onSurfaceVariant),
                  prefixIcon: Icon(Icons.search, color: c.onSurfaceVariant),
                  suffixIcon: _controller.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.clear, color: c.onSurfaceVariant),
                          onPressed: () {
                            _controller.clear();
                            _runSearch('');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: c.surfaceLow,
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Expanded(child: _buildBody(c)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(AppColors c) {
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(color: c.primary, strokeWidth: 2),
      );
    }

    if (_query.isEmpty) {
      return _placeholder(
        c,
        icon: Icons.search,
        message: 'Cherchez un restaurant ou un plat',
      );
    }

    if (_restaurantResults.isEmpty && _dishResults.isEmpty && _categoryResults.isEmpty) {
      return _placeholder(
        c,
        icon: Icons.search_off,
        message: 'Aucun résultat pour "$_query"',
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        if (_categoryResults.isNotEmpty) ...[
          _sectionTitle(c, 'Catégories', _categoryResults.length),
          const SizedBox(height: 8),
          ..._categoryResults.map((cat) => _categoryTile(c, cat)),
          const SizedBox(height: 16),
        ],
        if (_restaurantResults.isNotEmpty) ...[
          _sectionTitle(c, 'Restaurants', _restaurantResults.length),
          const SizedBox(height: 8),
          ..._restaurantResults.map((r) => _restaurantTile(c, r)),
          const SizedBox(height: 16),
        ],
        if (_dishResults.isNotEmpty) ...[
          _sectionTitle(c, 'Plats', _dishResults.length),
          const SizedBox(height: 8),
          ..._dishResults.map((m) => _dishTile(c, m)),
        ],
      ],
    );
  }

  Widget _placeholder(AppColors c,
      {required IconData icon, required String message}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 56, color: c.onSurfaceVariant.withValues(alpha: 0.5)),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: c.onSurfaceVariant, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(AppColors c, String title, int count) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        '${title.toUpperCase()} ($count)',
        style: GoogleFonts.spaceGrotesk(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: c.onSurfaceVariant,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _categoryTile(AppColors c, String category) {
    return Card(
      color: c.surfaceLow,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        onTap: () => _openCategory(category),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 52,
            height: 52,
            color: c.surfaceHigh,
            child: Icon(Icons.category, color: c.onSurfaceVariant, size: 24),
          ),
        ),
        title: Text(
          category,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.spaceGrotesk(
            fontWeight: FontWeight.w700,
            color: c.onSurface,
          ),
        ),
        trailing: Icon(Icons.chevron_right, color: c.onSurfaceVariant),
      ),
    );
  }

  Widget _restaurantTile(AppColors c, Restaurant r) {
    return Card(
      color: c.surfaceLow,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        onTap: () => _openRestaurant(r),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: _thumb(c, r.imageUrl, Icons.restaurant),
        ),
        title: Text(
          r.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.spaceGrotesk(
            fontWeight: FontWeight.w700,
            color: c.onSurface,
          ),
        ),
        subtitle: Row(
          children: [
            Icon(Icons.star, size: 13, color: c.primary),
            const SizedBox(width: 3),
            Text(
              r.rating.toStringAsFixed(1),
              style: TextStyle(fontSize: 12, color: c.onSurfaceVariant),
            ),
          ],
        ),
        trailing: Consumer(
          builder: (context, ref, _) {
            final isFav = ref.watch(
              favoritesNotifierProvider.select((ids) => ids.contains(r.id)),
            );
            return IconButton(
              onPressed: () =>
                  ref.read(favoritesNotifierProvider.notifier).toggleFavorite(r.id),
              icon: Icon(
                isFav ? Icons.favorite : Icons.favorite_border,
                color: isFav ? Colors.redAccent : c.onSurfaceVariant,
                size: 20,
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _dishTile(AppColors c, MenuItem m) {
    final restaurant = _restaurantsById[m.restaurantId];
    return Card(
      color: c.surfaceLow,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        onTap: restaurant != null ? () => _openRestaurant(restaurant) : null,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: _thumb(c, m.imageUrl, Icons.fastfood),
        ),
        title: Text(
          m.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.spaceGrotesk(
            fontWeight: FontWeight.w700,
            color: c.onSurface,
          ),
        ),
        subtitle: Text(
          restaurant?.name ?? m.category,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, color: c.onSurfaceVariant),
        ),
        trailing: Text(
          '${m.price.toStringAsFixed(0)} FDJ',
          style: GoogleFonts.spaceGrotesk(
            fontWeight: FontWeight.w800,
            color: c.primary,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _thumb(AppColors c, String? url, IconData fallback) {
    const size = 52.0;
    if (url == null || url.isEmpty) {
      return Container(
        width: size,
        height: size,
        color: c.surfaceHigh,
        child: Icon(fallback, color: c.onSurfaceVariant, size: 24),
      );
    }
    return CachedNetworkImage(
      imageUrl: url,
      width: size,
      height: size,
      fit: BoxFit.cover,
      memCacheWidth: (size * 2).toInt(),
      placeholder: (_, _) =>
          Container(width: size, height: size, color: c.surfaceHigh),
      errorWidget: (_, _, _) => Container(
        width: size,
        height: size,
        color: c.surfaceHigh,
        child: Icon(fallback, color: c.onSurfaceVariant, size: 24),
      ),
    );
  }
}
