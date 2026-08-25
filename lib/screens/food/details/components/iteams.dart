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
    // « Tous » affiché en dernier, mais reste l'onglet actif à l'ouverture :
    // le client voit tout le menu en arrivant (cf. `initialIndex` du TabBar).
    final categories = [...(results[1] as List<String>), 'Tous'];
    final promotions = results[2] as List<Promotion>;

    setState(() {
      _allMenus         = menus;
      _categories       = categories;
      _promotions       = promotions;
      _selectedCategory = categories.isNotEmpty ? categories.last : '';
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

  // Retourne la promo active pour un plat (item puis catégorie), null si aucune.
  Promotion? _promoForItem(MenuItem menu) =>
      PromotionService.resolveForItem(_promotions, menu);

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
          // « Tous » est le dernier onglet mais celui sélectionné à l'ouverture.
          // `_categories` est garanti non vide ici (garde plus haut).
          initialIndex: _categories.length - 1,
          child: TabBar(
            isScrollable: true,
            // La catégorie sélectionnée passe en vert accent (parité Android) :
            // sans `labelColor`, Material retombait sur la couleur de texte
            // normale, rendant la sélection peu visible.
            labelColor: Theme.of(context).colorScheme.primary,
            indicatorColor: Theme.of(context).colorScheme.primary,
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
            final activePromo = _promoForItem(menu);

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
                      promotion:  activePromo,
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
