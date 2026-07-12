import 'package:flutter/material.dart';
import '../../../components/cards/item_card.dart';
import '../../../constants.dart';
import '../../../models/menu_item.dart';
import '../../../models/restaurant.dart';
import '../../../services/menu_service.dart';
import '../addToOrder/add_to_order_screen.dart';
import '../search/search_screen.dart';

/// Recherche parmi les plats du restaurant courant (et non tous les restaurants).
class RestaurantMenuSearchScreen extends StatefulWidget {
  final Restaurant restaurant;

  const RestaurantMenuSearchScreen({super.key, required this.restaurant});

  @override
  State<RestaurantMenuSearchScreen> createState() => _RestaurantMenuSearchScreenState();
}

class _RestaurantMenuSearchScreenState extends State<RestaurantMenuSearchScreen> {
  final _searchController = TextEditingController();
  bool _isLoading = true;
  List<MenuItem> _allMenus = [];
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final menus = await MenuService().getMenusByRestaurant(widget.restaurant.id);
    if (!mounted) return;
    setState(() {
      _allMenus = menus;
      _isLoading = false;
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<MenuItem> get _filteredMenus {
    if (_query.isEmpty) return _allMenus;
    final lowerQuery = _query.toLowerCase();
    return _allMenus
        .where((m) =>
            m.name.toLowerCase().contains(lowerQuery) ||
            m.category.toLowerCase().contains(lowerQuery))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.restaurant.name),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: defaultPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: defaultPadding),
              SearchForm(
                controller: _searchController,
                hintText: "Rechercher un plat...",
                onChanged: (value) => setState(() => _query = value),
                onSubmitted: (value) => setState(() => _query = value),
              ),
              const SizedBox(height: defaultPadding),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _filteredMenus.isEmpty
                        ? Center(
                            child: Text(
                              _query.isEmpty ? 'Aucun plat disponible' : 'Aucun résultat trouvé',
                              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                            ),
                          )
                        : ListView.builder(
                            itemCount: _filteredMenus.length,
                            itemBuilder: (context, index) {
                              final menu = _filteredMenus[index];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: defaultPadding / 2),
                                child: ItemCard(
                                  menuItem: menu,
                                  press: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => AddToOrderScreen(
                                        menuItem: menu,
                                        restaurant: widget.restaurant,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
