import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart' hide Order;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../constants.dart';
import '../models/order.dart';
import '../models/order_item.dart';
import '../models/restaurant.dart';
import '../services/hive_service.dart';
import '../services/order_service.dart';
import '../services/food_notification_service.dart';
import 'active_order_notifier.dart';
import 'user_notifier.dart';

class CartState {
  final List<OrderItem> items;
  final Restaurant? selectedRestaurant;
  final bool isCreatingOrder;
  final String? error;

  static const int _deliveryFee = 500;

  const CartState({
    this.items = const [],
    this.selectedRestaurant,
    this.isCreatingOrder = false,
    this.error,
  });

  int get deliveryFee => _deliveryFee;
  bool get isEmpty => items.isEmpty;
  int get itemCount => items.fold(0, (acc, item) => acc + item.quantity);
  int get subtotal => items.fold(0, (acc, item) => acc + item.totalPrice);
  int get total => subtotal + _deliveryFee;

  bool isDifferentRestaurant(String restaurantId) {
    if (selectedRestaurant == null) return false;
    return selectedRestaurant!.id != restaurantId;
  }

  CartState copyWith({
    List<OrderItem>? items,
    Restaurant? selectedRestaurant,
    bool? isCreatingOrder,
    String? error,
    bool clearRestaurant = false,
    bool clearError = false,
  }) {
    return CartState(
      items: items ?? this.items,
      selectedRestaurant: clearRestaurant ? null : (selectedRestaurant ?? this.selectedRestaurant),
      isCreatingOrder: isCreatingOrder ?? this.isCreatingOrder,
      error: clearError ? null : (error ?? this.error),
    );
  }

  Map<String, dynamic> toJson() => {
    'restaurantId': selectedRestaurant?.id,
    'restaurantName': selectedRestaurant?.name,
    'restaurantAddress': selectedRestaurant?.address,
    'restaurantImageUrl': selectedRestaurant?.imageUrl,
    'restaurantDesc': selectedRestaurant?.description,
    'restaurantEmail': selectedRestaurant?.email,
    'restaurantPhone': selectedRestaurant?.phone,
    'restaurantLat': selectedRestaurant?.latitude,
    'restaurantLon': selectedRestaurant?.longitude,
    'restaurantRating': selectedRestaurant?.rating,
    'restaurantCreatedAt': selectedRestaurant?.createdAt.toIso8601String(),
    'items': items.map((i) => i.toJson()).toList(),
  };

  factory CartState.fromJson(Map<String, dynamic> json) {
    Restaurant? restaurant;
    if (json['restaurantId'] != null) {
      try {
        // Restauration avec conversion de createdAt string en DateTime
        restaurant = Restaurant(
          id: json['restaurantId'] as String,
          name: json['restaurantName'] as String? ?? '',
          address: json['restaurantAddress'] as String? ?? '',
          description: json['restaurantDesc'] as String? ?? '',
          email: json['restaurantEmail'] as String? ?? '',
          phone: json['restaurantPhone'] as String? ?? '',
          imageUrl: json['restaurantImageUrl'] as String? ?? '',
          latitude: (json['restaurantLat'] as num?)?.toDouble() ?? 0.0,
          longitude: (json['restaurantLon'] as num?)?.toDouble() ?? 0.0,
          rating: (json['restaurantRating'] as num?)?.toDouble() ?? 0.0,
          // On convertit de string ISO8601 à DateTime, si absent prend DateTime.now()
          createdAt: json['restaurantCreatedAt'] != null
              ? DateTime.parse(json['restaurantCreatedAt'] as String)
              : DateTime.now(),
        );
      } catch (e) {
        debugPrint('⚠️ [CartNotifier] Restauration restaurant: $e');
      }
    }

    final rawItems = json['items'] as List? ?? [];
    final items = rawItems
        .map((i) => OrderItem.fromJson(Map<String, dynamic>.from(i as Map)))
        .toList();

    return CartState(items: items, selectedRestaurant: restaurant);
  }
}

class CartNotifier extends StateNotifier<CartState> {
  final Ref _ref;

  CartNotifier(this._ref) : super(const CartState()) {
    _restoreFromHive();
  }

  void _restoreFromHive() {
    try {
      final json = HiveService.getCartJson();
      if (json == null) return;
      final data = CartState.fromJson(
          Map<String, dynamic>.from(jsonDecode(json) as Map));
      if (data.isEmpty) {
        HiveService.clearCart();
        return;
      }
      state = data;
      debugPrint(
          '📦 [CartNotifier] Panier restauré: ${data.itemCount} article(s) — ${data.selectedRestaurant?.name ?? "?"}');
    } catch (e) {
      debugPrint('⚠️ [CartNotifier] Cache corrompu: $e');
      HiveService.clearCart();
    }
  }

  void _persistToHive() {
    try {
      if (state.isEmpty) {
        HiveService.clearCart();
      } else {
        HiveService.saveCartJson(jsonEncode(state.toJson()));
      }
    } catch (e) {
      debugPrint('⚠️ [CartNotifier] Persist Hive: $e');
    }
  }

  void setRestaurant(Restaurant restaurant) {
    debugPrint('🏪 [CartNotifier] Restaurant: ${restaurant.name}');
    state = state.copyWith(selectedRestaurant: restaurant);
    _persistToHive();
  }

  void addItem(OrderItem item) {
    debugPrint('➕ [CartNotifier] Ajouter: ${item.name}');
    state = state.copyWith(items: [...state.items, item]);
    _persistToHive();
  }

  void removeItem(OrderItem item) {
    debugPrint('➖ [CartNotifier] Retirer: ${item.name}');
    final updated = state.items.where((i) => i != item).toList();
    state = state.copyWith(
      items: updated,
      clearRestaurant: updated.isEmpty,
    );
    _persistToHive();
  }

  void incrementQuantity(OrderItem item) {
    final index = state.items.indexOf(item);
    if (index == -1) return;
    final updated = List<OrderItem>.from(state.items);
    updated[index] = updated[index].copyWith(quantity: updated[index].quantity + 1);
    state = state.copyWith(items: updated);
    _persistToHive();
  }

  void decrementQuantity(OrderItem item) {
    final index = state.items.indexOf(item);
    if (index == -1) return;
    final updated = List<OrderItem>.from(state.items);
    if (updated[index].quantity > 1) {
      updated[index] = updated[index].copyWith(quantity: updated[index].quantity - 1);
      state = state.copyWith(items: updated);
    } else {
      updated.removeAt(index);
      state = state.copyWith(
        items: updated,
        clearRestaurant: updated.isEmpty,
      );
    }
    _persistToHive();
  }

  void clearCart() {
    debugPrint('🗑️ [CartNotifier] Panier vidé');
    state = const CartState();
    HiveService.clearCart();
  }

  void clearError() {
    if (mounted) state = state.copyWith(clearError: true);
  }

  Future<String?> createOrder({
    required String userId,
    required String paymentMethod,
    required String deliveryAddress,
    LatLng? deliveryLocation,
    String? addressDetails,
    String? customerName,
    String? customerPhone,
    int pointsUsed = 0,
    String? promoCode,
    int promoDiscount = 0,
  }) async {
    if (state.isEmpty || state.selectedRestaurant == null) {
      debugPrint('❌ [CartNotifier] Panier vide ou restaurant null');
      return null;
    }
    if (!mounted) return null;

    state = state.copyWith(isCreatingOrder: true, clearError: true);

    try {
      debugPrint('🛒 [CartNotifier] Création commande...');
      debugPrint('  - Restaurant: ${state.selectedRestaurant!.name}');
      debugPrint('  - Items: ${state.items.length}');

      final customerInfo = (customerName != null && customerPhone != null)
          ? {'name': customerName, 'phone': customerPhone}
          : await _getCustomerInfo(userId);

      GeoPoint? geoPoint;
      if (deliveryLocation != null) {
        geoPoint = GeoPoint(deliveryLocation.latitude, deliveryLocation.longitude);
      }

      // Réduction fidélité — appliquée UNIQUEMENT aux frais de livraison.
      // Plafond = deliveryFee → le subtotal (part restaurant) reste intact.
      final maxByDelivery = state.deliveryFee ~/ kPointValue;
      final safePoints = pointsUsed.clamp(0, maxByDelivery);
      final discount = safePoints * kPointValue;

      // Le code promo n'est transmis que s'il porte réellement une remise ; le
      // trigger `onOrderCreated` revalide de toute façon le couple
      // code/montant côté serveur et le corrige si besoin.
      final safePromoCode =
          (promoDiscount > 0 && (promoCode?.trim().isNotEmpty ?? false))
              ? promoCode!.trim().toUpperCase()
              : null;
      final safePromoDiscount = safePromoCode == null ? 0 : promoDiscount;

      final order = Order(
        id: '',
        userId: userId,
        restaurantId: state.selectedRestaurant!.id,
        restaurantName: state.selectedRestaurant!.name,
        restaurantImageUrl: state.selectedRestaurant!.imageUrl,
        customerName: customerInfo['name']!,
        customerPhone: customerInfo['phone']!,
        items: List<OrderItem>.from(state.items),
        deliveryFee: state.deliveryFee,
        status: Order.statusPending,
        paymentMethod: paymentMethod,
        deliveryAddress: deliveryAddress,
        deliveryLocation: geoPoint,
        addressDetails: addressDetails,
        createdAt: Timestamp.now(),
        updatedAt: Timestamp.now(),
        pointsUsed: safePoints,
        discount: discount,
        promoCode: safePromoCode,
        promoDiscount: safePromoDiscount,
      );

      final orderId = await OrderService().createOrder(order);

      if (orderId == null) {
        debugPrint('❌ [CartNotifier] Firestore createOrder retourne null');
        if (mounted) {
          state = state.copyWith(
            isCreatingOrder: false,
            error: 'Échec création commande',
          );
        }
        return null;
      }

      debugPrint('✅ [CartNotifier] Commande créée: $orderId');

      await HiveService.clearOrder();
      debugPrint('🧹 [CartNotifier] Ancienne commande Hive effacée');

      // Reconstruire l'Order avec le vrai ID pour éviter un round-trip Firestore
      // → activeOrderProvider set son état immédiatement → navigation instantanée
      final createdOrder = Order(
        id:               orderId,
        userId:           order.userId,
        restaurantId:     order.restaurantId,
        restaurantName:   order.restaurantName,
        restaurantImageUrl: order.restaurantImageUrl,
        customerName:     order.customerName,
        customerPhone:    order.customerPhone,
        items:            order.items,
        deliveryFee:      order.deliveryFee,
        status:           order.status,
        paymentMethod:    order.paymentMethod,
        deliveryAddress:  order.deliveryAddress,
        deliveryLocation: order.deliveryLocation,
        addressDetails:   order.addressDetails,
        createdAt:        order.createdAt,
        updatedAt:        order.updatedAt,
        pointsUsed:       order.pointsUsed,
        discount:         order.discount,
        promoCode:        order.promoCode,
        promoDiscount:    order.promoDiscount,
      );

      // Débiter les points utilisés (non bloquant)
      if (safePoints > 0) {
        unawaited(
          _ref
              .read(userNotifierProvider.notifier)
              .redeemPoints(safePoints)
              .catchError(
                  (e) => debugPrint('⚠️ [CartNotifier] redeemPoints: $e')),
        );
      }

      // Non bloquant — la navigation ne doit pas attendre le stream Firestore
      unawaited(
        _ref.read(activeOrderProvider.notifier).attachOrder(orderId, initialOrder: createdOrder)
            .catchError((e) => debugPrint('⚠️ [CartNotifier] attachOrder: $e')),
      );

      unawaited(
        FoodNotificationService()
            .notifyRestaurantNewOrder(
          restaurantId: state.selectedRestaurant!.id,
          restaurantName: state.selectedRestaurant!.name,
          orderId: orderId,
          customerName: customerInfo['name']!,
          total: order.total,
        )
            .catchError((e) => debugPrint('⚠️ [CartNotifier] Notif: $e')),
      );

      clearCart();

      if (mounted) {
        state = state.copyWith(isCreatingOrder: false, clearError: true);
      }

      return orderId;
    } catch (e) {
      debugPrint('❌ [CartNotifier] createOrder: $e');
      if (mounted) {
        state = state.copyWith(
          isCreatingOrder: false,
          error: e.toString(),
        );
      }
      return null;
    }
  }

  Future<Map<String, String>> _getCustomerInfo(String userId) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
      if (doc.exists) {
        final data = doc.data();
        return {
          'name': data?['name'] ?? data?['displayName'] ?? 'Client',
          'phone': data?['phone'] ?? data?['phoneNumber'] ?? 'Non renseigné',
        };
      }
      final u = FirebaseAuth.instance.currentUser;
      return {
        'name': u?.displayName ?? 'Client',
        'phone': u?.phoneNumber ?? 'Non renseigné',
      };
    } catch (e, st) {
      debugPrint('⚠️ [CartNotifier] _getCustomerInfo échoué, fallback anonyme: $e');
      // Rapporter en Crashlytics en prod pour surveiller la fréquence
      assert(() {
        // En debug, laisser remonter pour détecter les problèmes tôt
        return true;
      }());
      if (const bool.fromEnvironment('dart.vm.product')) {
        // ignore: avoid_catches_without_on_clauses — intentionnel, fallback gracieux
        FirebaseCrashlytics.instance.recordError(
          e, st,
          reason: 'CartNotifier._getCustomerInfo fallback',
          fatal: false,
        );
      }
      return {'name': 'Client', 'phone': 'Non renseigné'};
    }
  }
}

final cartProvider =
StateNotifierProvider<CartNotifier, CartState>((ref) => CartNotifier(ref));