import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'constants.dart';
import 'theme/app_colors.dart';
import 'translations/app_translations.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'screens/homeScreen/home_screen_app.dart';
import 'screens/taxi/tracking_screen.dart';
import 'screens/food/food_tracking/order_tracking_screen.dart';
import 'widgets/velox_loader.dart';
import 'widgets/global_active_order_widget.dart';
import 'utils/route_tracker.dart';

// ── Providers Riverpod ───────────────────────────────────────────
import 'providers/all_providers.dart';
import 'providers/riverpod_error_observer.dart';

// ── Services et utilitaires ───────────────────────────────────────
import 'services/notification_service.dart';
import 'utils/local_cache.dart';
import 'services/hive_service.dart';
import 'firebase_options.dart';

// ════════════════════════════════════════════════════════════════
// BACKGROUND FCM HANDLER
// ════════════════════════════════════════════════════════════════

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(
    RemoteMessage message) async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }

  debugPrint('📨 [BGHandler] ${message.notification?.title}');
  debugPrint('   data: ${message.data}');

  // Persister les données de la notification en SharedPreferences
  // pour que l'app puisse naviguer au prochain démarrage
  final type    = message.data['type']    as String?;
  final orderId = message.data['orderId'] as String?;
  final rideId  = message.data['rideId']  as String?;

  if (type != null) {
    await LocalCache.init();  // SharedPreferences non initialisées en background
    await LocalCache.savePendingNotification(
      type: type,
      orderId: orderId,
      rideId: rideId,
    );
    debugPrint('💾 [BGHandler] Notification pending persistée: type=$type');
  }
}

// ════════════════════════════════════════════════════════════════
// MAIN
// ════════════════════════════════════════════════════════════════

// Instance Analytics globale — utilisable depuis n'importe quel écran
final FirebaseAnalytics analytics = FirebaseAnalytics.instance;
final FirebaseAnalyticsObserver analyticsObserver =
FirebaseAnalyticsObserver(analytics: analytics);

void main() {
  runZonedGuarded(
        () async {
      WidgetsFlutterBinding.ensureInitialized();

      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);

      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }

      // App Check désactivé temporairement — à réactiver avant publication store
      // avec un debug token enregistré dans Firebase Console → App Check

      FirebaseMessaging.onBackgroundMessage(
          _firebaseMessagingBackgroundHandler);

      // Erreurs Flutter NON fatales : le framework les signale sans que l'app
      // s'arrête — une image qui ne se charge pas, une tuile de carte
      // indisponible, un overflow de layout. `recordFlutterFatalError` les
      // remontait comme des plantages : les échecs réseau sur les images
      // représentaient l'essentiel des « crashes » du tableau de bord et
      // noyaient les vrais bugs.
      //
      // Les exceptions réellement non rattrapées restent enregistrées en fatal
      // par le handler de `runZonedGuarded`, plus bas.
      FlutterError.onError = (FlutterErrorDetails details) {
        if (kDebugMode) {
          FlutterError.dumpErrorToConsole(details);
        } else {
          FirebaseCrashlytics.instance.recordFlutterError(details);
        }
      };

      // Erreurs remontées par la plateforme hors zone Dart (callbacks natifs).
      // Sans ce handler elles disparaissaient silencieusement.
      PlatformDispatcher.instance.onError = (error, stack) {
        if (!kDebugMode) {
          FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        }
        return true;
      };

      // Ces services sont nécessaires avant runApp (Hive, cache, traductions)
      // Mais ils sont rapides (<50ms)
      // Désactiver le téléchargement des polices à l'exécution —
      // les fichiers doivent être présents dans assets/google_fonts/
      GoogleFonts.config.allowRuntimeFetching = false;

      await Future.wait([
        HiveService.init(),
        LocalCache.init(),
        AppTranslations.init(),
        // Données de locale pour DateFormat(..., 'fr_FR') (écran historique)
        initializeDateFormatting('fr_FR', null),
      ]);

      runApp(
        ProviderScope(
          observers: const [RiverpodErrorObserver()],
          child: const MyApp(),
        ),
      );
    },
        (Object error, StackTrace stack) {
      debugPrint('❌ [Zone] Erreur non gérée: $error');
      if (!kDebugMode) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      }
    },
  );
}

// ════════════════════════════════════════════════════════════════
// NAVIGATOR KEY GLOBAL — utilisé par NotificationService pour naviguer
// sans BuildContext
// ════════════════════════════════════════════════════════════════

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

// ════════════════════════════════════════════════════════════════
// MY APP
// ════════════════════════════════════════════════════════════════

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> with WidgetsBindingObserver {

  bool _fcmInitialized = false;
  StreamSubscription<User?>? _authSub;
  // Vrai seulement après un premier paused → évite de réagir aux resumed du démarrage
  // (dialog permission GPS cause inactive→resumed sans paused intermédiaire)
  bool _hasBeenPaused = false;

  // TextTheme construit à partir de AppColors (onSurface / onSurfaceVariant) —
  // remplace les Colors.white / bodyTextColor en dur pour rester cohérent
  // avec le thème clair ET sombre (voir PROMPT_THEME_ALIGNEMENT).
  static TextTheme _textThemeFrom(AppColors c) {
    return GoogleFonts.poppinsTextTheme(TextTheme(
      displayLarge:   GoogleFonts.poppins(textStyle: TextStyle(fontWeight: FontWeight.w700, color: c.onSurface)),
      displayMedium:  GoogleFonts.poppins(textStyle: TextStyle(fontWeight: FontWeight.w700, color: c.onSurface)),
      displaySmall:   GoogleFonts.poppins(textStyle: TextStyle(fontWeight: FontWeight.w700, color: c.onSurface)),
      headlineLarge:  GoogleFonts.poppins(textStyle: TextStyle(fontWeight: FontWeight.w700, color: c.onSurface)),
      headlineMedium: GoogleFonts.poppins(textStyle: TextStyle(fontWeight: FontWeight.w700, color: c.onSurface)),
      headlineSmall:  GoogleFonts.poppins(textStyle: TextStyle(fontWeight: FontWeight.w600, color: c.onSurface)),
      titleLarge:     GoogleFonts.poppins(textStyle: TextStyle(fontWeight: FontWeight.w700, color: c.onSurface)),
      titleMedium:    GoogleFonts.poppins(textStyle: TextStyle(fontWeight: FontWeight.w600, color: c.onSurface)),
      titleSmall:     GoogleFonts.poppins(textStyle: TextStyle(fontWeight: FontWeight.w500, color: c.onSurface)),
      bodyLarge:      GoogleFonts.inter(textStyle: TextStyle(color: c.onSurface)),
      bodyMedium:     GoogleFonts.inter(textStyle: TextStyle(color: c.onSurfaceVariant)),
      bodySmall:      GoogleFonts.inter(textStyle: TextStyle(color: c.onSurfaceVariant)),
      labelLarge:     GoogleFonts.inter(textStyle: TextStyle(color: c.onSurface, fontWeight: FontWeight.w600)),
      labelMedium:    GoogleFonts.inter(textStyle: TextStyle(color: c.onSurfaceVariant)),
      labelSmall:     GoogleFonts.inter(textStyle: TextStyle(color: c.onSurfaceVariant)),
    ));
  }

  // Empêche une double-navigation vers OrderTracking dans la même session VM
  bool _activeOrderNavigated = false;
  ProviderSubscription<ActiveOrderState>? _activeOrderSub;

  // Empêche une double-navigation vers TrackingScreen dans la même session VM
  bool _activeRideNavigated = false;
  ProviderSubscription<ActiveRideState>? _activeRideSub;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    // Consommer la notification pending (si l'app a été ouverte depuis une notif background)
    // puis surveiller la restauration d'une commande active depuis Hive
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _consumePendingNotification();
      _listenForActiveOrder();
      _listenForActiveRide();
    });

    _authSub = FirebaseAuth.instance.authStateChanges().listen((User? user) async {
      if (!mounted) return;
      if (user != null && !_fcmInitialized) {
        _fcmInitialized = true;
        debugPrint('🔔 Auth → user connecté: ${user.uid}');
        // Différer l'init notifications pour ne pas bloquer les premiers frames
        // (le background Flutter engine Firebase cause ~100 frames skippés si immédiat)
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          await Future.delayed(const Duration(milliseconds: 500));
          if (!mounted) return;
          await NotificationService().initialize(user.uid);
        });
      } else if (user == null) {
        _fcmInitialized = false;
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _activeOrderSub?.close();
    _activeRideSub?.close();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
        _hasBeenPaused = true;
        debugPrint('⏸️ App en arrière-plan — pause des streams');
        ref.read(activeRideProvider.notifier).pauseStream();
        ref.read(activeOrderProvider.notifier).pauseStream();
        ref.read(locationNotifierProvider.notifier).stopTracking();
        break;

      case AppLifecycleState.resumed:
        if (!_hasBeenPaused) break; // ignore les resumed du démarrage (dialogs permission)
        debugPrint('▶️ App au premier plan — reprise des streams');
        ref.read(activeRideProvider.notifier).resumeStream();
        ref.read(activeOrderProvider.notifier).resumeStream();
        ref.read(locationNotifierProvider.notifier).startTracking();
        ref.read(userNotifierProvider.notifier).refresh();
        _consumePendingNotification();
        break;

      default:
        break;
    }
  }

  // ── Restauration d'une commande active après crash / "Don't keep activities" ──
  //
  // activeOrderProvider._init() lit Hive en background et met à jour son état.
  // On s'abonne à ce provider : dès qu'une commande active est trouvée ET que
  // aucune notification pending n'a déjà géré la navigation, on redirige.
  // Le flag _activeOrderNavigated évite une double navigation dans la même
  // session VM (il se remet à false automatiquement si le moteur Flutter est recréé).

  void _listenForActiveOrder() {
    _activeOrderSub = ref.listenManual<ActiveOrderState>(
      activeOrderProvider,
          (previous, next) {
        if (_activeOrderNavigated) return;
        if (!next.isLoading && next.hasActiveOrder && next.orderId != null) {
          _navigateToActiveOrder(next.orderId!);
        }
      },
      fireImmediately: true, // vérifie aussi l'état initial (Hive déjà chargé)
    );
  }

  void _navigateToActiveOrder(String orderId) {
    final nav = appNavigatorKey.currentState;
    if (nav == null) return;

    // Ne pas naviguer si on est déjà sur la page de tracking
    final isAlreadyOnTracking = nav.canPop() &&
        nav.overlay?.context.widget.runtimeType.toString() == 'OrderTrackingScreen';
    if (isAlreadyOnTracking) return;

    _activeOrderNavigated = true;
    debugPrint('🔄 [MyApp] Commande active restaurée → navigation: $orderId');
    nav.pushNamed('/order-tracking', arguments: {'orderId': orderId});
  }

  // ── Restauration d'une course VTC active après crash / kill ──────
  //
  // Même mécanique que _listenForActiveOrder : ActiveRideNotifier._init()
  // lit le rideId depuis Hive au démarrage. Dès qu'une course active est
  // détectée, on redirige automatiquement vers TrackingScreen.
  // Le flag _activeRideNavigated évite une double navigation.

  void _listenForActiveRide() {
    _activeRideSub = ref.listenManual<ActiveRideState>(
      activeRideProvider,
      (previous, next) {
        if (_activeRideNavigated) return;
        if (!next.isLoading && next.hasActiveRide && next.rideId != null) {
          // Naviguer uniquement lors d'une restauration au démarrage :
          //   - previous == null → premier fire (Hive déjà chargé avant l'écoute)
          //   - previous.isLoading == true → Hive vient de finir de charger
          // Si previous a une course active = false & isLoading = false, c'est
          // une course créée dans cette session → RideConfirmationScreen gère déjà la navigation.
          final isStartupRestoration =
              previous == null || previous.isLoading;
          if (!isStartupRestoration) return;
          _navigateToActiveRide(next.rideId!);
        }
      },
      fireImmediately: true,
    );
  }

  void _navigateToActiveRide(String rideId) {
    final nav = appNavigatorKey.currentState;
    if (nav == null) return;

    _activeRideNavigated = true;
    debugPrint('🔄 [MyApp] Course VTC active restaurée → TrackingScreen');
    nav.pushNamed('/ride-tracking', arguments: {'rideId': rideId});
  }

  void _consumePendingNotification() {
    final pending = LocalCache.getPendingNotification();
    if (pending == null) return;

    debugPrint('🔔 [MyApp] Notification pending: type=${pending.type}');
    LocalCache.clearPendingNotification();

    switch (pending.type) {
      case 'order_update':
      case 'order_ready_client':
        if (pending.orderId != null) {
          _activeOrderNavigated = true; // évite la double navigation via _listenForActiveOrder
          appNavigatorKey.currentState
              ?.pushNamed('/order-tracking', arguments: {'orderId': pending.orderId});
        }
        break;
      case 'driver_accepted':
      case 'driver_arriving':
      case 'driver_arrived':
      case 'ride_started':
      case 'ride_completed':
      case 'ride_cancelled':
      case 'no_driver_available':
      // Anciens types — compatibilité
      case 'ride_accepted':
      case 'ride_update':
        if (pending.rideId != null) {
          _activeRideNavigated = true;
          appNavigatorKey.currentState
              ?.pushNamed('/ride-tracking', arguments: {'rideId': pending.rideId});
        }
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeState = ref.watch(themeNotifierProvider);
    // Reconstruit le sous-arbre quand la langue change (le système tr() est
    // statique : sans ce rebuild keyé, les écrans gardent l'ancienne langue).
    final language = ref.watch(languageNotifierProvider).language;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: appNavigatorKey,
      navigatorObservers: [analyticsObserver, RouteTracker()],
      title: 'Velox',
      // Overlay global : la pastille de suivi de commande vit au-dessus du
      // Navigator, donc elle survit à la navigation entre écrans (accueil /
      // fiche resto / panier / profil…). Elle se masque elle-même sur les
      // écrans de suivi et si aucune commande n'est active.
      builder: (context, child) => Stack(
        children: [
          child ?? const SizedBox.shrink(),
          const GlobalActiveOrderWidget(),
        ],
      ),
      onGenerateRoute: (settings) {
        final args = settings.arguments as Map<String, dynamic>? ?? {};
        switch (settings.name) {
          case '/ride-tracking':
          // TrackingScreen lit le rideId depuis activeRideProvider (Hive + Firestore)
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => const TrackingScreen(),
            );
          case '/order-tracking':
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => OrderTrackingScreen(
                orderId: args['orderId'] as String?,
              ),
            );
          default:
            return null; // Laisse Flutter gérer les routes inconnues
        }
      },
      theme: themeState.themeData.copyWith(
        // ── AppBar ────────────────────────────────────────────────
        appBarTheme: AppBarTheme(
          backgroundColor: themeState.colors.surfaceHigh,
          foregroundColor: themeState.colors.onSurface,
          elevation: 0,
          titleTextStyle: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: themeState.colors.onSurface,
          ),
          iconTheme: IconThemeData(
            color: themeState.colors.onSurface,
          ),
        ),

        // ── TextTheme — Poppins (titres) + Inter (corps), couleurs AppColors ──
        textTheme: _textThemeFrom(themeState.colors),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: themeState.colors.primary,
            foregroundColor: themeState.colors.onPrimary,
            minimumSize: const Size(double.infinity, 40),
            textStyle: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          contentPadding: const EdgeInsets.all(defaultPadding),
          hintStyle:      TextStyle(color: themeState.colors.onSurfaceVariant),
          labelStyle:     TextStyle(color: themeState.colors.onSurfaceVariant),
          filled:         true,
          fillColor: themeState.colors.surfaceHigh,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: themeState.colors.outlineVariant),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: themeState.colors.outlineVariant),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: themeState.colors.primary, width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: themeState.colors.error),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: themeState.colors.error, width: 1.5),
          ),
        ),
      ),
      home: KeyedSubtree(
        key: ValueKey('lang_$language'),
        child: const AuthWrapper(),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// AUTH WRAPPER
// Rôle : router vers HomeScreenApp si connecté, OnboardingScreen sinon.
// Utilisé comme `home` dans MaterialApp → résout le retour à l'onboarding
// après recreation d'Activity (background/foreground Android).
// ════════════════════════════════════════════════════════════════

class AuthWrapper extends ConsumerWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userState = ref.watch(userNotifierProvider);

    if (userState.isLoading) {
      return const VeloxLoader();
    }

    // Connecté → dashboard
    if (userState.isAuthenticated) {
      return const HomeScreenApp();
    }

    // Non connecté → onboarding
    return const OnboardingScreen();
  }
}