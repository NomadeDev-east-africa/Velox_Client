import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:nomade_client/services/notification_service.dart';

/// Service d'authentification Firebase — convention camelCase unifiée
class AuthService {
  final firebase_auth.FirebaseAuth _auth =
      firebase_auth.FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  // ✅ Référence au NotificationService singleton
  final NotificationService _notificationService = NotificationService();

  firebase_auth.User? getCurrentUser() => _auth.currentUser;

  Stream<firebase_auth.User?> get authStateChanges =>
      _auth.authStateChanges();

  /// Vérifie si l'utilisateur a un numéro de téléphone enregistré
  /// (nécessaire après une connexion Google/Apple, qui n'en fournit pas).
  Future<bool> hasPhoneNumber(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    final phone = doc.data()?['phone'];
    return phone is String && phone.trim().isNotEmpty;
  }

  // ════════════════════════════════════════════════════════════
  // CONNEXION Email + Password
  // ════════════════════════════════════════════════════════════

  Future<firebase_auth.User?> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      final user = credential.user;

      if (user != null) {
        // ✅ FIX : Mettre à jour lastActiveAt à chaque connexion
        await _firestore.collection('users').doc(user.uid).set({
          'lastActiveAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        // ✅ FIX : Initialiser les notifications pour ce user
        // Force la réécriture du token si user différent du précédent
        await _notificationService.initialize(user.uid);

        debugPrint('✅ [AuthService] Connexion: ${user.uid}');
      }

      return user;
    } on firebase_auth.FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  // ════════════════════════════════════════════════════════════
  // INSCRIPTION Email + Password
  // ════════════════════════════════════════════════════════════

  Future<firebase_auth.User?> signUpWithEmailPassword({
    required String email,
    required String password,
    required String name,
    String? phone,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      final user = credential.user;
      if (user != null) {
        await user.updateDisplayName(name);

        // ✅ Écriture camelCase — toutes les clés Firestore
        await _firestore.collection('users').doc(user.uid).set({
          'name': name,
          'email': email.trim(),
          'phone': phone,
          'photoUrl': null,
          'preferences': {
            'language': 'fr',
            'currency': 'FDJ',
            'notificationsEnabled': true,
            'darkMode': false,
          },
          'paymentMethods': [],
          'stats': {
            'totalTaxiRides': 0,
            'totalFoodOrders': 0,
            'totalSpentFdj': 0.0,
            'memberSince': FieldValue.serverTimestamp(),
          },
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'lastActiveAt': FieldValue.serverTimestamp(),
          'isActive': true,
          'isVerified': false,
        });

        // ✅ FIX BUG #3 : Forcer l'écriture du token FCM pour le nouveau user
        // refreshTokenForUser() reset les caches et force la réécriture
        // même si le token device est identique à l'ancien user
        await _notificationService.refreshTokenForUser();

        debugPrint('✅ [AuthService] User créé: ${user.uid}');
      }

      return user;
    } on firebase_auth.FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  // ════════════════════════════════════════════════════════════
  // CONNEXION Google
  // ════════════════════════════════════════════════════════════

  Future<firebase_auth.User?> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null;

      final auth = await googleUser.authentication;
      final credential = firebase_auth.GoogleAuthProvider.credential(
        accessToken: auth.accessToken,
        idToken: auth.idToken,
      );

      final userCredential = await _auth.signInWithCredential(credential);
      final user = userCredential.user;

      if (user != null) {
        await _createOrUpdateUserDocument(user);

        // ✅ FIX : Initialiser les notifications après Google Sign In
        await _notificationService.initialize(user.uid);

        debugPrint('✅ [AuthService] Google Sign In: ${user.uid}');
      }

      return user;
    } catch (e) {
      throw 'Erreur connexion Google: ${e.toString()}';
    }
  }

  // ════════════════════════════════════════════════════════════
  // CONNEXION Apple
  // ════════════════════════════════════════════════════════════

  Future<firebase_auth.User?> signInWithApple() async {
    try {
      final rawNonce = _generateNonce();
      final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();

      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );

      final oauthCredential = firebase_auth.OAuthProvider('apple.com').credential(
        idToken: appleCredential.identityToken,
        rawNonce: rawNonce,
        accessToken: appleCredential.authorizationCode,
      );

      final userCredential = await _auth.signInWithCredential(oauthCredential);
      final user = userCredential.user;

      if (user != null) {
        // Apple ne renvoie le nom qu'à la toute première autorisation —
        // on le récupère ici pour l'écrire dans Firebase avant que ce
        // soit perdu (les connexions suivantes ne le renverront plus).
        final fullName = [appleCredential.givenName, appleCredential.familyName]
            .whereType<String>()
            .join(' ')
            .trim();
        if (fullName.isNotEmpty &&
            (user.displayName == null || user.displayName!.isEmpty)) {
          await user.updateDisplayName(fullName);
        }

        await _createOrUpdateUserDocument(user);
        await _notificationService.initialize(user.uid);

        debugPrint('✅ [AuthService] Apple Sign In: ${user.uid}');
      }

      return user;
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) return null;
      throw 'Erreur connexion Apple: ${e.message}';
    } catch (e) {
      throw 'Erreur connexion Apple: ${e.toString()}';
    }
  }

  String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(length, (_) => charset[random.nextInt(charset.length)])
        .join();
  }

  // ════════════════════════════════════════════════════════════
  // CONNEXION Téléphone (OTP)
  // ════════════════════════════════════════════════════════════

  int? _resendToken;

  Future<void> signInWithPhone({
    required String phoneNumber,
    required Function(String verificationId) codeSent,
    required Function(firebase_auth.PhoneAuthCredential credential)
    verificationCompleted,
    required Function(String error) verificationFailed,
  }) async {
    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        timeout: const Duration(seconds: 60),
        verificationCompleted:
            (firebase_auth.PhoneAuthCredential credential) async {
          await _auth.signInWithCredential(credential);
          verificationCompleted(credential);
        },
        verificationFailed: (firebase_auth.FirebaseAuthException e) {
          verificationFailed(_handleAuthException(e));
        },
        codeSent: (String verificationId, int? resendToken) {
          _resendToken = resendToken;
          codeSent(verificationId);
        },
        codeAutoRetrievalTimeout: (_) {},
        forceResendingToken: _resendToken,
      );
    } catch (e) {
      throw 'Erreur envoi OTP: ${e.toString()}';
    }
  }

  // ════════════════════════════════════════════════════════════
  // VÉRIFIER code OTP
  // ════════════════════════════════════════════════════════════

  Future<firebase_auth.User?> verifyOTP({
    required String verificationId,
    required String smsCode,
  }) async {
    try {
      final credential = firebase_auth.PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode,
      );
      final userCredential = await _auth.signInWithCredential(credential);
      final user = userCredential.user;

      if (user != null) {
        await _createOrUpdateUserDocument(user);

        // ✅ FIX : Initialiser les notifications après OTP
        await _notificationService.initialize(user.uid);

        debugPrint('✅ [AuthService] OTP vérifié: ${user.uid}');
      }

      return user;
    } on firebase_auth.FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  // ════════════════════════════════════════════════════════════
  // RÉINITIALISER mot de passe
  // ════════════════════════════════════════════════════════════

  Future<void> resetPassword(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on firebase_auth.FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  // ════════════════════════════════════════════════════════════
  // DÉCONNEXION
  // ════════════════════════════════════════════════════════════

  Future<void> signOut() async {
    try {
      // ✅ FIX : Supprimer le token FCM AVANT la déconnexion
      // pour que l'ancien user ne reçoive plus de notifications
      await _notificationService.clearToken();
      debugPrint('✅ [AuthService] Token FCM supprimé avant déconnexion');
    } catch (e) {
      // Non bloquant — on continue la déconnexion même si ça échoue
      debugPrint('⚠️ [AuthService] Erreur suppression token FCM: $e');
    }

    try {
      await Future.wait([
        _auth.signOut(),
        _googleSignIn.signOut(),
      ]);
      debugPrint('✅ [AuthService] Déconnexion réussie');
    } catch (e) {
      debugPrint('❌ [AuthService] Erreur déconnexion: $e');
      rethrow;
    }
  }

  // ════════════════════════════════════════════════════════════
  // CRÉER OU METTRE À JOUR le document user
  // ════════════════════════════════════════════════════════════

  Future<void> _createOrUpdateUserDocument(
      firebase_auth.User user) async {
    final userDoc = _firestore.collection('users').doc(user.uid);
    final docSnapshot = await userDoc.get();

    if (!docSnapshot.exists) {
      // ✅ Nouveau document en camelCase
      await userDoc.set({
        'name': user.displayName ?? 'User',
        'email': user.email,
        'phone': user.phoneNumber,
        'photoUrl': user.photoURL,
        'preferences': {
          'language': 'fr',
          'currency': 'FDJ',
          'notificationsEnabled': true,
          'darkMode': false,
        },
        'paymentMethods': [],
        'stats': {
          'totalTaxiRides': 0,
          'totalFoodOrders': 0,
          'totalSpentFdj': 0.0,
          'memberSince': FieldValue.serverTimestamp(),
        },
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'lastActiveAt': FieldValue.serverTimestamp(),
        'isActive': true,
        'isVerified': user.emailVerified,
      });
      debugPrint('✅ [AuthService] Nouveau user créé: ${user.uid}');
    } else {
      // ✅ Mise à jour — camelCase
      await userDoc.update({
        'lastActiveAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        // ✅ FIX : Mettre à jour isVerified si email vérifié entre-temps
        'isVerified': user.emailVerified,
      });
      debugPrint('✅ [AuthService] User mis à jour: ${user.uid}');
    }
  }

  // ════════════════════════════════════════════════════════════
  // GESTION DES ERREURS
  // ════════════════════════════════════════════════════════════

  String _handleAuthException(firebase_auth.FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'Aucun compte trouvé avec cet email.';
      case 'wrong-password':
        return 'Mot de passe incorrect.';
      case 'invalid-email':
        return 'Email invalide.';
      case 'user-disabled':
        return 'Ce compte a été désactivé.';
      case 'email-already-in-use':
        return 'Cet email est déjà utilisé.';
      case 'weak-password':
        return 'Le mot de passe doit contenir au moins 6 caractères.';
      case 'invalid-verification-code':
        return 'Code de vérification invalide.';
      case 'invalid-verification-id':
        return 'Session expirée. Renvoyez le code.';
      case 'too-many-requests':
        return 'Trop de tentatives. Réessayez plus tard.';
      case 'operation-not-allowed':
        return 'Cette méthode de connexion n\'est pas activée.';
    // ✅ FIX : Ajout cas manquants fréquents
      case 'network-request-failed':
        return 'Erreur réseau. Vérifiez votre connexion.';
      case 'requires-recent-login':
        return 'Session expirée. Reconnectez-vous.';
      case 'credential-already-in-use':
        return 'Ce compte est déjà associé à un autre utilisateur.';
      case 'invalid-credential':
        return 'Identifiants invalides. Vérifiez vos informations.';
      default:
        return 'Erreur: ${e.message ?? e.code}';
    }
  }
}