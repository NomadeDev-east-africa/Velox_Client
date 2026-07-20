# Travaux iOS — Velox (session 4 : corrections UI/UX post-soumission)

> Fait suite à `travauxIos.md` (session 1), `TRAVAUXIOS2.md` (sessions 2-4),
> `travauxIOSfinal.md` (soumission App Store) et `TRAVAUXIOS3.md` (rejet Apple +
> corrections). Cette session couvre une grosse série de corrections UI/UX et de bugs
> remontés en testant sur device réel (iPhone mus + un 2e iPhone), après la validation
> de l'app par Apple. Deux versions TestFlight livrées : **1.0.6** puis **1.0.7**.

---

## 1. Texte "Livraison gratuite" → "500 FDJ" (build 1.0.6)

La livraison n'est pas gratuite (500 FDJ) mais le texte l'affichait comme telle à
plusieurs endroits :
- Bannière promo accueil (`promotion_banner.dart`) : clé `free_delivery` corrigée dans
  les 5 langues (`fr/en/ar/so/aa.dart`) ; clé `free_delivery_desc` (manquante partout,
  affichait le nom brut de la clé à l'écran) ajoutée dans les 5 langues.
- Cartes restaurant grande et moyenne : "Free"/"Paid"/"Free delivery" → "500 FDJ" en dur.
- Page détail restaurant (`restaurant_info.dart`) : clé `free` ("Gratuit") → "500 FDJ".

## 2. Icône Apple invisible sur le bouton de connexion (build 1.0.6)

`social_button.dart` place l'icône dans un badge blanc de 28×28 (12×12 utile après
padding). `Icon(Icons.apple)` ne se redimensionne pas comme les SVG (Facebook/Google)
et débordait hors du badge à taille 22 → apparaissait décalée. Fix : couleur passée en
noir puis icône enveloppée dans un `FittedBox` pour se redimensionner et se centrer
comme les autres icônes.

## 3. Catégories : navigation corrigée vers une vraie liste multi-restaurants (1.0.6)

Cliquer sur une catégorie (accueil, écran "Voir tout" → "By Categories", ou recherche)
ouvrait la page d'**un seul restaurant** tiré au hasard (celui du plat représentatif
choisi pour l'illustration). Créé `CategoryItemsScreen`
(`home_food/category_items_screen.dart`) : liste tous les plats de la catégorie, tous
restaurants confondus (nom du restaurant affiché au-dessus de chaque plat). Branché
depuis :
- `_CategoryRow` sur l'accueil
- `CategoryCard` sur l'écran "By Categories" (le nom du restaurant affiché sur la
  vignette a aussi été retiré)
- Nouvelle section "Catégories" ajoutée aux résultats de `FoodSearchScreen` (recherche
  élargie : catégorie + restaurant + plats, le matching plat inclut aussi sa catégorie)

## 4. Recherche scopée au restaurant (1.0.6)

L'icône recherche sur la page détail restaurant ouvrait la recherche **globale** de
restaurants (`SearchScreen`, aujourd'hui code mort). Créé `RestaurantMenuSearchScreen`
(`details/restaurant_menu_search_screen.dart`) : recherche uniquement parmi les plats
du restaurant courant. `SearchForm` a reçu un paramètre `hintText` optionnel. **Bug
corrigé après premier test** : l'écran n'avait pas d'`AppBar` donc pas de bouton retour
visible — ajouté avec le nom du restaurant en titre.

## 5. Ménage UI accueil (1.0.6)

- "VOIR TOUT" retiré de la section "Meilleurs choix" (`_sectionHeader` : `onTap` passé
  en optionnel, le bouton ne s'affiche que s'il est fourni).
- Icônes "Portefeuille"/"Paiements" (toutes deux "coming soon", non fonctionnelles)
  retirées des actions rapides — seule "Historique" reste.

## 6. Prix VTC : 200 FDJ/km (1.0.6)

`mock_taxi_data.dart` : `pricePerKm` des deux véhicules (Standard, Confort) passé de
50/70 à **200** FDJ/km (`basePrice` inchangé : 500/650 FDJ).

## 7. Restaurants favoris (cœur) + bug Firestore (1.0.6)

L'infrastructure existait déjà (`favorites_notifier.dart`, page
`favorite_restaurants_screen.dart` dans le profil) mais aucun bouton cœur n'était
présent en dehors des listes accueil. Ajouté sur la page détail restaurant et les
résultats de recherche.

**Bug découvert en testant sur device réel** : le cœur se remplissait un instant au tap
puis revenait vide, rien n'était sauvegardé. Cause réelle : règle de sécurité
Firestore — `match /users/{userId} { allow update: ... && onlyFields([...]) }` ne
contenait pas `favoriteRestaurants` dans la liste blanche des champs modifiables.
**Résolu par un agent externe** (celui qui gère le déploiement réel de
`firestore.rules`, prompt de handoff fourni dans la session) — confirmé fonctionnel
après déploiement et retest.

## 8. Build & upload TestFlight 1.0.6

`flutter build ipa --release` puis `xcrun altool --upload-app` (clé API existante,
Key ID `8PN6V7YQBT`) → **UPLOAD SUCCEEDED**, Delivery UUID
`e0e3ddf1-9b51-41e7-a543-8c44d7c2e18f`. Signature Apple Distribution + `aps-environment
production` + `applesignin` vérifiés avant envoi. Commit + push sur `feature/design-
review` puis fast-forward de `main` (les deux branches étaient déjà quasiment
synchronisées, `main` avait juste pris du retard sur plusieurs commits antérieurs).

---

## 9. Deuxième lot de corrections (build 1.0.7)

### 9.1 Footer accueil
"VELOX — SERVICE NATIONAL DJIBOUTIEN V1.0.0" → **"VELOX Corp since 2026"**.

### 9.2 Bug des 200 FDJ de livraison (confirmation + suivi de commande)
Cause exacte trouvée : `order_details_screen.dart` avait `const deliveryFee = 200.0;`
codé en dur, utilisé uniquement pour l'affichage de l'écran de confirmation (countdown
60s) — alors que la commande **persistée** dans Firestore utilisait déjà
`cart.deliveryFee` (500, correct) via `CartNotifier.createOrder()`. Fix : une ligne,
`final deliveryFee = cartState.deliveryFee.toDouble();`. Le bug était donc purement
cosmétique sur l'écran de countdown, pas une corruption de données.

### 9.3 Écran "Ajouter au panier" — tri des sections + plafond sauces + animations
Point d'architecture important : les groupes d'options (Formule/Taille, Sauces,
Légumes, Suppléments) sont **100% pilotés par Firestore** (`menuItem.optionGroups`),
configurés librement par chaque restaurant via une app admin séparée — le client ne
doit jamais présumer du nom/de l'existence d'un groupe. Décision utilisateur : trier
par reconnaissance de mots-clés (accent-insensible) uniquement parmi les groupes
réellement présents sur le plat, sans en injecter de manquants ; les groupes non
reconnus vont à la fin.
- `_categoryPriority()` : formule/taille/format/size → 0, sauce → 1, légume/veget → 2,
  supplément/extra → 3, sinon → 4 (fin de liste). Tri stable (ordre d'origine conservé
  entre groupes de même priorité).
- Plafond de **2 sauces incluses max** : `_toggleChoice` bloque la 3e sélection sur un
  groupe dont le nom contient "sauce", avec un SnackBar invitant à voir les
  Suppléments.
- Transitions de couleur fluides : `Container` → `AnimatedContainer` (220ms,
  `Curves.easeOut`) sur la ligne de choix et le radio/checkbox ; `Text` → 
  `AnimatedDefaultTextStyle` pour le libellé et le prix.
- **Bug remonté après test** : le SnackBar "Maximum 2 sauces..." et celui "Veuillez
  choisir..." étaient illisibles (texte blanc sur fond blanc en thème clair, texte noir
  sur fond noir en thème sombre) — aucune couleur explicite sur le `Text`, alors que le
  `backgroundColor` était bien `_c.surfaceHigh` (theme-aware). Fix : `style:
  TextStyle(color: _c.onSurface)` ajouté aux deux.

### 9.4 Icône dollar → pièce neutre
`assets/icons/delivery.svg` (littéralement un "$" dans un cercle) utilisé à côté de
"500 FDJ" sur la page détail restaurant et la carte restaurant (recherche). Remplacé
par `Icon(Icons.toll_rounded, color: kNeonGreen)` — **attention** : `Icons.
monetization_on_rounded` a été essayé en premier mais dessine *aussi* un "$" dessus
(remonté par l'utilisateur après un premier test) ; `Icons.toll` est le bon choix
(pièce/jeton neutre, sans symbole de devise). `DeliveryInfo` (dans `restaurant_info.
dart`) refactorée pour accepter un `Widget icon` au lieu d'un `String iconSrc`, pour
pouvoir mixer Icon Material et SvgPicture selon le cas.

### 9.5 Onglets catégories illisibles en thème sombre
`iteams.dart` (onglets Tous/Salades/Nos Viandes... sur la page détail restaurant) :
`unselectedLabelColor: titleColor` — `titleColor` est une constante fixe
`Color(0xFF212529)` (quasi-noir), invisible sur fond sombre. Remplacé par
`Theme.of(context).colorScheme.onSurfaceVariant` (theme-aware). Vérifié qu'aucun autre
`TabBar`/`SnackBar` de l'app n'a le même défaut (le reste avait déjà été migré vers
`AppColors` lors d'une session précédente — cf. `travauxIOSfinal.md` section 3). Un
usage de `titleColor`/`bodyTextColor` dans `lib/screens/food/filter/` existe mais ce
dossier est du **code mort** (aucune référence ailleurs dans l'app), donc non corrigé
(pas de risque utilisateur).

### 9.6 "12 rides" codé en dur sur l'accueil
`home_screen_app.dart` affichait littéralement `_buildStatItem('12', ...)`. Vérifié :
le champ `users/{uid}.stats.totalTaxiRides` n'est **jamais incrémenté nulle part** (ni
client, ni Cloud Functions) — resterait à 0 pour toujours de toute façon. Remplacé par
un vrai comptage temps réel : nouveau `completedRidesCountProvider`
(`order_stats_provider.dart`), `StreamProvider.autoDispose` sur
`taxiRides` filtré par `userId` + `status == 'completed'`, même pattern que
`orderStatsProvider` pour les commandes.

### 9.7 Moyens de paiement : BCI, EXIM Bank, Dahab+
Ajoutés aux listes existantes (cash, Waafi, D-Money, CAC Pay) dans
`order_details_screen.dart` (food) et `ride_confirmation_screen.dart` (VTC). Bug
additionnel trouvé et corrigé au passage : `order_history_screen.dart::_paymentLabel`
retombait sur "Espèces" par défaut pour toute méthode non reconnue (une commande payée
par BCI se serait affichée "Espèces" dans l'historique) — cases ajoutées pour les 3
nouvelles méthodes.

### 9.8 Numéro de téléphone obligatoire
Le champ téléphone était **optionnel** même à l'inscription par email, et totalement
absent pour Google/Apple.
- `sign_up_form.dart` : champ rendu obligatoire (validator).
- Nouvel écran bloquant `complete_phone_screen.dart` (`PopScope(canPop: false)`,
  pas de bouton retour) : demande le numéro, l'enregistre sur `users/{uid}.phone`
  (déjà dans la liste blanche `onlyFields` des règles Firestore, aucun fix de règles
  nécessaire ici), puis navigue vers `HomeScreenApp`.
- `AuthService.hasPhoneNumber(uid)` : nouvelle méthode vérifiant le champ Firestore.
- Branché après connexion Google **et** Apple, dans `sign_in_screen.dart` **et** dans
  `sign_up_screen.dart` (qui a sa propre implémentation Google dupliquée) : si pas de
  numéro, redirige vers `CompletePhoneScreen` au lieu de `HomeScreenApp`.
- **Renforcement demandé par l'utilisateur** après un premier test : bloquer aussi au
  moment de "Commander" (food, `order_details_screen.dart::_processOrder`) et
  "Confirmer la course" (VTC, `ride_confirmation_screen.dart::_confirmRide`), pas
  seulement à la connexion — pour couvrir les comptes créés avant cette fonctionnalité.

### 9.9 Bug critique : données de l'ancien compte visibles après changement de compte
**Remonté par l'utilisateur** : déconnexion puis reconnexion avec un autre compte →
le panier/checkout affichait encore les données du compte précédent.

Cause racine : `UserNotifier.logout()` vidait bien le stockage persistant
(`HiveService.clearAllSession()`, `LocalCache.clearUser()`) mais **jamais l'état en
mémoire** des autres providers Riverpod (`cartProvider`, `activeRideProvider`,
`activeOrderProvider`, `favoritesNotifierProvider`, `addressNotifierProvider`) — ces
`StateNotifier` restent vivants en mémoire tant que l'app tourne, indépendamment du
vidage de leur backing store. `UserNotifier` ne détenait même pas de `Ref` pour
pouvoir les invalider.

Fix :
- `UserNotifier` prend maintenant un `Ref` en constructeur
  (`UserNotifier(this._ref) : super(...)`, provider mis à jour en conséquence).
- `logout()` **et** `deleteAccount()` appellent `_ref.invalidate(...)` sur les 5
  providers ci-dessus après avoir vidé Hive/LocalCache — Riverpod les recrée entièrement
  au prochain accès, garantissant un état 100% frais pour le nouveau compte.
- `orderStatsProvider`/`redeemedPointsProvider`/`completedRidesCountProvider` n'ont pas
  eu besoin de fix : ils sont `.autoDispose` et re-`watch()` déjà `userId` de façon
  réactive.

### 9.10 Build & upload TestFlight 1.0.7
Même procédure que 1.0.6 : signature Apple Distribution vérifiée, `flutter build ipa
--release`, upload via `xcrun altool` → **UPLOAD SUCCEEDED**, Delivery UUID
`266330e1-4187-480c-a662-2268c1ec8fa2`. Commit détaillé + push sur `feature/design-
review` puis fast-forward de `main`.

---

# PARTIE 2 — sessions suivantes (nouvelle marque + VTC + garde-fous)

> Grosse série entamée après la 1.0.7 : refonte du logo, 7 corrections UI, module
> VTC (prix réel, GPS, suivi chauffeur), boissons incluses, puis un lot de bugs
> critiques (login Apple, suppression de compte, resto fermé). Deux builds :
> **1.0.8** livrée sur TestFlight ; le lot de bugs suivant est buildé/testé sur
> device mais **pas encore** sur TestFlight (voir section « En attente »).

## 11. Nouveau logo + icône d'app

Le client a fourni 2 JPEG (dans `assets/images/`) : `logo-velox-ios.jpeg` (« V »
blanc/argent 3D, contour vert néon, fond noir, 1254²) et `velox-logo-BG.jpeg` (même
logo, fond clair `#F7F7F7`, 1024²). C'est une **nouvelle identité** (l'ancien
`logo-velox.png` était un « V » vert plat avec le mot « Velox »).

- **Logo in-app transparent** : `velox-logo-BG.jpeg` détouré en PNG transparent
  `assets/images/velox-logo-sansBG.png` (512²). Méthode (script Pillow+numpy dans le
  scratchpad) : le fond était parfaitement uniforme (`#F7F7F7` au pixel près), donc
  flood-fill depuis les 4 coins (préserve les zones claires *internes* du logo qu'un
  seuil global percerait), + dé-multiplication des bords anti-aliasés (sinon halo
  clair sur thème sombre) + suppression du bruit JPEG (sinon bavures grises).
  Testé composé sur `#F5F5F5`/`#0E0E0E`/blanc/vert de marque → aucun halo. Branché sur
  home (`home_screen_app.dart`), signup (`sign_up_screen.dart`) et loader
  (`velox_loader.dart`) — les 3 pointaient encore sur l'ancien logo.
- **Icône d'app** : `logo-velox-ios.jpeg` → PNG 1024 **opaque** (Apple refuse toute
  transparence) `logo-velox-ios-icon.png`, mis en `image_path` de
  `flutter_launcher_icons`. Régénéré (21 tailles iOS, 0 alpha vérifié). Masque
  arrondi iOS simulé : 0 pixel du logo rogné. **Réparé au passage** :
  `adaptive_icon_foreground` pointait vers `logo_velox.webp` **inexistant** dans
  `assets/images/` → remplacé par `velox-logo-adaptive-fg.png` (logo cadré à 57%
  pour la zone sûre du masque circulaire Android).

## 12. Sept corrections UI (dans la 1.0.8)

1. **« VOIR TOUT » retiré** au-dessus de « All restaurants » (`home_screen_food.dart`,
   suppression du `onTap` → `_sectionHeader` masque le bouton sans callback).
2. **Auto-complétion OTP** (`otp_form.dart` réécrit) : `AutofillGroup` +
   `autofillHints: [AutofillHints.oneTimeCode]` → la suggestion « Depuis Messages »
   apparaît. Deux blocages levés en plus du hint : `maxLength: 1` **tronquait** les 6
   chiffres collés par iOS (retiré), et `obscureText` masquait le code (retiré). Ajout
   de la répartition auto des 6 chiffres sur les cases.
3. **+253 en dur partout** : nouveau widget partagé
   `lib/components/inputs/djibouti_phone.dart` (préfixe 🇩🇯 +253 figé, formatters
   chiffres/max 8/espacement, validation, conversion E.164). Appliqué à
   `phone_login_screen` (refactorisé, ses classes privées supprimées),
   `complete_phone_screen`, `signUp/components/sign_up_form`, `edit_profile_screen`.
   **Changement de données** : les numéros sont désormais toujours stockés en
   `+253XXXXXXXX` (avant : texte brut sur 2 écrans). `edit_profile` reconvertit
   l'existant en chiffres locaux pour le pré-remplissage (pas de +253 en double).
4. **Logo sur signup** (voir section 11).
5. **Lien site** dans Profil → À propos : ouvre `https://veloxdj.com` (url_launcher,
   externe). Sous-titre `veloxdj.com`.
6. **« + clim » vert** sous « Taxi Confort » uniquement (`ride_choice_card.dart`,
   `drapeauVert` / `kNeonGreenDark` si sélectionné). « Climatisation » retirée des
   features du Standard (`mock_taxi_data.dart`).
7. **25 min → 35 min** sur les cartes resto (Meilleurs choix + All restaurants).

## 13. Module VTC (dans la 1.0.8)

**Tarifs** (`mock_taxi_data.dart`, via `RideChoice.calculatePrice`) : Standard
500 + 200/km, Confort 650 + 200/km → **0,2 FDJ/mètre**.

- **Prix sur distance ROUTIÈRE** : `_setDestination` (`taxi_home_screen.dart`)
  utilisait la distance à vol d'oiseau (Haversine) → sous-facturation de ~30% en
  ville. Basculé sur `LocationService.getRoute()` (OpenRouteService, clé configurée).
  Estimation immédiate à vol d'oiseau puis remplacée par la vraie distance ; bouton
  « Confirmer » désactivé pendant le calcul (pas de validation sur un prix qui bouge).
- **Blocage GPS** : `getCurrentLocation` **avalait** l'exception → l'écran taxi posait
  silencieusement « Centre-ville, Djibouti » comme départ (course facturée depuis un
  faux point). Erreur typée (`LocationFailure` dans `location_service.dart`), repli
  silencieux supprimé, écran de blocage avec bouton vers les réglages iOS + relance
  auto au retour au premier plan (`WidgetsBindingObserver`).
- **Carte chauffeur** (`tracking_screen.dart`) : ajout **plaque** (lue sur
  `drivers/{id}.licensePlate` — pas sur la course, `Ride.vehicleId` est null) +
  bouton **« SUIVRE »** ouvrant `track_driver_screen.dart` (nouveau, décalqué sur le
  suivi livreur : position temps réel `drivers/{id}.currentLocation`, vraie route,
  recalcul si déplacement > 40 m ; cible le pickup avant course, la destination après).

## 14. Boissons incluses avec la formule « Menu »

`add_to_order_screen.dart`. Un groupe d'options nommé « Boissons » reste **masqué**
tant que le choix « menu » n'est pas coché dans un groupe « Formule ». Data-driven :
si le plat n'a pas de groupe boissons, rien ne s'affiche.

- **Bug de détection (corrigé)** : le déclencheur testait `choix == 'Menu'` en exact
  sensible à la casse. Vérifié sur les vraies données (lecture REST de `menuItems`,
  public read) : « Tacos Cordon Bleu XL » chez KPB a un groupe **« formule »** avec
  choix **« menu » en minuscule** et un groupe **« Boissons »** (Coca/Sprite/Fanta).
  Corrigé → `_isMenuChoice` compare via `_normalize` (insensible casse/accents ;
  « Menu Maxi » ne déclenche pas). **Confirmé fonctionnel** sur device.
- Pièges désamorcés : sélection boisson oubliée quand on quitte « menu » ;
  présélection d'un groupe boissons `required` masqué vidée à l'init ; validation
  ignore les groupes masqués. Groupe boissons trié juste après la formule.

## 15. Lot de bugs critiques (buildé/testé device — PAS encore sur TestFlight)

### 15.1 Login iOS — `permission-denied` à la reconnexion Apple/Google
`AuthService._createOrUpdateUserDocument` écrivait `isVerified` dans l'`update()` d'un
compte existant. Ce champ **n'est pas** dans la whitelist `onlyFields()` des règles
`users` déployées (anti-triche) → tout l'update rejeté. Un **nouveau** compte passait
(`.set()`), mais la **2e** connexion échouait. Fix : `isVerified` retiré de l'update
(côté client, aucun changement de règles nécessaire).

### 15.2 Bouton Facebook retiré du `sign_in_screen` (Apple + Google conservés).

### 15.3 Suppression de compte impossible — ordre inversé
`UserNotifier.deleteAccount` appelait `user.delete()` (Auth) **avant** la suppression
Firestore → token invalidé → `isAuth()` faux → suppression du doc refusée, doc
orphelin. Fix : Firestore d'abord (sous-collections `addresses/` + `favorite_drivers/`
puis le doc, pas de cascade), Auth en dernier. Nouveau `AuthService.deleteAuthAccount()`
avec **reconnexion auto** Apple/Google si Firebase exige un login récent
(`requires-recent-login`).

### 15.4 Commande possible vers un restaurant fermé
Vérifié : **rien** ne bloquait. `isOpen` servait juste à afficher un badge ; les
`openingHours` n'étaient même pas lus. **Cloud Function déployée `updateRestaurantOpenStatus`**
(absente du `functions/index.js` local) recalcule `isOpen` **toutes les 5 min en heure
de Djibouti** selon les horaires — `isOpen` est donc la source de vérité « ouvert
maintenant ». Fix client : `Restaurant.canOrder => isOpen`, `openingHours` parsés
seulement pour le message de réouverture. Blocage sur la fiche resto (bandeau + bouton
« Ajouter » désactivé), au moment d'ajouter au panier, et garde-fou final à la commande
(`order_details_screen._processOrder`). Idéalement à doubler d'un contrôle dans la CF
`onOrderCreated` (backend, non fait).

## 16. Builds & découvertes backend

- **1.0.8+1** livrée sur TestFlight : `flutter build ipa`, signature Apple Distribution
  + `aps-environment production` + applesignin vérifiés, upload `xcrun altool` →
  **UPLOAD SUCCEEDED**, Delivery UUID `3521aeed-dc0b-4c9c-8040-1db628a33714`. Contient
  sections 11-14. **Le lot section 15 n'y est pas encore.**
- **Méthode d'inspection des vraies données** (sans service account, sans gcloud) :
  `menuItems` et `restaurants` sont en `allow read: if true` → lecture via l'API REST
  Firestore avec juste la clé API (dans `firebase_options.dart`) :
  `https://firestore.googleapis.com/v1/projects/nomade253-478a9/databases/(default)/documents/...`
  (+ `:runQuery` pour filtrer par nom). Firebase CLI ne lit pas les docs mais liste les
  functions (`firebase functions:list`) et leurs logs (`firebase functions:log`).
- **Copies locales périmées** : `firestore.rules` ET `functions/index.js` sur ce Mac
  sont en retard sur le déployé (la CF `updateRestaurantOpenStatus` n'existe qu'en
  déployé). Les vraies règles déployées ont été téléchargées par le client
  (`~/Downloads/firestore_rules.rules`, 651 lignes vs 456 local) ; la copie projet
  `firestore.rules` a été **supprimée** par le client pour éviter la confusion.
  **Rien n'a été déployé depuis ce Mac** (ni règles, ni functions).

---

## 10. En attente / à faire

1. **Nouvelle build TestFlight pour le lot section 15** : login Apple, suppression de
   compte, retrait Facebook, blocage resto fermé sont buildés/testés sur device mais
   **pas encore sur TestFlight**. Boissons (section 14) confirmées fonctionnelles sur
   device. Prochaine version à passer en **1.0.9** (la 1.0.8 est déjà prise). Procédure :
   bump `pubspec.yaml`, `flutter build ipa --release`, vérif signature, `xcrun altool`.
2. **Questionnaire App Store Connect — capacités de réseau social** (exigence Apple,
   deadline **7 septembre 2026**) : réponse attendue **"Non"** (pas de messagerie
   user-à-user, profils publics ni fil social — seulement des avis à sens unique).
   L'utilisateur répond lui-même sur App Store Connect.
3. **Garde-fou serveur resto fermé** (optionnel, backend) : doubler le blocage client
   d'un contrôle `isOpen` dans la CF `onOrderCreated` (rejet des commandes vers un
   resto fermé). Non fait — nécessite un déploiement de functions (machine Windows).

## Rappel technique

- Build iOS = macOS/Xcode uniquement (ce Mac).
- Deux repos GitHub existent : `Velox_Client` (origin) et `velox-flutter-ios`
  (`ios-repo`, non touché).
- **Backend jamais déployé depuis ce Mac.** Les copies locales `firestore.rules` (copie
  projet supprimée par le client ; vraie version déployée dans
  `~/Downloads/firestore_rules.rules`) ET `functions/index.js` sont **périmées** vs le
  déployé. La CF `updateRestaurantOpenStatus` n'existe qu'en déployé. Lecture des vraies
  données Firestore possible via l'API REST + clé API (collections `menuItems` /
  `restaurants` en read public) ; inspection des functions via `firebase functions:list`
  / `functions:log` (CLI loggé `devchirdon@gmail.com`, projet `nomade253-478a9`).
- **iPhone mus** : connecté cette session, devicectl UUID
  `0E351098-C88C-58A9-B284-E4E551718827` (skill `/velox-deploy`). L'iPhone 12
  (`26B894D9-22F2-5176-BECA-4AD66199D8D3`) était souvent hors ligne. Flux fiable :
  `flutter build ios --release` puis `xcrun devicectl device install app` +
  `device process launch` (le lancement échoue si l'iPhone est verrouillé). Les
  appareils repassent en `unavailable` s'ils se verrouillent / quittent le WiFi —
  revérifier avec `xcrun devicectl list devices`.
