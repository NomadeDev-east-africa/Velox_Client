import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/promo_banner.dart';

/// Accès aux bannières promotionnelles de l'accueil Food (collection `banners`).
///
/// Les bannières sont pilotées depuis l'admin : l'app ne fait que les lire, en
/// temps réel, pour qu'un changement soit visible sans nouvelle soumission
/// App Store.
class BannerService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Flux temps réel des bannières affichables, triées par `order` croissant.
  ///
  /// Le filtre `active == true` et le tri sont faits **côté client** et non dans
  /// la requête Firestore : un `where` + `orderBy` sur deux champs différents
  /// exigerait un index composite, pour un volume de documents négligeable.
  Stream<List<PromoBanner>> watchBanners() {
    return _db.collection('banners').snapshots().map((snapshot) {
      final banners = snapshot.docs
          .map(PromoBanner.fromFirestore)
          .where((b) => b.active && b.isRenderable)
          .toList()
        ..sort((a, b) => a.order.compareTo(b.order));
      return banners;
    });
  }
}
