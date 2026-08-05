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

  /// Vérifie si le compte a un numéro de téléphone RÉELLEMENT lié à Firebase
  /// Auth (provider `phone`), et non un simple champ Firestore.
  ///
  /// ⚠️ La source de vérité est `firebaseUser.phoneNumber`, PAS `users/{uid}.phone` :
  /// un numéro présent seulement en Firestore n'existe pas pour la connexion OTP,
  /// donc Firebase créait un NOUVEAU compte vide à la connexion par SMS (bug des
  /// « comptes fantômes »). `uid` n'est conservé que pour la compatibilité d'appel :
  /// on interroge toujours le compte actuellement connecté.
  Future<bool> hasPhoneNumber(String uid) async {
    final phone = _auth.currentUser?.phoneNumber;
    return phone != null && phone.trim().isNotEmpty;
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
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      final user = credential.user;
      if (user != null) {
        await user.updateDisplayName(name);

        // ✅ Écriture camelCase — toutes les clés Firestore.
        // `phone` reste null ici : un numéro n'est JAMAIS enregistré depuis un
        // simple champ (fuite « Firestore-seul » = comptes fantômes à l'OTP).
        // Il est lié à Firebase Auth via CompletePhoneScreen (linkPhoneCredential),
        // vers lequel l'inscription redirige juste après.
        await _firestore.collection('users').doc(user.uid).set({
          'name': name,
          'email': email.trim(),
          'phone': null,
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
  // SUPPRESSION DU COMPTE Auth
  // ════════════════════════════════════════════════════════════

  /// Supprime le compte Firebase Auth. À appeler EN DERNIER, après avoir
  /// supprimé les données Firestore : une fois le compte Auth détruit, le token
  /// n'est plus valide et toute écriture/suppression Firestore serait refusée.
  ///
  /// Firebase exige une connexion récente pour supprimer un compte : si le login
  /// est trop ancien, on ré-authentifie automatiquement via le provider d'origine
  /// puis on réessaie.
  Future<void> deleteAuthAccount() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Utilisateur non connecté');
    try {
      await user.delete();
    } on firebase_auth.FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        await _reauthenticate(user);
        await user.delete();
      } else {
        rethrow;
      }
    }
  }

  /// Ré-authentifie AVANT toute suppression, pour les providers qui le
  /// permettent silencieusement (Apple/Google). Ainsi, si l'utilisateur annule
  /// la fenêtre de reconnexion, la suppression est abandonnée AVANT toute perte
  /// de données (message d'erreur honnête). No-op pour téléphone/email : leur
  /// éventuelle reconnexion se fait dans deleteAuthAccount (cas rare).
  Future<void> reauthenticateForDeletion() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Utilisateur non connecté');
    final providers = user.providerData.map((p) => p.providerId).toSet();
    if (providers.contains('apple.com')) {
      await user.reauthenticateWithCredential(await _buildAppleCredential());
    } else if (providers.contains('google.com')) {
      await user.reauthenticateWithCredential(await _buildGoogleCredential());
    }
  }

  /// Ré-authentifie l'utilisateur via le provider avec lequel il s'est connecté.
  Future<void> _reauthenticate(firebase_auth.User user) async {
    final providers = user.providerData.map((p) => p.providerId).toSet();

    if (providers.contains('apple.com')) {
      await user.reauthenticateWithCredential(await _buildAppleCredential());
    } else if (providers.contains('google.com')) {
      await user.reauthenticateWithCredential(await _buildGoogleCredential());
    } else {
      // Téléphone / email : pas de reconnexion silencieuse possible ici.
      throw 'Pour supprimer votre compte, reconnectez-vous puis réessayez.';
    }
  }

  Future<firebase_auth.OAuthCredential> _buildAppleCredential() async {
    final rawNonce = _generateNonce();
    final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();
    final appleCredential = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: hashedNonce,
    );
    return firebase_auth.OAuthProvider('apple.com').credential(
      idToken: appleCredential.identityToken,
      rawNonce: rawNonce,
      accessToken: appleCredential.authorizationCode,
    );
  }

  Future<firebase_auth.AuthCredential> _buildGoogleCredential() async {
    // signOut force le sélecteur de compte → jeton frais pour la reconnexion.
    await _googleSignIn.signOut();
    final googleUser = await _googleSignIn.signIn();
    if (googleUser == null) throw 'Reconnexion annulée';
    final auth = await googleUser.authentication;
    return firebase_auth.GoogleAuthProvider.credential(
      accessToken: auth.accessToken,
      idToken: auth.idToken,
    );
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
  // LIER un numéro au compte COURANT (Google/Apple/email) via OTP
  // ════════════════════════════════════════════════════════════

  /// Envoie un SMS pour LIER le numéro au compte déjà connecté — contrairement
  /// à [signInWithPhone] qui, lui, ouvre/crée une session téléphone. Ici on ne
  /// fait JAMAIS de `signInWithCredential` : sur auto-récupération (Android) on
  /// lie directement via [linkPhoneCredential], sinon le code passe par
  /// [codeSent] et l'écran finalise avec [linkPhoneCredential].
  Future<void> verifyPhoneForLinking({
    required String phoneNumber,
    required Function(String verificationId) codeSent,
    required Function(String error) verificationFailed,
    Function()? autoLinked,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      verificationFailed('Session expirée. Reconnectez-vous.');
      return;
    }
    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        timeout: const Duration(seconds: 60),
        verificationCompleted:
            (firebase_auth.PhoneAuthCredential credential) async {
          try {
            await linkPhoneCredential(credential);
            autoLinked?.call();
          } catch (e) {
            verificationFailed(e.toString());
          }
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
      verificationFailed('Erreur envoi OTP: ${e.toString()}');
    }
  }

  /// Lie (1er numéro → `linkWithCredential`) ou remplace (numéro déjà présent →
  /// `updatePhoneNumber`) le numéro sur le compte COURANT, puis reflète
  /// `user.phoneNumber` dans Firestore (affichage). La source de vérité reste
  /// Firebase Auth. Lève un message clair si le numéro appartient à un autre
  /// compte (`credential-already-in-use`).
  Future<void> linkPhoneCredential(
      firebase_auth.PhoneAuthCredential credential) async {
    final user = _auth.currentUser;
    if (user == null) throw 'Session expirée. Reconnectez-vous.';
    try {
      final hasPhoneProvider =
          user.providerData.any((p) => p.providerId == 'phone');
      if (hasPhoneProvider) {
        await user.updatePhoneNumber(credential);
      } else {
        await user.linkWithCredential(credential);
      }
      await user.reload();
      final linked = _auth.currentUser;
      if (linked?.phoneNumber != null &&
          linked!.phoneNumber!.trim().isNotEmpty) {
        await _firestore.collection('users').doc(linked.uid).set(
          {
            'phone': linked.phoneNumber,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }
      debugPrint('✅ [AuthService] Numéro lié au compte: ${linked?.uid}');
    } on firebase_auth.FirebaseAuthException catch (e) {
      if (e.code == 'credential-already-in-use' ||
          e.code == 'account-exists-with-different-credential' ||
          e.code == 'phone-number-already-exists') {
        throw 'Ce numéro est déjà lié à un autre compte.';
      }
      if (e.code == 'provider-already-linked') {
        // Déjà un provider `phone` mais détection ratée : on remplace.
        await user.updatePhoneNumber(credential);
        await user.reload();
        return;
      }
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
  // RÉCUPÉRATION mot de passe par SMS (OTP)
  // ════════════════════════════════════════════════════════════

  /// Envoie un code OTP SANS ouvrir de session automatiquement (contrairement à
  /// [signInWithPhone]) : `verificationCompleted` est volontairement un no-op,
  /// l'utilisateur saisit le code puis on finalise via [signInForPasswordRecovery].
  Future<void> sendOtpCode({
    required String phoneNumber,
    required Function(String verificationId) codeSent,
    required Function(String error) verificationFailed,
  }) async {
    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (_) {},
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
      verificationFailed('Erreur envoi OTP: ${e.toString()}');
    }
  }

  /// Connexion OTP dédiée à la RÉCUPÉRATION de mot de passe. Le compte visé doit
  /// posséder un provider email/mot de passe. Si le numéro n'est rattaché à aucun
  /// tel compte, l'OTP créerait un compte fantôme : on le supprime aussitôt et on
  /// lève une erreur claire (jamais de compte vide généré par une récupération).
  Future<firebase_auth.User> signInForPasswordRecovery({
    required String verificationId,
    required String smsCode,
  }) async {
    final credential = firebase_auth.PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode,
    );
    final result = await _auth.signInWithCredential(credential);
    final user = result.user!;
    final hasPassword =
        user.providerData.any((p) => p.providerId == 'password');
    final isNew = result.additionalUserInfo?.isNewUser ?? false;

    if (!hasPassword || user.email == null) {
      if (isNew) {
        // Compte fantôme fraîchement créé par cet OTP → suppression immédiate.
        try {
          await user.delete();
        } catch (_) {}
      }
      await _auth.signOut();
      throw 'Aucun compte avec mot de passe n\'est associé à ce numéro. '
          'Connectez-vous plutôt avec le téléphone, ou utilisez la voie email.';
    }
    return user;
  }

  /// Définit un nouveau mot de passe sur le compte connecté (après OTP de
  /// récupération). Nécessite une authentification récente — assurée par l'OTP.
  Future<void> setNewPassword(String newPassword) async {
    final user = _auth.currentUser;
    if (user == null) throw 'Session expirée. Recommencez la vérification.';
    try {
      await user.updatePassword(newPassword);
    } on firebase_auth.FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        throw 'Session expirée. Recommencez la vérification par SMS.';
      }
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
      // ✅ Mise à jour — camelCase.
      // `isVerified` est volontairement exclu : il n'est PAS dans la whitelist
      // onlyFields() des règles Firestore (anti-triche — un utilisateur ne peut
      // pas se déclarer vérifié). L'inclure faisait échouer tout l'update avec
      // permission-denied à chaque reconnexion Apple/Google d'un compte existant.
      await userDoc.update({
        'lastActiveAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
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