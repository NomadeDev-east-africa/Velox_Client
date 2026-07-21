import 'package:flutter/material.dart';
import '../../../components/cards/item_card.dart';
import '../../../constants.dart';
import '../../../models/menu_item.dart';
import '../../../models/promotion.dart';
import '../../../models/restaurant.dart';
import '../../../services/menu_service.dart';
import '../../../services/promotion_service.dart';
import '../../../services/restaurant_service.dart';
import '../addToOrder/add_to_order_screen.dart';

/// Liste les plats d'une catégorie donnée, tous restaurants confondus.
class CategoryItemsScreen extends StatefulWidget {
  final String category;

  const CategoryItemsScreen({super.key, required this.category});

  @override
  State<CategoryItemsScreen> createState() => _CategoryItemsScreenState();
}

class _CategoryItemsScreenState extends State<CategoryItemsScreen> {
  bool _isLoading = true;
  List<MenuItem> _items = [];
  Map<String, Restaurant?> _restaurantsById = {};
  // Promos actives regroupées par restaurant (les plats affichés viennent de
  // plusieurs restaurants).
  Map<String, List<Promotion>> _promotionsByRestaurant = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final allMenus = await MenuService().getAllMenus();
    final items = allMenus.where((m) => m.category == widget.category).toList();

    final uniqueIds = items.map((m) => m.restaurantId).toSet().toList();
    final restaurantService = RestaurantService();
    final promotionService = PromotionService();
    final fetched = await Future.wait(
      uniqueIds.map((id) => restaurantService.getRestaurantById(id)),
    );
    final promos = await Future.wait(
      uniqueIds.map((id) =>
          promotionService.getActivePromotionsForRestaurant(id)),
    );
    final byId = {
      for (var i = 0; i < uniqueIds.length; i++) uniqueIds[i]: fetched[i],
    };
    final promosById = {
      for (var i = 0; i < uniqueIds.length; i++) uniqueIds[i]: promos[i],
    };

    if (!mounted) return;
    setState(() {
      _items = items;
      _restaurantsById = byId;
      _promotionsByRestaurant = promosById;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.category)),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _items.isEmpty
                ? const Center(child: Text('Aucun plat disponible'))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: defaultPadding / 2),
                    itemCount: _items.length,
                    itemBuilder: (context, index) {
                      final menu = _items[index];
                      final restaurant = _restaurantsById[menu.restaurantId];
                      final promo = PromotionService.resolveForItem(
                        _promotionsByRestaurant[menu.restaurantId] ?? const [],
                        menu,
                      );

                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: defaultPadding, vertical: defaultPadding / 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (restaurant != null)
                              Padding(
                                padding: const EdgeInsets.only(left: 5, bottom: 4),
                                child: Text(
                                  restaurant.name,
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelMedium!
                                      .copyWith(color: primaryColor, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ItemCard(
                              menuItem: menu,
                              promotion: promo,
                              press: restaurant == null
                                  ? () {}
                                  : () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => AddToOrderScreen(
                                            menuItem: menu,
                                            restaurant: restaurant,
                                            promotion: promo,
                                          ),
                                        ),
                                      ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
