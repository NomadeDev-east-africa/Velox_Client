import 'package:flutter/material.dart';

import '../../../../constants.dart';
import 'featured_item_card.dart';
import '../../../../translations/app_translations.dart';
import '../../../../services/menu_service.dart';
import '../../../../services/promotion_service.dart';
import '../../../../models/menu_item.dart';
import '../../../../models/promotion.dart';
import '../../../../models/restaurant.dart';
import '../../addToOrder/add_to_order_screen.dart';

class FeaturedItems extends StatefulWidget {
  final String restaurantId;
  final Restaurant restaurant;  // ✅ AJOUT: Recevoir le restaurant

  const FeaturedItems({
    super.key,
    required this.restaurantId,
    required this.restaurant,  // ✅ AJOUT
  });

  @override
  State<FeaturedItems> createState() => _FeaturedItemsState();
}

class _FeaturedItemsState extends State<FeaturedItems> {
  List<MenuItem> _featuredMenus = [];
  List<Promotion> _promotions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFeaturedMenus();
  }

  Future<void> _loadFeaturedMenus() async {
    final results = await Future.wait([
      MenuService().getFeaturedMenus(widget.restaurantId, limit: 3),
      PromotionService().getActivePromotionsForRestaurant(widget.restaurantId),
    ]);

    if (mounted) {
      setState(() {
        _featuredMenus = results[0] as List<MenuItem>;
        _promotions    = results[1] as List<Promotion>;
        _isLoading     = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.all(defaultPadding),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_featuredMenus.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: defaultPadding),
          child: Text(
            tr('featured_items'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        const SizedBox(height: defaultPadding / 2),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              ...List.generate(
                _featuredMenus.length,
                (index) {
                  final menu = _featuredMenus[index];
                  final promo =
                      PromotionService.resolveForItem(_promotions, menu);
                  return Padding(
                    padding: const EdgeInsets.only(left: defaultPadding),
                    child: FeaturedItemCard(
                      menuItem: menu,
                      promotion: promo,
                      press: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => AddToOrderScreen(
                              menuItem: menu,
                              restaurant: widget.restaurant,
                              promotion: promo,
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
              const SizedBox(width: defaultPadding),
            ],
          ),
        ),
      ],
    );
  }
}
