import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/promo_banner.dart';
import '../services/banner_service.dart';

final bannerServiceProvider = Provider<BannerService>((ref) => BannerService());

/// Bannières promo de l'accueil Food, en temps réel.
///
/// En erreur (invité non connecté, réseau) ou pendant le chargement, l'accueil
/// retombe sur sa bannière par défaut — cf. `_PromoBannerSection`.
final bannersProvider = StreamProvider<List<PromoBanner>>((ref) {
  return ref.watch(bannerServiceProvider).watchBanners();
});
