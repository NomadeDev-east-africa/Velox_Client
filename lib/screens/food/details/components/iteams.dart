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
  /// Index de la catégorie active — la sélection se fait par position et non
  /// par libellé, deux entrées pouvant porter le même nom.
  int             _selectedIndex = -1;
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
      _selectedIndex    = categories.length - 1;
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
        // ── Catégories ─────────────────────────────────────────────
        // Rangée défilante maison plutôt qu'un TabBar : un TabBar scrollable
        // se recale toujours sur l'onglet actif, or « Tous » est sélectionné
        // par défaut ET affiché en dernier — la barre s'ouvrait donc calée à
        // droite, masquant les premières catégories. Ici la position de départ
        // reste à gauche, indépendamment de la sélection.
        // Hauteur libre plutôt que fixe : avec les réglages d'accessibilité
        // iOS (« Texte plus grand »), une hauteur figée découpait les noms de
        // catégorie et déclenchait un débordement.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: defaultPadding),
          child: Row(
            children: List.generate(_categories.length * 2 - 1, (slot) {
              if (slot.isOdd) return const SizedBox(width: 20);
              final i = slot ~/ 2;
              final category = _categories[i];
              // Sélection par index : deux catégories homonymes (un plat rangé
              // dans une catégorie littéralement nommée « Tous ») seraient
              // sinon surlignées ensemble.
              final isSelected = i == _selectedIndex;
              final hasPromo = _categoryHasPromo(category);
              final scheme = Theme.of(context).colorScheme;

              return Semantics(
                button: true,
                selected: isSelected,
                child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() {
                  _selectedIndex = i;
                  _selectedCategory = category;
                }),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Padding(
                          padding: EdgeInsets.only(right: hasPromo ? 8 : 0),
                          child: Text(
                            category,
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(
                                  color: isSelected
                                      ? scheme.primary
                                      : scheme.onSurfaceVariant,
                                ),
                          ),
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
                    const SizedBox(height: 4),
                    // Soulignement de l'onglet actif, équivalent de l'indicator
                    // du TabBar remplacé.
                    Container(
                      height: 2,
                      width: 28,
                      color: isSelected ? scheme.primary : Colors.transparent,
                    ),
                  ],
                ),
                ),
              );
            }),
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
