import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../components/floating_cart_button.dart';
import '../../../constants.dart';
import '../../../translations/app_translations.dart';
import 'restaurant_menu_search_screen.dart';
import 'components/featured_items.dart';
import 'components/iteams.dart';
import 'components/restaurant_info.dart';
import '../../../models/restaurant.dart';
// ─────────────────────────────────────────────────────────────────────────────
// SECTION AVIS CLIENTS — lit restaurants/{id}/avis en temps réel
// ─────────────────────────────────────────────────────────────────────────────

class _AvisSection extends StatelessWidget {
  final String restaurantId;

  const _AvisSection({required this.restaurantId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('restaurants')
          .doc(restaurantId)
          .collection('avis')
          .orderBy('createdAt', descending: true)
          .limit(20)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink();
        }

        final docs = snapshot.data?.docs ?? [];
        // Filtrer : n'afficher que les avis avec un commentaire non vide
        final avecCommentaire = docs.where((d) {
          final c = (d.data() as Map<String, dynamic>)['commentaire'] as String? ?? '';
          return c.trim().isNotEmpty;
        }).toList();

        if (avecCommentaire.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: defaultPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.chat_bubble_outline,
                      color: primaryColor, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    '${tr('customer_reviews')} (${avecCommentaire.length})',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...avecCommentaire.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final note        = (data['note'] as num?)?.toInt() ?? 0;
                final commentaire = data['commentaire'] as String? ?? '';
                final clientNom   = data['clientNom'] as String? ?? 'Client';
                final ts          = data['createdAt'] as Timestamp?;
                final date        = ts != null
                    ? _formatDate(ts.toDate())
                    : '';

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.08),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          // Étoiles
                          ...List.generate(5, (i) => Icon(
                            i < note
                                ? Icons.star_rounded
                                : Icons.star_border_rounded,
                            size: 16,
                            color: i < note
                                ? Colors.amber
                                : Theme.of(context).colorScheme.outlineVariant,
                          )),
                          const Spacer(),
                          Text(
                            date,
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.45),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        commentaire,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        clientNom,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: primaryColor,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}/'
           '${dt.month.toString().padLeft(2, '0')}/'
           '${dt.year}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class DetailsScreen extends StatelessWidget {
  final Restaurant restaurant;

  const DetailsScreen({
    super.key,
    required this.restaurant,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            icon: SvgPicture.asset(
              "assets/icons/share.svg",
              colorFilter: ColorFilter.mode(
                Theme.of(context).appBarTheme.foregroundColor ?? Colors.black87,
                BlendMode.srcIn,
              ),
            ),
            onPressed: () {},
          ),
          IconButton(
            icon: SvgPicture.asset(
              "assets/icons/search.svg",
              colorFilter: ColorFilter.mode(
                Theme.of(context).appBarTheme.foregroundColor ?? Colors.black87,
                BlendMode.srcIn,
              ),
            ),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => RestaurantMenuSearchScreen(restaurant: restaurant),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Stack( // ✅ CHANGEMENT: Column → Stack
          children: [
            SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: defaultPadding / 2),
                  RestaurantInfo(restaurant: restaurant),
                  const SizedBox(height: defaultPadding),
                  FeaturedItems(
                    restaurantId: restaurant.id,
                    restaurant: restaurant,
                  ),
                  const SizedBox(height: defaultPadding),
                  Items(
                    restaurantId: restaurant.id,
                    restaurant: restaurant,
                  ),
                  const SizedBox(height: defaultPadding),
                  _AvisSection(restaurantId: restaurant.id),
                  const SizedBox(height: 80), // ✅ Ajouter un espace pour le bouton flottant
                ],
              ),
            ),
            const Positioned( // ✅ Positioned directement dans Stack
              left: 0,
              right: 0,
              bottom: 20,
              child: FloatingCartButton(),
            ),
          ],
        ),
      ),
    );
  }
}