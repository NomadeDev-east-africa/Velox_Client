import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/promotion.dart';
import '../models/menu_item.dart';

class PromotionService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<List<Promotion>> getActivePromotionsForRestaurant(
      String restaurantId) async {
    try {
      final snapshot = await _db
          .collection('promotions')
          .where('restaurantId', isEqualTo: restaurantId)
          .where('isActive', isEqualTo: true)
          .get();

      return snapshot.docs
          .map((doc) => Promotion.fromFirestore(doc))
          .where((p) => p.isCurrentlyActive)
          .toList();
    } catch (e) {
      debugPrint('⚠️ [PromotionService] $e');
      return [];
    }
  }

  /// Résout la promo active applicable à un plat : d'abord une promo ciblant le
  /// plat (par ID ou slug du nom), sinon une promo ciblant sa catégorie.
  /// Retourne `null` si aucune promo active ne s'applique.
  /// Source de vérité partagée par tous les écrans (liste, recherche, catégorie,
  /// page d'ajout au panier) pour un affichage ET un prix facturé cohérents.
  static Promotion? resolveForItem(
      List<Promotion> promotions, MenuItem item) {
    for (final p in promotions) {
      if (p.matchesItem(item.id, item.name)) return p;
    }
    for (final p in promotions) {
      if (p.matchesCategory(item.category)) return p;
    }
    return null;
  }
}
