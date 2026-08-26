# TRAVAUX iOS — Partie 5 (25-26 août 2026)

Sessions couvrant la parité avec Android, les notifications persistées et
l'analyse des crashes. Builds **1.0.15 → 1.0.18** sur TestFlight.

> ⚠️ **Ce Mac est rendu après cette session.** Les builds iOS exigent
> macOS/Xcode : toute reprise nécessite une autre machine. Voir « Reprise sur
> une nouvelle machine » en fin de document.

---

## 1. Parité Android (prompt `docs/prompts/PROMPT_IOS_PARITY_SYNC.md`)

Six points répliqués depuis la branche Android `feature/ios-parity-preprod`.
Aucun changement backend : tout s'appuyait sur des collections et Cloud
Functions déjà déployées.

**Bannières admin** — `banners` lue en temps réel, tri par `order`, filtre
`active` côté client pour éviter un index composite. Rendus texte et image,
tap vers WhatsApp / URL / restaurant / catégorie. Texte auto-rétrécissant
avant ellipsis. Repli sur la bannière par défaut si rien d'actif, en
chargement, ou en erreur — le cas invité, `banners` exigeant `isAuth()`.

**Codes promo** — `promoCode` / `promoDiscount` sur `Order`, callable
`validatePromoCode`. Le `discountAmount` du serveur est affiché et stocké tel
quel, jamais recalculé. Le code s'efface dès que le panier change.

> Piège : `callable.call<Map<String, dynamic>>()` lève un cast error sur iOS,
> la réponse arrivant en `Map<Object?, Object?>`. Reconstruire la map
> explicitement.

**Widget de suivi** — fenêtre post-livraison 60 s → 8 s, comptée depuis
`deliveredAt` et non depuis la découverte de la commande : une commande
livrée puis restaurée depuis Hive réapparaissait au lancement.

**Historique** — la section courses VTC était absente alors que
`getUserRideHistory` existait, inutilisée. Ajoutée, avec en-têtes à compteur.

**Adresses au checkout** — le carnet d'adresses est proposé avant la carte.

**Tarifs VTC** — lecture temps réel de `config/taxiPricing`. `includedKm`
ajouté à `RideChoice` ; la formule manquait les km inclus. Le barème 500/650 à
135 FDJ/km a été retiré : il divergeait du serveur, qui recalcule
`estimatedFare`/`finalFare`, donc le prix affiché ne correspondait pas au prix
facturé.

> Fausse piste coûteuse : un écart de prix constaté entre Android et iOS a été
> attribué à la lecture Firestore. En réalité elle fonctionnait — le user
> testait un build antérieur. Vérifier la version installée AVANT de
> soupçonner le code. `test/taxi_pricing_test.dart` fige désormais
> l'invariant sur la forme réelle du document (1140 FDJ sur 5 km).

---

## 2. Notifications persistées

**Côté client** — `AppNotification`, `NotificationHistoryService`,
`notification_history_provider`, écran `notifications_screen.dart`, entrée
dans Profil → Historique & favoris avec pastille de non-lus.

**Côté backend** — spécifié dans `docs/prompts/PROMPT_NOTIFICATIONS_BACKEND.md`,
livré et déployé le 26/08 (`docs/prompts/RETOUR_NOTIFICATIONS_BACKEND.md`).
Collection `users/{uid}/notifications`, index, règles n'autorisant au client
que `read`/`readAt`, purge 90 jours, `aps.category` sur tous les envois.

Vérifié sur la donnée de production : forme conforme, et `read: true` avec
`readAt` renseigné prouve que le `markAsRead` du client passe bien les règles
déployées. Chaîne validée de bout en bout.

**Notifications dépliables** — `DarwinNotificationDetails()` était vide, donc
aucune catégorie : iOS n'affichait qu'une bannière tronquée. Trois catégories
enregistrées (`VELOX_ORDER` / `VELOX_RIDE` / `VELOX_PROMO`).
`BigTextStyleInformation` ajouté côté Android.

**Bug trouvé grâce à la vérification** — toutes les notifications de course
portent le `rideId` en `actionValue`, y compris « Course terminée », or
`TrackingScreen` suit la course *active* et ignore l'ID transmis. L'état est
désormais relu avant de naviguer.

**Limites connues du backend** : les campagnes promo arrivent en
`actionType: "none"` — l'écran admin n'a que titre et message. `order_update`
n'est émis par aucune fonction ; seul `order_ready_client` est persisté.

---

## 3. Crashes — le vrai diagnostic

Sept problèmes symbolisés (copies dans `docs/crashes-2026-08/`).

**Cinq sur sept n'étaient pas des plantages.** `main.dart` enregistrait toute
erreur Flutter via `recordFlutterFatalError` : les échecs réseau sur images
(`NetworkImage`, `cached_network_image`, tuiles `flutter_map`) comptaient
comme des crashes et noyaient les vrais bugs. Passé en `recordFlutterError`,
non-fatal ; les exceptions réellement non rattrapées restent fatales via
`runZonedGuarded`. `PlatformDispatcher.instance.onError`, absent, a été ajouté.

**Vrais bugs corrigés** — `getToken()` FCM levait une PlatformException non
capturée au démarrage ; `delivery_address_picker_screen` avait trois
`setState` sans garde `mounted`, dont celui du `catch`, seul crash constaté
sur 1.0.16.

**Phase de build dSYM** ajoutée au target Runner. Sans elle les symboles
étaient écrasés au build suivant, `flutter build ipa` réutilisant toujours
`build/ios/archive` — et Apple n'hébergeant plus les dSYM depuis la fin du
bitcode, les crashes d'une version publiée devenaient définitivement
illisibles.

> L'UUID du binaire `Runner` ne change pas tant qu'on ne touche qu'au Dart ;
> seul `App.framework` est régénéré à chaque build. C'est ce qui a permis de
> récupérer a posteriori un dSYM 1.0.14 réputé perdu.

**`test/widget_test.dart` supprimé** — boilerplate `flutter create` qui
cherchait le compteur du template et échouait depuis toujours. Suite
désormais entièrement verte (32 tests).

---

## 4. Reprise sur une nouvelle machine

À récupérer **avant** de rendre ce Mac, sans quoi c'est perdu :

1. **Certificat de distribution** — `Apple Distribution: HODA BARKHADLE
   (7XH7YBK9H6)`. La clé privée n'existe que dans le trousseau de ce Mac.
   Exporter un `.p12` depuis Trousseaux d'accès (clic droit sur le certificat
   → Exporter). Sans ça, il faudra révoquer et recréer le certificat.
2. **Clé API App Store Connect** — `AuthKey_8PN6V7YQBT.p8`, dans
   `~/.appstoreconnect/private_keys/`. Apple ne permet de la télécharger
   qu'une seule fois.

Déjà sauvegardé dans ce dépôt : `GoogleService-Info.plist`, la skill
`.claude/skills/velox-deploy/`, les prompts et les rapports de crash.

**Environnement** : Flutter + Xcode, `flutter pub get`, `pod install`, puis
connexion Firebase CLI (`firebase login`) si besoin d'inspecter la production.

**Particularités du réseau rencontré ici** : uploads `altool` interrompus par
des erreurs `-1005` — réessayés automatiquement, l'envoi aboutit ; résolutions
DNS ponctuellement en échec, prévoir des retries dans tout script réseau ;
`flutter run --profile` et `--debug` en sans-fil échouent faute de découverte
du service VM (mDNS), donc **pas de logs `debugPrint` sans câble USB** — le
mode release s'installe mais ne remonte pas les logs.

---

## 5. Restant à traiter

- **Contrat de repli des tarifs VTC** à arbitrer avec l'agent Android : côté
  iOS, un document ne renseignant que `basePrice` conserve 3 km inclus et
  200/km en dur. Si l'app chauffeur interprète un champ absent comme zéro, le
  même trajet serait estimé et facturé différemment.
- **Campagnes promo** sans action ni image tant que l'écran admin n'a pas les
  champs correspondants.
- **Effet du reclassement des erreurs** à observer sur les prochains jours :
  le compteur de plantages devrait chuter nettement.
