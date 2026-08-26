// ════════════════════════════════════════════════════════════════
// ALL_PROVIDERS.DART — Registre central Riverpod — Nomade253 Client
// ════════════════════════════════════════════════════════════════
//
// IMPORTER CE FICHIER dans chaque screen :
//   import 'package:nomade_client/providers/all_providers.dart';
//
// ════════════════════════════════════════════════════════════════

// ── Phase 2 — Providers UI ───────────────────────────────────────
export 'user_notifier.dart';           // userNotifierProvider
export 'theme_notifier.dart';          // themeNotifierProvider
export 'language_notifier.dart';       // languageNotifierProvider

// ── Phase 3 — Providers métier ride/order ────────────────────────
export 'active_ride_notifier.dart';    // activeRideProvider
export 'active_order_notifier.dart';   // activeOrderProvider

// ── Phase 4 — Panier ─────────────────────────────────────────────
export 'cart_notifier.dart';           // cartProvider

// ── Phase 5 — Restaurants ────────────────────────────────────────
export 'restaurant_notifier.dart';
// restaurantNotifierProvider
// allRestaurantsProvider     ← sélecteur
// featuredRestaurantsProvider← sélecteur
// popularRestaurantsProvider ← sélecteur
// restaurantsLoadingProvider ← sélecteur

// ── Phase 5 — Startup séquencé ───────────────────────────────────
export 'app_startup_service.dart';     // appStartupProvider

// ── Phase 7 — Adresses utilisateur ──────────────────────────────
export 'address_notifier.dart';        // addressNotifierProvider

// ── Stats commandes live ─────────────────────────────────────────
export 'order_stats_provider.dart';    // orderStatsProvider

// ── Historique commandes utilisateur ─────────────────────────────
export 'user_orders_provider.dart';    // userOrdersProvider

// ── Historique courses VTC utilisateur ───────────────────────────
export 'user_rides_provider.dart';     // userRidesProvider

// ── Bannières promo pilotées par l'admin ─────────────────────────
export 'banner_provider.dart';         // bannersProvider

// ── Tarifs VTC pilotés depuis Firestore ──────────────────────────
export 'taxi_pricing_provider.dart';
// rideChoicesProvider        ← catalogue tarifé (repli local automatique)
// defaultRideChoiceProvider  ← véhicule par défaut

// ── Favoris restaurants ───────────────────────────────────────────
export 'favorites_notifier.dart';      // favoritesNotifierProvider

// ── Préférences notifications ─────────────────────────────────────
export 'notifications_notifier.dart';  // notificationsNotifierProvider

// ── Historique notifications ──────────────────────────────────────
export 'notification_history_provider.dart';
// notificationHistoryProvider        ← liste temps réel
// unreadNotificationsCountProvider   ← pastille non-lus

// ── Phase 6 — GPS Riverpod ───────────────────────────────────────
export 'location_notifier.dart';
// locationNotifierProvider
// currentPositionProvider    ← sélecteur
// currentAddressProvider     ← sélecteur
// locationLoadingProvider    ← sélecteur

// ════════════════════════════════════════════════════════════════
// MIGRATION RIVERPOD TERMINÉE — MultiProvider supprimé
// LocationProvider, RestaurantProvider, MenuProvider : RETIRÉS
// Tous les providers sont désormais gérés par Riverpod
// ════════════════════════════════════════════════════════════════
