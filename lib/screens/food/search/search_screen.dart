import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../components/cards/big/restaurant_info_big_card.dart';
import '../../../components/scalton/big_card_scalton.dart';
import '../../../constants.dart';
import '../../../services/restaurant_service.dart';
import '../../../models/restaurant.dart';
import '../details/details_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _searchController = TextEditingController();
  List<Restaurant> _searchResults = [];
  List<Restaurant> _topRestaurants = [];
  bool _isSearching = false;
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadTopRestaurants();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadTopRestaurants() async {
    setState(() => _isLoading = true);

    final results = await RestaurantService().getTopRatedRestaurants(limit: 10);

    if (mounted) {
      setState(() {
        _topRestaurants = results;
        _isLoading = false;
      });
    }
  }

  Future<void> _performSearch(String query) async {
    if (query.isEmpty) {
      setState(() {
        _isSearching = false;
        _searchResults = [];
        _searchQuery = '';
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _isLoading = true;
      _searchQuery = query;
    });

    final results = await RestaurantService().searchRestaurants(query);

    if (mounted) {
      setState(() {
        _searchResults = results;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayRestaurants = _isSearching ? _searchResults : _topRestaurants;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: defaultPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: defaultPadding),
              Text('Search', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: defaultPadding),

              // Search Form
              SearchForm(
                controller: _searchController,
                onChanged: (value) {
                  if (value.length >= 2) {
                    _performSearch(value);
                  } else if (value.isEmpty) {
                    _performSearch('');
                  }
                },
                onSubmitted: (value) {
                  _performSearch(value);
                },
              ),

              const SizedBox(height: defaultPadding),

              // Title
              Text(
                _isSearching
                    ? 'Résultats de recherche${_searchQuery.isNotEmpty ? ' pour "$_searchQuery"' : ''}'
                    : "Top Restaurants",
                style: Theme.of(context).textTheme.titleLarge,
              ),

              const SizedBox(height: defaultPadding),

              // Results List
              Expanded(
                child: _isLoading
                    ? ListView.builder(
                  itemCount: 2,
                  itemBuilder: (context, index) => const Padding(
                    padding: EdgeInsets.only(bottom: defaultPadding),
                    child: BigCardScalton(),
                  ),
                )
                    : displayRestaurants.isEmpty
                    ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _isSearching ? Icons.search_off : Icons.restaurant,
                        size: 64,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _isSearching
                            ? 'Aucun résultat trouvé'
                            : 'Aucun restaurant disponible',
                        style: TextStyle(
                          fontSize: 16,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (_isSearching) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Essayez avec un autre mot-clé',
                          style: TextStyle(
                            fontSize: 14,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                )
                    : RefreshIndicator(
                  onRefresh: _isSearching
                      ? () => _performSearch(_searchQuery)
                      : _loadTopRestaurants,
                  child: ListView.builder(
                    itemCount: displayRestaurants.length,
                    itemBuilder: (context, index) {
                      final restaurant = displayRestaurants[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: defaultPadding),
                        child: RestaurantInfoBigCard(
                          restaurant: restaurant,
                          deliveryTime: 25,
                          press: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    DetailsScreen(restaurant: restaurant),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SearchForm extends StatelessWidget {
  final TextEditingController controller;
  final Function(String) onChanged;
  final Function(String) onSubmitted;
  final String hintText;

  const SearchForm({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.onSubmitted,
    this.hintText = "Rechercher un restaurant...",
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      onChanged: onChanged,
      onFieldSubmitted: onSubmitted,
      style: Theme.of(context).textTheme.labelLarge,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: hintText,
        contentPadding: kTextFieldPadding,
        prefixIcon: Padding(
          padding: const EdgeInsets.all(8.0),
          child: SvgPicture.asset(
            'assets/icons/search.svg',
            colorFilter: ColorFilter.mode(
              Theme.of(context).colorScheme.onSurfaceVariant,
              BlendMode.srcIn,
            ),
          ),
        ),
        suffixIcon: controller.text.isNotEmpty
            ? IconButton(
          icon: const Icon(Icons.clear),
          onPressed: () {
            controller.clear();
            onChanged('');
          },
        )
            : null,
      ),
    );
  }
}