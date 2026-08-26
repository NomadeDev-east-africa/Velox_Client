import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:nomade_client/main.dart' show appNavigatorKey;
import 'package:nomade_client/utils/local_cache.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final FlutterLocalNotificationsPlugin _localNotifications =
  FlutterLocalNotificationsPlugin();

  String? _lastSavedToken;
  // ✅ FIX : Garder trace du dernier userId pour lequel le token a été sauvegardé
  String? _lastSavedUserId;
  String? _userId;

  // ── Guards statiques ─────────────────────────────────────────────────────
  // Persistent à l'échelle du Dart VM (survit aux recreations de Widget/State
  // mais PAS à un redémarrage complet du moteur Flutter).
  static bool _handlersSetup = false;      // évite les double-listeners FCM
  static String? _initializedForUserId;    // évite le re-init complet pour même user
  static bool _permissionInProgress = false; // évite les appels requestPermission() concurrents

  /// Initialiser avec l'ID utilisateur
  Future<void> initialize(String userId) async {
    // ── Guard 1 : même user déjà initialisé dans cette session VM ──────────
    if (_initializedForUserId == userId) {
      debugPrint('⏭️ [NotificationService] Déjà initialisé pour $userId — refresh token uniquement');
      await _refreshAndSaveToken();
      return;
    }

    // ── Guard 2 : changement d'utilisateur → reset des caches ───────────────
    final bool userChanged = _userId != null && _userId != userId;
    if (userChanged) {
      debugPrint('🔄 [NotificationService] Changement user: $_userId → $userId');
      _lastSavedToken = null;
      _lastSavedUserId = null;
      _handlersSetup = false; // forcer la ré-écoute pour le nouveau user
    }

    _userId = userId;

    // 1. Demander les permissions (avec garde contre les appels concurrents)
    if (_permissionInProgress) {
      debugPrint('⏭️ [NotificationService] requestPermission déjà en cours — annulé');
      return;
    }
    _permissionInProgress = true;
    final NotificationSettings settings;
    try {
      settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
    } finally {
      _permissionInProgress = false;
    }
    debugPrint(
        '📲 [NotificationService] Statut permissions: ${settings.authorizationStatus}');

    if (settings.authorizationStatus != AuthorizationStatus.authorized) {
      debugPrint('⚠️ [NotificationService] Notifications non autorisées');
      return;
    }

    // 2. Créer le canal de notification pour Android
    if (defaultTargetPlatform == TargetPlatform.android) {
      await _createAndroidNotificationChannel();
    }

    // 3. Initialiser le plugin de notifications locales
    await _initLocalNotifications();

    // ✅ iOS : afficher la notif (alert/badge/son) quand l'app est au premier plan.
    // Sans ça, sur iOS, aucune bannière système ne s'affiche en foreground.
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    }

    // 4. Configurer les handlers (une seule fois par VM lifetime)
    if (!_handlersSetup) {
      _setupMessageHandlers();
      _messaging.onTokenRefresh.listen((newToken) async {
        debugPrint('🔄 [NotificationService] Token FCM rafraîchi');
        await _saveTokenToFirestore(newToken);
      });
      _handlersSetup = true;
    }

    // 5. Obtenir et sauvegarder le token FCM
    await _refreshAndSaveToken();

    // Marquer cet userId comme initialisé
    _initializedForUserId = userId;

    debugPrint('✅ [NotificationService] Initialisé avec succès');
  }

  /// ✅ Créer le canal de notification Android
  Future<void> _createAndroidNotificationChannel() async {
    final AndroidNotificationChannel channel = AndroidNotificationChannel(
      'orders',
      'Commandes Nomade',
      description: 'Notifications pour vos commandes alimentaires',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
      showBadge: true,
      sound: const RawResourceAndroidNotificationSound('notification'),
      vibrationPattern: Int64List.fromList([0, 500, 500, 500]),
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    debugPrint('✅ [NotificationService] Canal Android créé: orders');
  }

  // ── Catégories iOS ────────────────────────────────────────────────────────
  // Identifiants partagés avec le backend : ils doivent apparaître tels quels
  // dans `aps.category` de la charge utile APNs pour que les notifications
  // reçues hors premier plan soient elles aussi dépliables.
  static const String categoryOrder = 'VELOX_ORDER';
  static const String categoryRide  = 'VELOX_RIDE';
  static const String categoryPromo = 'VELOX_PROMO';

  /// Catégorie correspondant à un `type` de push.
  static String _categoryFor(String? type) {
    switch (type) {
      case 'order_update':
      case 'order_ready_client':
        return categoryOrder;
      case 'driver_accepted':
      case 'driver_arriving':
      case 'driver_arrived':
      case 'ride_started':
      case 'ride_completed':
      case 'ride_cancelled':
      case 'no_driver_available':
      case 'ride_accepted':
      case 'ride_update':
        return categoryRide;
      default:
        return categoryPromo;
    }
  }

  /// ✅ Initialiser les notifications locales
  Future<void> _initLocalNotifications() async {
    const AndroidInitializationSettings androidSettings =
    AndroidInitializationSettings('@mipmap/ic_launcher');

    // Non `const` : `DarwinNotificationAction.plain` n'est pas un constructeur
    // constant.
    final DarwinInitializationSettings iosSettings =
    DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
      // Catégories iOS : c'est leur enregistrement qui donne à une notification
      // un contenu dépliable avec des actions. Sans catégorie, iOS n'affiche
      // que la bannière tronquée et rien ne se passe à l'appui long.
      //
      // ⚠️ Ne vaut que pour les notifications AFFICHÉES PAR L'APP (premier
      // plan). Quand l'app est en arrière-plan ou fermée, iOS rend directement
      // la charge utile APNs : le backend doit y placer `aps.category` avec ces
      // mêmes identifiants, sinon la notification reste sans actions.
      notificationCategories: <DarwinNotificationCategory>[
        DarwinNotificationCategory(
          categoryOrder,
          actions: <DarwinNotificationAction>[
            DarwinNotificationAction.plain('view_order', 'Voir la commande'),
          ],
          options: <DarwinNotificationCategoryOption>{
            DarwinNotificationCategoryOption.hiddenPreviewShowTitle,
          },
        ),
        DarwinNotificationCategory(
          categoryRide,
          actions: <DarwinNotificationAction>[
            DarwinNotificationAction.plain('view_ride', 'Suivre la course'),
          ],
          options: <DarwinNotificationCategoryOption>{
            DarwinNotificationCategoryOption.hiddenPreviewShowTitle,
          },
        ),
        DarwinNotificationCategory(
          categoryPromo,
          options: <DarwinNotificationCategoryOption>{
            DarwinNotificationCategoryOption.hiddenPreviewShowTitle,
          },
        ),
      ],
    );

    final InitializationSettings settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      settings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );
  }

  /// Gérer le tap sur une notification locale (flutter_local_notifications)
  void _onNotificationTap(NotificationResponse response) {
    debugPrint('🔔 [NotificationService] Tap sur notification: ${response.payload}');
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;

    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      final type    = data['type']    as String?;
      final orderId = data['orderId'] as String?;
      final rideId  = data['rideId']  as String?;

      switch (type) {
        case 'order_update':
        case 'order_ready_client':
          if (orderId != null) _navigateToOrder(orderId);
          break;
        case 'driver_accepted':
        case 'driver_arriving':
        case 'driver_arrived':
        case 'ride_started':
        case 'ride_completed':
        case 'ride_cancelled':
        case 'no_driver_available':
        case 'ride_accepted':
        case 'ride_update':
          if (rideId != null) _navigateToRide(rideId);
          break;
        default:
          if (orderId != null) _navigateToOrder(orderId);
      }
    } catch (_) {
      // Legacy payload (plain orderId string)
      if (payload.isNotEmpty) _navigateToOrder(payload);
    }
  }

  /// ✅ Configurer les handlers de messages
  void _setupMessageHandlers() {
    // Messages au premier plan
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Messages depuis background (tap)
    FirebaseMessaging.onMessageOpenedApp.listen(_handleBackgroundMessage);

    // Message initial si app était fermée
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) {
        debugPrint(
            '📬 [NotificationService] Message initial: ${message.notification?.title}');
        _handleMessageClick(message);
      }
    });
  }

  /// ✅ Rafraîchir et sauvegarder le token
  Future<void> _refreshAndSaveToken() async {
    // `getToken()` et `getAPNSToken()` lèvent une PlatformException quand le
    // canal natif répond en erreur — APNs pas encore enregistré, réseau absent
    // au lancement. Non capturée, l'exception remontait jusqu'à
    // `FlutterError.onError` et était comptée comme un plantage au démarrage.
    // Ne pas obtenir de jeton n'est pas fatal : les notifications sont
    // simplement indisponibles jusqu'à la prochaine tentative.
    try {
      // ✅ FIX iOS : le token APNs doit être disponible AVANT d'appeler getToken(),
      // sinon FCM renvoie null (race condition fréquente au 1er lancement de l'app).
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final apnsToken = await _waitForApnsToken();
        if (apnsToken == null) {
          debugPrint(
              '⚠️ [NotificationService] Token APNs indisponible après plusieurs tentatives — token FCM non récupéré');
          return;
        }
      }

      final token = await _messaging.getToken();
      if (token != null) {
        debugPrint(
            '📱 [NotificationService] Token FCM récupéré (${token.length} caractères)');
        await _saveTokenToFirestore(token);
      } else {
        debugPrint('⚠️ [NotificationService] Token FCM null');
      }
    } catch (e, stack) {
      debugPrint('⚠️ [NotificationService] Récupération du token FCM échouée: $e');
      // Tracé en non-fatal : utile pour mesurer la fréquence sans polluer les
      // plantages. `onTokenRefresh` reprendra la main dès que FCM en émet un.
      if (!kDebugMode) {
        FirebaseCrashlytics.instance.recordError(
          e,
          stack,
          reason: 'getToken FCM',
          fatal: false,
        );
      }
    }
  }

  /// ✅ iOS : attend que le token APNs soit prêt (retry avec délai).
  /// `getToken()` peut échouer/renvoyer null si appelé avant que l'OS ait
  /// fini d'enregistrer l'app auprès d'APNs.
  Future<String?> _waitForApnsToken({int maxAttempts = 5}) async {
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      final apnsToken = await _messaging.getAPNSToken();
      if (apnsToken != null) {
        debugPrint('📲 [NotificationService] Token APNs prêt (tentative $attempt)');
        return apnsToken;
      }
      debugPrint(
          '⏳ [NotificationService] Token APNs pas encore prêt (tentative $attempt/$maxAttempts)');
      await Future.delayed(const Duration(seconds: 1));
    }
    return null;
  }

  /// ✅ Sauvegarder le token FCM
  Future<void> _saveTokenToFirestore(String token) async {
    if (_userId == null) {
      debugPrint('⚠️ [NotificationService] User non connecté');
      return;
    }

    // ✅ FIX : Vérifier AUSSI si le userId a changé
    // Un même token device peut appartenir à plusieurs users successifs
    // → Si userId différent du dernier sauvegardé, FORCER l'écriture
    final bool sameToken = _lastSavedToken == token;
    final bool sameUser  = _lastSavedUserId == _userId;

    if (sameToken && sameUser) {
      debugPrint('⏭️ [NotificationService] Token identique pour même user, écriture ignorée');
      return;
    }

    // ✅ FIX : Vérifier aussi le cache local UNIQUEMENT si même userId
    // Si userId différent → ignorer le cache local et forcer l'écriture
    if (sameUser) {
      final cachedToken = LocalCache.getFcmToken();
      if (cachedToken == token) {
        debugPrint('⏭️ [NotificationService] Token en cache identique, écriture ignorée');
        _lastSavedToken = token;
        _lastSavedUserId = _userId;
        return;
      }
    }

    try {
      // 1. Cache local en premier : survit à un crash entre les deux opérations
      await LocalCache.saveFcmToken(token);

      // 2. Firestore ensuite : source de vérité serveur
      await _firestore.collection('users').doc(_userId).set({
        'fcmToken': token,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      _lastSavedToken  = token;
      _lastSavedUserId = _userId;

      debugPrint('✅ [NotificationService] Token FCM sauvegardé pour $_userId');
    } catch (e) {
      debugPrint('❌ [NotificationService] Erreur sauvegarde token: $e');
      // Cache local déjà écrit — le token sera re-tenté au prochain refreshTokenForUser()
    }
  }

  /// ✅ Forcer le rafraîchissement du token
  /// À appeler après login/signup pour garantir l'écriture
  Future<void> refreshTokenForUser() async {
    // ✅ FIX : Reset complet pour forcer la réécriture
    _lastSavedToken = null;
    _lastSavedUserId = null;
    await LocalCache.saveFcmToken('');
    await _refreshAndSaveToken();
  }

  /// ✅ Supprimer le token (déconnexion)
  Future<void> clearToken() async {
    if (_userId == null) return;

    try {
      await _firestore.collection('users').doc(_userId).update({
        'fcmToken': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      // ✅ FIX : Reset complet des caches à la déconnexion
      _lastSavedToken = null;
      _lastSavedUserId = null;
      _initializedForUserId = null;
      _handlersSetup = false;
      await LocalCache.saveFcmToken('');
      debugPrint('✅ [NotificationService] Token FCM supprimé');
    } catch (e) {
      debugPrint('❌ [NotificationService] Erreur suppression token: $e');
    }
  }

  /// ✅ Gérer les messages au premier plan
  void _handleForegroundMessage(RemoteMessage message) {
    debugPrint('📬 [Foreground] Notification: ${message.notification?.title}');
    debugPrint('   - Body: ${message.notification?.body}');
    debugPrint('   - Data: ${message.data}');
    _showLocalNotification(message);
  }

  /// ✅ Afficher une notification locale (pour foreground)
  Future<void> _showLocalNotification(RemoteMessage message) async {
    final String? type = message.data['type'] as String?;
    final String body  = message.notification?.body ?? '';

    final AndroidNotificationDetails androidDetails =
    AndroidNotificationDetails(
      'orders',
      'Commandes Nomade',
      channelDescription: 'Notifications pour vos commandes',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      // Style dépliable : sans lui, Android tronque à une ligne quel que soit
      // le texte reçu.
      styleInformation: BigTextStyleInformation(
        body,
        contentTitle: message.notification?.title,
      ),
    );

    final DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      // Rattache la notification à une catégorie enregistrée : c'est ce qui
      // rend le contenu dépliable et fait apparaître les actions.
      categoryIdentifier: _categoryFor(type),
      // Regroupe les notifications d'une même famille dans le centre iOS.
      threadIdentifier: _categoryFor(type),
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    final payload = jsonEncode({
      'type':    message.data['type'],
      'orderId': message.data['orderId'],
      'rideId':  message.data['rideId'],
    });

    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch % 100000,
      message.notification?.title ?? 'Nouvelle notification',
      body,
      details,
      payload: payload,
    );
  }

  /// ✅ Gérer les messages depuis background
  void _handleBackgroundMessage(RemoteMessage message) {
    debugPrint(
        '📬 [Background tap] Notification: ${message.notification?.title}');
    _handleMessageClick(message);
  }

  /// Traiter le click sur notification FCM (background tap / initial message)
  void _handleMessageClick(RemoteMessage message) {
    final type    = message.data['type']    as String?;
    final orderId = message.data['orderId'] as String?;
    final rideId  = message.data['rideId']  as String?;

    debugPrint('🔔 [NotificationService] Click type: $type');

    switch (type) {
      case 'order_ready_client':
      case 'order_update':
        if (orderId != null) _navigateToOrder(orderId);
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
        if (rideId != null) _navigateToRide(rideId);
        break;
      default:
        debugPrint('📋 [NotificationService] Type inconnu: $type');
    }
  }

  /// Navigation vers le suivi de commande (sans BuildContext)
  void _navigateToOrder(String orderId) {
    final nav = appNavigatorKey.currentState;
    if (nav == null) {
      debugPrint('⚠️ [NotificationService] Navigator non disponible');
      return;
    }
    debugPrint('🧭 [NotificationService] Navigation → commande $orderId');
    // Pousser la route nommée définie dans votre router.
    // Adapter le nom de route à votre configuration MaterialApp.
    nav.pushNamed('/order-tracking', arguments: {'orderId': orderId});
  }

  /// Navigation vers le suivi de course taxi
  void _navigateToRide(String rideId) {
    final nav = appNavigatorKey.currentState;
    if (nav == null) return;
    debugPrint('🧭 [NotificationService] Navigation → course $rideId');
    nav.pushNamed('/ride-tracking', arguments: {'rideId': rideId});
  }

  /// ✅ Vérifier si les notifications sont activées
  Future<bool> areNotificationsEnabled() async {
    try {
      final settings = await _messaging.getNotificationSettings();
      return settings.authorizationStatus == AuthorizationStatus.authorized;
    } catch (e) {
      debugPrint(
          '❌ [NotificationService] Erreur vérification permissions: $e');
      return false;
    }
  }

  /// ✅ S'abonner à un topic
  Future<void> subscribeToTopic(String topic) async {
    try {
      await _messaging.subscribeToTopic(topic);
      debugPrint('✅ [NotificationService] Souscrit au topic: $topic');
    } catch (e) {
      debugPrint(
          '❌ [NotificationService] Erreur abonnement topic $topic: $e');
    }
  }

  /// ✅ Se désabonner d'un topic
  Future<void> unsubscribeFromTopic(String topic) async {
    try {
      await _messaging.unsubscribeFromTopic(topic);
      debugPrint('✅ [NotificationService] Désabonné du topic: $topic');
    } catch (e) {
      debugPrint(
          '❌ [NotificationService] Erreur désabonnement topic $topic: $e');
    }
  }

  String? get fcmToken => _lastSavedToken;
}