import 'package:flutter/material.dart';
import '../../../../components/cards/item_card.dart';
import '../../../../constants.dart';
import '../../addToOrder/add_to_order_screen.dart';
import '../../../../services/menu_service.dart';
import '../../../../services/promotion_service.dart';
import '../../../../models/menu_item.dart';
import '../../../../models/promotion.dart';
import '../../../../models/restaurant.dart';

class Items extends StatefulWidget {
  final String restaurantId;
  final Restaurant restaurant;

  const Items({
    super.key,
    required this.restaurantId,
    required this.restaurant,
  });

  @override
  State<Items> createState() => _ItemsState();
}

class _ItemsState extends State<Items> {
  List<MenuItem>  _allMenus    = [];
  List<String>    _categories  = [];
  List<Promotion> _promotions  = [];
  String          _selectedCategory = '';
  bool            _isLoading   = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final service = MenuService();
    final results = await Future.wait([
      service.getMenusByRestaurant(widget.restaurantId),
      service.getCategories(widget.restaurantId),
      PromotionService().getActivePromotionsForRestaurant(widget.restaurantId),
    ]);

    if (!mounted) return;

    final menus      = results[0] as List<MenuItem>;
    final categories = ['Tous', ...(results[1] as List<String>)];
    final promotions = results[2] as List<Promotion>;

    setState(() {
      _allMenus         = menus;
      _categories       = categories;
      _promotions       = promotions;
      _selectedCategory = categories.isNotEmpty ? categories[0] : '';
      _isLoading        = false;
    });
  }

  List<MenuItem> get _filteredMenus {
    if (_selectedCategory.isEmpty || _selectedCategory == 'Tous') {
      return _allMenus;
    }
    return _allMenus
        .where((m) => m.category == _selectedCategory)
        .toList();
  }

  // Retourne la promo active pour un plat (null si aucune)
  Promotion? _promoForItem(MenuItem menu) {
    for (final p in _promotions) {
      if (p.matchesItem(menu.id, menu.name)) return p;
    }
    return null;
  }

  // La catégorie a-t-elle une promo de type "category" active ?
  bool _categoryHasPromo(String category) =>
      _promotions.any((p) => p.matchesCategory(category));

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.all(defaultPadding),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_categories.isEmpty || _allMenus.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(defaultPadding),
        child: Center(child: Text('Aucun menu disponible')),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Onglets catégories ─────────────────────────────────────
        DefaultTabController(
          length: _categories.length,
          child: TabBar(
            isScrollable: true,
            unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
            labelStyle: Theme.of(context).textTheme.titleLarge,
            onTap: (i) => setState(() => _selectedCategory = _categories[i]),
            tabs: _categories.map((category) {
              final hasPromo = _categoryHasPromo(category);
              return Tab(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Padding(
                      padding: EdgeInsets.only(right: hasPromo ? 8 : 0),
                      child: Text(category),
                    ),
                    if (hasPromo)
                      Positioned(
                        top: -2,
                        right: 0,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Color(0xFF6EFF6E),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),

        const SizedBox(height: defaultPadding / 2),

        // ── Liste des plats filtrés ────────────────────────────────
        ..._filteredMenus.map(
          (menu) {
            // Promo directe sur le plat OU promo sur sa catégorie
            final itemPromo  = _promoForItem(menu);
            final catPromo   = _promotions
                .where((p) => p.matchesCategory(menu.category))
                .firstOrNull;
            final activePromo = itemPromo ?? catPromo;

            return Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: defaultPadding, vertical: defaultPadding / 2),
              child: ItemCard(
                menuItem:  menu,
                promotion: activePromo,
                press: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AddToOrderScreen(
                      menuItem:   menu,
                      restaurant: widget.restaurant,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
