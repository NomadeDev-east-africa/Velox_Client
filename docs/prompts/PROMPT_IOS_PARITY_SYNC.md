# Prompt — Rattraper côté iOS les évolutions Android récentes (`Velox_client`)

> À copier-coller tel quel à l'agent Claude qui travaille sur l'app **iOS**.
> Contexte : `Velox_client` (Android/Kotlin) et l'app iOS partagent le **même backend
> Firebase** (Firestore + Cloud Functions + règles) — seul le client change. Les
> fonctionnalités ci-dessous sont déjà **en code côté Android** (branche
> `feature/ios-parity-preprod`, pas encore mergée/commitée) et doivent être répliquées
> côté iOS pour la parité de fonctionnalités. Rien à changer côté backend : tout ce qui
> est décrit ici s'appuie sur des collections/Cloud Functions **déjà existantes et
> partagées**.
>
> Ce prompt couvre deux sessions de travail Android consécutives.

---

## 1. Bannières promo pilotées depuis l'admin (au lieu d'un carrousel codé en dur)

**Backend (déjà en place, ne pas toucher)** — collection `banners/{id}` :
```
{
  type: "text" | "image",
  order: number,             // ordre d'affichage
  active: boolean,
  // si type == "text"
  title: string,
  subtitle: string,
  // si type == "image"
  imageUrl: string,          // URL Storage publique
  // commun
  actionType: "none" | "whatsapp" | "url" | "restaurant" | "category",
  actionValue: string | null,
}
```
Règles : lecture = n'importe quel utilisateur connecté (`isAuth()`), écriture = admin
seulement. Pas de multi-langue : un seul texte par bannière, affiché tel quel peu
importe la langue du téléphone.

**Ce qu'il faut faire côté iOS :**
- Remplacer le carrousel de bannières codé en dur de l'accueil Food par une lecture
  temps réel de `banners` (tri par `order`, filtrer `active == true` **côté client**
  après lecture — pas dans la requête Firestore, pour éviter un index composite).
- Deux rendus selon `type` : un texte (titre + sous-titre sur fond coloré plein) ou une
  image (URL Storage).
- Au tap (si `actionType != "none"`) : ouvrir WhatsApp (`actionType == "whatsapp"`, URL
  `https://wa.me/{actionValue}`), une URL externe, ou naviguer vers un restaurant/une
  catégorie selon `actionValue`.

**Bug corrigé côté Android à reproduire si l'UI iOS a le même souci :** le texte libre
saisi par l'admin (longueur inconnue) débordait du cadre fixe de la carte. Fix appliqué :
- Le titre/sous-titre **rétrécissent automatiquement** (au lieu d'être coupés) si le
  texte est trop long pour tenir sur les lignes prévues (2 lignes titre, 2 lignes
  sous-titre), jusqu'à une taille de police minimale — au-delà, ellipsis en dernier
  recours plutôt qu'une coupe brutale mi-glyphe.
- Le conteneur de texte utilise **toute la largeur** de la carte (pas seulement la
  largeur du texte lui-même).
- L'image d'une bannière `type: "image"` s'affiche en **`FillWidth`** (occupe toute la
  largeur de la carte, léger rognage vertical accepté si le ratio ne correspond pas
  exactement) — **pas** `Crop` (coupait trop l'image) **ni** `Fit` pur (laissait de
  grosses bandes vides sur les côtés si l'image n'était pas assez large).

---

## 2. Codes promo au checkout

**Backend (déjà en place, ne pas toucher)** — collection `promoCodes/{CODE}` (doc ID =
le code, en MAJUSCULES), **non lisible directement côté client** (règles : `read: false`
sauf admin). Tout passe par la Cloud Function callable `validatePromoCode` :

Input :
```json
{ "code": "...", "restaurantId": "...", "subtotal": 0, "deliveryFee": 0 }
```
Output :
```jsonc
// refusé
{ "valid": false, "message": "..." }
// accepté — discountAmount déjà calculé et plafonné côté serveur, à afficher tel quel
{ "valid": true, "code": "WELCOME10", "discountAmount": 450, "discountType": "percentage", "discountValue": 10 }
```
Le trigger `onOrderCreated` réévalue tout côté serveur à la création de la commande
(code actif ? pas expiré ? pas déjà utilisé par ce client ? bon restaurant ?) et corrige
silencieusement la remise/le total si besoin — même filet de sécurité que les points de
fidélité.

**Ce qu'il faut faire côté iOS :**
- Modèle commande : ajouter `promoCode` (string?) et `promoDiscount` (int, défaut 0).
  Le total facturé = `subtotal + deliveryFee - loyaltyDiscount - promoDiscount`
  (jamais négatif).
- Écran panier/checkout : champ + bouton "Appliquer" un code promo ; si valide, afficher
  "Code appliqué (XXXX) : −450 FDJ" avec option de le retirer ; si invalide, afficher le
  message d'erreur renvoyé par la fonction (pas bloquant, l'utilisateur peut réessayer).
- **Revalider automatiquement si le panier/le restaurant change** après application
  (le pourcentage/montant calculé n'est plus valable) — le plus simple est d'effacer le
  code appliqué dès que le panier change et de laisser l'utilisateur retaper.
- Ne jamais recalculer soi-même la remise pour l'affichage : toujours utiliser
  `discountAmount` renvoyé par `validatePromoCode`.

---

## 3. Widget flottant de suivi de commande active

Nouveau composant persistant, visible sur **Accueil / Fiche resto / Panier / Profil**
(jamais sur l'écran de suivi lui-même) tant qu'une commande food est active :
- **Règles de visibilité** : masqué si aucune commande ou si `status == "cancelled"` ;
  visible tant que `pending → delivering` ; reste visible **8 secondes après livraison**
  (`status == "completed"`, calculé depuis `deliveredAt`) puis disparaît tout seul.
- Réagit à l'utilisateur connecté : bascule sur la dernière commande du compte courant,
  se vide à la déconnexion (écoute un flux "dernière commande de cet utilisateur",
  équivalent `streamLatestOrder(uid)`).
- Contenu : icône + libellé selon le statut (préparation / prête / en livraison /
  livrée), un indicateur à 3 points regroupant les statuts détaillés en 3 phases
  (préparation → prête → livraison/livrée), tap → ouvre l'écran de suivi de cette
  commande.
- Style : pastille arrondie flottante en bas à droite, ne doit jamais chevaucher une
  barre de panier ou la navigation du bas déjà présente à l'écran (décaler verticalement
  selon ce qui occupe déjà le bas).

---

## 4. Écran "Mes commandes" / "Historique" — mise en cohérence UI

Sur Android, cet écran utilisait encore les composants Material3 par défaut (couleurs,
police) au lieu du thème sombre + accent vert de l'app — corrigé. Côté iOS, vérifier que
l'écran équivalent (liste des commandes food + historique des courses VTC) respecte bien
le même thème visuel que le reste de l'app, et si ce n'est pas déjà le cas, ajouter :
- Une carte par commande/course avec : miniature (image restaurant ou icône par défaut),
  nom, date, montant, **badge de statut coloré avec icône** (ex : sablier = en attente,
  coche verte = terminé/livré, croix rouge = annulé, icône dédiée = en préparation/livraison).
- Section food et section courses séparées par un en-tête avec icône (fourchette/couteau
  pour food, voiture pour les courses) + compteur.
- Tap sur une commande **active** (non terminée/annulée) → ouvre son suivi en direct.
- État vide (aucune commande) avec icône + message, cohérent avec les autres écrans
  vides de l'app (ex. adresses vides, panier vide).

---

## 5. Choix d'adresse au checkout : proposer les adresses enregistrées, pas seulement la carte

Avant : au checkout, la seule façon de définir l'adresse de livraison était de choisir un
point sur la carte, alors que l'app a par ailleurs un **carnet d'adresses enregistrées**
(CRUD déjà existant, utilisé dans le profil : nom, adresse, détails, type maison/bureau/
autre, coordonnées, adresse par défaut).

**Ce qu'il faut faire côté iOS (si pas déjà le cas) :** au checkout, taper sur "Adresse
de livraison" doit ouvrir un choix entre :
1. **Les adresses déjà enregistrées** de l'utilisateur (liste avec icône selon le type,
   badge "par défaut") — sélection directe, pas besoin de repasser par la carte.
2. **Choisir un point sur la carte** (comportement existant, conservé en option de repli
   pour une adresse ponctuelle non enregistrée).

---

## 6. Tarifs VTC — désormais pilotés depuis Firestore (plus du tout en dur)

⚠️ **Mise à jour depuis la rédaction initiale de ce point** : ce qui suit remplace un
premier barème en dur (600/750 FDJ, 3 km inclus, 200 FDJ/km) qui a depuis été déplacé
vers une config Firestore + une validation serveur — ne pas coder de valeurs en dur
côté iOS, lire la config comme décrit ci-dessous.

**Nouveau document Firestore `config/taxiPricing`** (règles déjà déployées : `read:
isAuth()`, `write: isAdmin()`, même politique que `banners`) :
```json
{
  "standard": { "basePrice": 600, "includedKm": 3, "pricePerKm": 200 },
  "comfort":  { "basePrice": 750, "includedKm": 3, "pricePerKm": 200 }
}
```
Formule : `prix = basePrice + pricePerKm × max(0, distanceKm − includedKm)`.

**Ce qu'il faut faire côté iOS :**
- Écouter ce document en temps réel (comme pour `banners`) plutôt que coder le barème
  en dur — l'admin doit pouvoir changer les prix sans nouvelle soumission App Store.
- Garder des **valeurs par défaut locales identiques** à celles ci-dessus (600/3/200 et
  750/3/200) comme repli si le document est absent, vide, ou en erreur de lecture — ce
  sont les mêmes valeurs que le fallback codé côté Android (`TaxiCatalog.choices`) et
  côté Cloud Function (`DEFAULT_TAXI_PRICING` dans `nomade_client/functions/index.js`).
  Le doc n'existe pas encore forcément en prod tant que personne n'a sauvegardé depuis
  l'écran admin — tout doit continuer à fonctionner correctement dans ce cas.

**Revalidation déjà en place côté serveur (aucune action iOS requise, juste à savoir)** :
`nomade_client/functions/index.js` recalcule `estimatedFare` à la création de la course
(`onTaxiRideCreated`) et `finalFare` à sa complétion (`onRideUpdated`) depuis ce même
document — si jamais l'app iOS envoie une estimation qui ne correspond pas à la formule
(bug, ancienne valeur en cache…), le serveur la corrige silencieusement, comme pour les
prix des plats food (`validatePrices`). Donc pas de risque de facturation incorrecte
même en cas de décalage temporaire — mais éviter le décalage reste important pour que
le prix **affiché** au client corresponde au prix **facturé**.

---

## 7. Pour information — déjà fait côté Android, à vérifier si applicable à iOS

- **Carrousel promo accueil Food** : 2 nouvelles bannières ajoutées en plus de
  l'existante ("Pensé pour Djibouti, fait pour vous" + une bannière cliquable qui ouvre
  WhatsApp) — probablement obsolète pour iOS puisque le carrousel est maintenant piloté
  par l'admin (point 1) plutôt qu'en dur.
- **Fiche restaurant** : la catégorie sélectionnée (Burger, Accompagnement, Boissons…)
  passe en vert fluo (couleur d'accent de l'app) au lieu de la couleur de texte normale —
  à vérifier si l'écran iOS équivalent a le même comportement.
- **Backend `nomade_client` (partagé, déjà déployé en prod, aucune action iOS requise)** :
  fix d'un bug VTC où un échec d'envoi push au chauffeur ciblé perdait toute la file de
  secours (`assignDriverToRide`) ; nouvelle fonction planifiée `autoResendReadyOrders`
  qui relance automatiquement les commandes food prêtes sans livreur. Comportement déjà
  correct pour tous les clients (Android et iOS) sans rien à changer côté app.

---

## Ne pas faire

- Ne pas dupliquer la logique de calcul de remise/prix promo côté client — toujours
  utiliser la valeur renvoyée par `validatePromoCode`.
- Ne pas lire `promoCodes`/`promoCodeRedemptions` directement en Firestore (bloqué par
  les règles).
- Ne pas modifier les Cloud Functions ni les règles Firestore — tout est déjà en place
  et partagé entre Android et iOS.
