import 'package:flutter/widgets.dart';

/// Nom de la route actuellement au sommet de la pile de navigation.
/// Alimenté par [RouteTracker] et lu par la pastille de suivi globale pour se
/// masquer sur les écrans de suivi (`/order-tracking`, `/ride-tracking`).
final ValueNotifier<String?> currentRouteName = ValueNotifier<String?>(null);

/// Observer branché sur `MaterialApp.navigatorObservers` : met à jour
/// [currentRouteName] à chaque changement de route. Les routes poussées sans
/// `settings.name` (la plupart des `Navigator.push(MaterialPageRoute(...))`)
/// remontent `null` — la pastille reste alors visible, ce qui est voulu
/// (accueil / fiche resto / panier / profil…).
class RouteTracker extends NavigatorObserver {
  void _update(Route<dynamic>? route) {
    if (route is PageRoute) {
      currentRouteName.value = route.settings.name;
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _update(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _update(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _update(newRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _update(previousRoute);
  }
}
