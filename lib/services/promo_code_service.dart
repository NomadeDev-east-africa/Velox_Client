import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

/// Résultat d'une validation de code promo.
class PromoCodeResult {
  const PromoCodeResult({
    required this.valid,
    this.code,
    this.discountAmount = 0,
    this.discountType,
    this.discountValue = 0,
    this.message,
  });

  final bool valid;

  /// Code normalisé renvoyé par le serveur (MAJUSCULES).
  final String? code;

  /// Montant de la remise en FDJ, **déjà calculé et plafonné côté serveur**.
  /// À afficher tel quel : ne jamais le recalculer côté client.
  final int discountAmount;

  /// "percentage" ou "fixed".
  final String? discountType;

  /// Valeur brute (ex : 10 pour -10 %), à titre informatif.
  final int discountValue;

  /// Message d'erreur à afficher quand [valid] est faux.
  final String? message;

  const PromoCodeResult.invalid(String message)
      : this(valid: false, message: message);
}

/// Validation des codes promo au checkout.
///
/// La collection `promoCodes` n'est **pas lisible côté client** (règles
/// Firestore) : tout passe par la Cloud Function callable `validatePromoCode`.
/// Le trigger `onOrderCreated` réévalue de toute façon le code à la création de
/// la commande et corrige la remise si besoin.
class PromoCodeService {
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  Future<PromoCodeResult> validate({
    required String code,
    required String restaurantId,
    required int subtotal,
    required int deliveryFee,
  }) async {
    final trimmed = code.trim().toUpperCase();
    if (trimmed.isEmpty) {
      return const PromoCodeResult.invalid('Saisissez un code promo');
    }

    try {
      final callable = _functions.httpsCallable('validatePromoCode');
      // Pas de paramètre de type sur `call` : sur iOS la réponse décodée est un
      // `Map<Object?, Object?>` et un `call<Map<String, dynamic>>` lèverait un
      // cast error — reconstruire la map explicitement est le chemin sûr.
      final response = await callable.call({
        'code': trimmed,
        'restaurantId': restaurantId,
        'subtotal': subtotal,
        'deliveryFee': deliveryFee,
      });

      final raw = response.data;
      if (raw is! Map) {
        return const PromoCodeResult.invalid('Réponse inattendue du serveur');
      }
      final data = Map<String, dynamic>.from(raw);

      if (data['valid'] != true) {
        return PromoCodeResult.invalid(
          (data['message'] as String?)?.trim().isNotEmpty == true
              ? data['message'] as String
              : 'Code promo invalide',
        );
      }

      return PromoCodeResult(
        valid: true,
        code: (data['code'] as String?) ?? trimmed,
        discountAmount: ((data['discountAmount'] ?? 0) as num).toInt(),
        discountType: data['discountType'] as String?,
        discountValue: ((data['discountValue'] ?? 0) as num).toInt(),
      );
    } on FirebaseFunctionsException catch (e) {
      debugPrint('⚠️ [PromoCodeService] ${e.code} — ${e.message}');
      return PromoCodeResult.invalid(
        e.message?.trim().isNotEmpty == true
            ? e.message!
            : 'Impossible de vérifier ce code',
      );
    } catch (e) {
      debugPrint('⚠️ [PromoCodeService] $e');
      return const PromoCodeResult.invalid(
        'Impossible de vérifier ce code. Vérifiez votre connexion.',
      );
    }
  }
}
