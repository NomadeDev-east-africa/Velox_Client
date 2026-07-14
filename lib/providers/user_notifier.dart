import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import '../services/hive_service.dart';
import '../services/notification_service.dart';
import '../utils/local_cache.dart';
import 'active_order_notifier.dart';
import 'active_ride_notifier.dart';
import 'address_notifier.dart';
import 'cart_notifier.dart';
import 'favorites_notifier.dart';

// ═══════════════════════════════════════════════════════════════
// ÉTAT
// ═══════════════════════════════════════════════════════════════

class UserState {
  final User? firebaseUser;
  final String? userId;
  final String? name;
  final String? email;
  final String? phone;
  final String? photoUrl;
  final Map<String, dynamic>? userData;
  final bool isLoading;
  final String? error;

  const UserState({
    this.firebaseUser,
    this.userId,
    this.name,
    this.email,
    this.phone,
    this.photoUrl,
    this.userData,
    this.isLoading = true,
    this.error,
  });

  // ─── Getters calculés ────────────────────────────────────────

  bool get isAuthenticated => firebaseUser != null;

  String get displayName {
    if (name != null && name!.isNotEmpty) return name!;
    if (firebaseUser?.displayName != null &&
        firebaseUser!.displayName!.isNotEmpty) {
      return firebaseUser!.displayName!;
    }
    if (email != null) return email!.split('@').first;
    return 'Utilisateur';
  }

  String? get displayPhotoUrl => photoUrl ?? firebaseUser?.photoURL;
  String? get displayPhone    => phone  ?? firebaseUser?.phoneNumber;
  bool   get isEmailVerified  => firebaseUser?.emailVerified ?? false;

  UserState copyWith({
    User? firebaseUser,
    String? userId,
    String? name,
    String? email,
    String? phone,
    String? photoUrl,
    Map<String, dynamic>? userData,
    bool? isLoading,
    String? error,
    // Permet de remettre firebaseUser à null explicitement
    bool clearFirebaseUser = false,
    bool clearError = false,
  }) {
    return UserState(
      firebaseUser: clearFirebaseUser ? null : (firebaseUser ?? this.firebaseUser),
      userId:    userId    ?? this.userId,
      name:      name      ?? this.name,
      email:     email     ?? this.email,
      phone:     phone     ?? this.phone,
      photoUrl:  photoUrl  ?? this.photoUrl,
      userData:  userData  ?? this.userData,
      isLoading: isLoading ?? this.isLoading,
      error:     clearError ? null : (error ?? this.error),
    );
  }

  UserState get cleared => const UserState(isLoading: false);
}

// ═══════════════════════════════════════════════════════════════
// NOTIFIER
// ═══════════════════════════════════════════════════════════════

class UserNotifier extends StateNotifier<UserState> {
  final FirebaseAuth      _auth      = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Ref _ref;

  StreamSubscription<User?>? _authSubscription;

  UserNotifier(this._ref) : super(const UserState()) {
    _initializeAuth();
  }

  // ─── INITIALISATION ──────────────────────────────────────────

  Future<void> _initializeAuth() async {
    if (!mounted) return;

    state = state.copyWith(isLoading: true);

    try {
      // Utilisateur déjà connecté au démarrage
      final currentUser = _auth.currentUser;
      if (currentUser != null) {
        await _loadUserData(currentUser);
      } else {
        state = state.copyWith(isLoading: false);
      }

      // Écouter les changements d'auth
      _authSubscription = _auth.authStateChanges().listen((User? user) async {
        if (!mounted) return;

        if (user != null) {
          await _loadUserData(user);
        } else {
          _clearUserData();
        }
      });
    } catch (e) {
      debugPrint('❌ [UserNotifier] _initializeAuth: $e');
      if (mounted) {
        state = state.copyWith(isLoading: false, error: e.toString());
      }
    }
  }

  // ─── CHARGEMENT DONNÉES ───────────────────────────────────────

  Future<void> _loadUserData(User firebaseUser) async {
    if (!mounted) return;

    try {
      final uid = firebaseUser.uid;
      final doc = await _firestore.collection('users').doc(uid).get();

      if (!mounted) return;

      if (doc.exists) {
        final data = doc.data()!;

        state = state.copyWith(
          firebaseUser: firebaseUser,
          userId:    uid,
          // ✅ 'name' en priorité (camelCase — AuthService écrit 'name')
          name:      data['name'] ?? data['displayName'] ?? firebaseUser.displayName,
          email:     data['email'] ?? firebaseUser.email,
          phone:     data['phone'] ?? firebaseUser.phoneNumber,
          // ✅ 'photoUrl' camelCase uniquement
          photoUrl:  data['photoUrl'] ?? firebaseUser.photoURL,
          userData:  data,
          isLoading: false,
          clearError: true,
        );

        // Persister userId en cache local (pour les providers qui en ont besoin)
        await LocalCache.saveUserId(uid);
        if (state.name != null) {
          await LocalCache.saveUserName(state.name!);
        }

        debugPrint('✅ [UserNotifier] Données chargées: ${state.displayName}');
      } else {
        // Pas de document Firestore → utiliser Firebase Auth
        state = state.copyWith(
          firebaseUser: firebaseUser,
          userId:    uid,
          name:      firebaseUser.displayName,
          email:     firebaseUser.email,
          phone:     firebaseUser.phoneNumber,
          photoUrl:  firebaseUser.photoURL,
          isLoading: false,
          clearError: true,
        );
        debugPrint('! [UserNotifier] Pas de doc Firestore, utilisation Firebase Auth');
      }
    } on FirebaseException catch (e) {
      debugPrint('❌ [UserNotifier] Firebase (${e.code}): ${e.message}');
      if (!mounted) return;
      final msg = e.code == 'unavailable'
          ? 'Pas de connexion réseau'
          : e.code == 'permission-denied'
              ? 'Accès refusé'
              : e.message ?? e.code;
      state = state.copyWith(
        firebaseUser: firebaseUser,
        userId:    firebaseUser.uid,
        name:      firebaseUser.displayName,
        email:     firebaseUser.email,
        phone:     firebaseUser.phoneNumber,
        photoUrl:  firebaseUser.photoURL,
        isLoading: false,
        error:     msg,
      );
    } catch (e) {
      debugPrint('❌ [UserNotifier] _loadUserData: $e');
      if (!mounted) return;

      // Fallback Firebase Auth
      state = state.copyWith(
        firebaseUser: firebaseUser,
        userId:    firebaseUser.uid,
        name:      firebaseUser.displayName,
        email:     firebaseUser.email,
        phone:     firebaseUser.phoneNumber,
        photoUrl:  firebaseUser.photoURL,
        isLoading: false,
        error:     e.toString(),
      );
    }
  }

  // ─── REFRESH ──────────────────────────────────────────────────

  Future<void> refresh() async {
    if (!mounted) return;
    debugPrint('🔄 UserNotifier - Refresh');

    final user = _auth.currentUser;
    if (user != null) {
      await _loadUserData(user);
    }
  }

  // ─── MISE À JOUR PROFIL ───────────────────────────────────────

  Future<void> updateProfile({
    String? name,
    String? phone,
    String? photoUrl,
    DateTime? birthDate,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Utilisateur non connecté');

    try {
      final updates = <String, dynamic>{};
      if (name      != null) updates['name']      = name;
      if (phone     != null) updates['phone']      = phone;
      if (photoUrl  != null) updates['photoUrl']   = photoUrl;
      if (birthDate != null) updates['birthDate']  = Timestamp.fromDate(birthDate);

      if (updates.isNotEmpty) {
        updates['updatedAt'] = FieldValue.serverTimestamp();
        await _firestore.collection('users').doc(user.uid).update(updates);

        if (name     != null) await user.updateDisplayName(name);
        if (photoUrl != null) await user.updatePhotoURL(photoUrl);
        await user.reload();

        await _loadUserData(_auth.currentUser!);
        debugPrint('✅ [UserNotifier] Profil mis à jour');
      }
    } catch (e) {
      debugPrint('❌ [UserNotifier] updateProfile: $e');
      if (mounted) state = state.copyWith(error: e.toString());
      rethrow;
    }
  }

  Future<String> uploadProfilePhoto(XFile image) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Utilisateur non connecté');

    final storageRef = FirebaseStorage.instance
        .ref()
        .child('profile_photos/${user.uid}.jpg');

    final bytes = await image.readAsBytes();
    await storageRef.putData(
      bytes,
      SettableMetadata(contentType: 'image/jpeg'),
    );
    final url = await storageRef.getDownloadURL();
    await updateProfile(photoUrl: url);
    debugPrint('✅ [UserNotifier] Photo uploadée: $url');
    return url;
  }

  // ─── LOGOUT ───────────────────────────────────────────────────

  /// Déconnexion complète avec nettoyage de toutes les données locales
  Future<void> logout() async {
    try {
      await NotificationService().clearToken();
      await _auth.signOut();

      // ✅ Vider les données métier Hive
      await HiveService.clearAllSession();

      // ✅ Vider le cache utilisateur SharedPreferences (garder darkMode/language)
      await LocalCache.clearUser();

      // ✅ Réinitialiser les providers liés au compte (sinon leur état en
      // mémoire — panier, course/commande active, favoris, adresses —
      // reste celui du compte précédent jusqu'au prochain hot restart).
      _ref.invalidate(cartProvider);
      _ref.invalidate(activeRideProvider);
      _ref.invalidate(activeOrderProvider);
      _ref.invalidate(favoritesNotifierProvider);
      _ref.invalidate(addressNotifierProvider);

      _clearUserData();
      debugPrint('✅ [UserNotifier] Déconnexion complète');
    } catch (e) {
      debugPrint('❌ [UserNotifier] logout: $e');
      if (mounted) state = state.copyWith(error: e.toString());
      rethrow;
    }
  }

  Future<void> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Utilisateur non connecté');

    try {
      // Auth first — if this throws requires-recent-login, Firestore est intact
      // et l'utilisateur peut se ré-authentifier et réessayer.
      await user.delete();
      await _firestore.collection('users').doc(user.uid).delete();
      await HiveService.clearAllSession();
      await LocalCache.clearUser();
      _ref.invalidate(cartProvider);
      _ref.invalidate(activeRideProvider);
      _ref.invalidate(activeOrderProvider);
      _ref.invalidate(favoritesNotifierProvider);
      _ref.invalidate(addressNotifierProvider);
      _clearUserData();
      debugPrint('✅ [UserNotifier] Compte supprimé');
    } catch (e) {
      debugPrint('❌ [UserNotifier] deleteAccount: $e');
      if (mounted) state = state.copyWith(error: e.toString());
      rethrow;
    }
  }

  Future<void> sendEmailVerification() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Utilisateur non connecté');
    try {
      await user.sendEmailVerification();
      debugPrint('✅ [UserNotifier] Email de vérification envoyé');
    } catch (e) {
      debugPrint('❌ [UserNotifier] sendEmailVerification: $e');
      if (mounted) state = state.copyWith(error: e.toString());
      rethrow;
    }
  }

  // ─── FIDÉLITÉ ─────────────────────────────────────────────────

  /// Incrémente les points fidélité dépensés (réduction appliquée au checkout).
  Future<void> redeemPoints(int points) async {
    final user = _auth.currentUser;
    if (user == null || points <= 0) return;
    try {
      await _firestore.collection('users').doc(user.uid).set(
        {'redeemedPoints': FieldValue.increment(points)},
        SetOptions(merge: true),
      );
      debugPrint('✅ [UserNotifier] $points points dépensés');
    } catch (e) {
      debugPrint('❌ [UserNotifier] redeemPoints: $e');
      rethrow;
    }
  }

  // ─── HELPERS ──────────────────────────────────────────────────

  void _clearUserData() {
    if (!mounted) return;
    state = const UserState(isLoading: false);
    debugPrint('🧹 [UserNotifier] Données utilisateur effacées');
  }

  void clearError() {
    if (mounted) state = state.copyWith(clearError: true);
  }

  T? getUserDataValue<T>(String key) {
    if (state.userData == null) return null;
    return state.userData![key] as T?;
  }

  bool hasRole(String role) {
    if (state.userData == null) return false;
    final roles = state.userData!['roles'] as List?;
    return roles?.contains(role) ?? false;
  }

  // ─── DISPOSE ──────────────────────────────────────────────────

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}

// ═══════════════════════════════════════════════════════════════
// PROVIDER GLOBAL
// Utilisation dans les screens :
//   ref.watch(userNotifierProvider)          → UserState
//   ref.read(userNotifierProvider.notifier)  → UserNotifier
// ═══════════════════════════════════════════════════════════════

final userNotifierProvider =
    StateNotifierProvider<UserNotifier, UserState>(
  (ref) => UserNotifier(ref),
);
