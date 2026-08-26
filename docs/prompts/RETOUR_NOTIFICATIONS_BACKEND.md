# Retour — Backend notifications persistées (suite à PROMPT_NOTIFICATIONS_BACKEND.md)

> Implémenté et **déployé en production** sur `nomade253-478a9`
> (Cloud Functions + règles Firestore + index) le 2026-08-26.
> Réponses dans l'ordre du §8 du prompt initial.

---

## 1. Chemin exact de la collection + forme du document

Aucune divergence par rapport à la spec initiale.

**`users/{uid}/notifications/{notificationId}`** — `notificationId` est un ID
Firestore auto-généré, sauf pour les campagnes promo où c'est le `campaignId`
(cf. §5) — un doc par utilisateur par campagne, réécriture idempotente si la
même campagne est rejouée.

```jsonc
{
  "type": "promo" | "order" | "ride",
  "title": "string",
  "body":  "string",          // texte complet, jamais tronqué
  "createdAt": Timestamp,
  "read":      boolean,       // false à la création, bascule par le client
  "readAt":    Timestamp | null,
  "actionType":  "none" | "order" | "ride" | "restaurant" | "url" | "whatsapp",
  "actionValue": "string | null",
  "imageUrl":   "string | null",
  "campaignId": "string | null"
}
```

Écrit **uniquement** par les Cloud Functions (Admin SDK), jamais par les apps
clientes — cf. §4 pour les règles qui l'imposent.

---

## 2. Index déployés

Dans `firestore.indexes.json`, `fieldOverrides` :

```json
{
  "collectionGroup": "notifications",
  "fieldPath": "createdAt",
  "indexes": [
    { "order": "ASCENDING",  "queryScope": "COLLECTION" },
    { "order": "DESCENDING", "queryScope": "COLLECTION" },
    { "order": "ASCENDING",  "queryScope": "COLLECTION_GROUP" },
    { "order": "DESCENDING", "queryScope": "COLLECTION_GROUP" }
  ]
}
```

- `COLLECTION` (ASC+DESC) : couvre la requête normale de l'app cliente —
  `users/{uid}/notifications` triée par `createdAt` (desc pour l'historique,
  asc dispo si besoin de pagination inversée).
- `COLLECTION_GROUP` (ASC+DESC) : requis par la purge à 90 jours, qui
  interroge tous les `notifications` toutes sous-collections confondues.

Déployé avec succès (`firebase deploy --only firestore:indexes`,
`+ firestore: deployed indexes ... successfully`).

---

## 3. Règles Firestore — en production, confirmé

```
match /users/{userId} {
  match /notifications/{notificationId} {
    allow read:   if isAuth() && isOwner(userId);
    allow update: if isAuth() && isOwner(userId) && onlyFields(['read', 'readAt']);
    allow create, delete: if false;
  }
}
```

Déployées et confirmées actives (`firebase deploy --only firestore:rules`,
`+ firestore: released rules ... to cloud.firestore`) sur le fichier
`functions/scripts/sim/firestore_rules_prod.rules` du repo `nomade_client`
— **c'est ce fichier, et pas la copie dans `FINAL 253 NOMADE\...`, qui est
la source réellement déployée** (référencée par `firebase.json`). La copie a
été mise à jour aussi, par cohérence, mais gardez `firestore_rules_prod.rules`
comme référence si les deux divergent un jour.

Le client peut lire et ne peut **que** basculer `read`/`readAt` — toute
tentative de créer, supprimer, ou modifier un autre champ est rejetée.

---

## 4. Exemples de documents réels, un par `type`

**`order`** — écrit par `sendOrderReadyNotifications` quand une commande passe à "ready" :
```jsonc
{
  "type": "order",
  "title": "✅ Votre commande est prête",
  "body": "Un livreur arrive sous peu pour récupérer votre commande",
  "createdAt": Timestamp(2026-08-26T14:32:10Z),
  "read": false,
  "readAt": null,
  "actionType": "order",
  "actionValue": "aB3xK9pQmZ1234567890",   // orderId
  "imageUrl": null,
  "campaignId": null
}
```

**`ride`** — un exemple parmi les 7 transitions instrumentées (ici `driver_accepted`, écrit par `acceptRideTx`/`onRideUpdated`) :
```jsonc
{
  "type": "ride",
  "title": "✅ Un chauffeur a accepté votre course",
  "body": "Ahmed arrive dans 5 min — +25377123456",
  "createdAt": Timestamp(2026-08-26T14:40:02Z),
  "read": false,
  "readAt": null,
  "actionType": "ride",
  "actionValue": "rD8vN2wLxYp0987654321",  // rideId
  "imageUrl": null,
  "campaignId": null
}
```

**`promo`** — écrit par `sendBroadcastNotification` (admin), un doc par client :
```jsonc
{
  "type": "promo",
  "title": "-20% ce week-end !",
  "body": "Profitez de -20% sur toutes vos commandes jusqu'à dimanche.",
  "createdAt": Timestamp(2026-08-26T09:00:00Z),
  "read": false,
  "readAt": null,
  "actionType": "none",
  "actionValue": null,
  "imageUrl": null,
  "campaignId": "b6e1e6b2-4c9a-4f3d-9a11-7e2f5c8d1a90"
}
```

⚠️ **Limitation actuelle sur les promos** : l'écran admin de diffusion
n'a aujourd'hui que titre + message (pas de champ image / lien / action au
tap). `actionType`/`actionValue`/`imageUrl` sont donc toujours `"none"`/`null`
pour les campagnes — le schéma les supporte déjà, mais rien ne les remplit
tant que l'admin n'a pas un formulaire pour ça. À garder en tête si l'app
prévoit un affichage "carte cliquable" pour les promos.

### `type` de push → `type` de document (mapping réellement implémenté)

| Push `data.type` | Doc `type` | Fonction |
|---|---|---|
| `driver_accepted` | `ride` | `acceptRideTx`, `onRideUpdated` |
| `driver_arriving`, `driver_arrived`, `ride_started`, `ride_completed` | `ride` | `onRideUpdated` |
| `ride_cancelled` (annulé **par le chauffeur**, reçu par le client) | `ride` | `onRideUpdated` |
| `no_driver_available` | `ride` | `sendNextDriverOffer` |
| `order_ready_client` | `order` | `sendOrderReadyNotifications` |
| campagne admin | `promo` | `sendBroadcastNotification` |

**Volontairement non persisté** (push existant mais hors périmètre client) :
- `ride_cancelled` par le **client** (reçu par le chauffeur, pas par vous) ;
- `earnings_updated` (chauffeur uniquement) ;
- accusé de création de commande côté client : n'existe pas côté backend
  aujourd'hui (`onOrderCreated` ne notifie que restaurant + admins, jamais
  le client à la création) ;
- `order_update` : mentionné dans le prompt initial comme type déjà consommé
  par vos apps, mais aucune Cloud Function ne l'émet actuellement (les
  transitions `preparing`/`delivering`/`delivered` sont gérées côté app
  livreur sans notif serveur) — rien à persister tant que ce push n'existe pas
  réellement côté backend.

---

## 5. Callable de diffusion de campagne

**`sendBroadcastNotification`** (déjà existante, utilisée par l'admin —
`broadcast_notification_screen.dart`) — étendue, pas remplacée.

- Payload inchangé : `{ title, body, audiences: string[] }`, `audiences`
  incluant `"clients"` pour toucher votre app.
- Retour désormais enrichi d'un `campaignId` (UUID généré serveur à chaque
  appel) : `{ success, perAudience, totalSent, totalFailed, campaignId }`.
- Historique écrit uniquement pour l'audience `"clients"` — les autres
  (`restaurants`, `livreurs`, `drivers`) reçoivent le push mais n'ont pas
  d'historique in-app (hors périmètre, ce ne sont pas des comptes clients).
- Le doc `users/{uid}/notifications/{campaignId}` est écrit pour **tous**
  les comptes de la collection `users`, avec ou sans `fcmToken` — l'historique
  doit rester disponible même si le push a échoué ou si le token est absent.

---

## Autres points utiles côté iOS

- **`aps.category`** ajouté sur tous les envois listés au §4 :
  `VELOX_ORDER` / `VELOX_RIDE` / `VELOX_PROMO`, avec `thread-id` identique
  (regroupement par famille). `mutable-content` n'est PAS envoyé (pas
  d'`imageUrl` actif aujourd'hui, cf. limitation §4 — à ajouter le jour où
  l'admin pourra attacher une image à une promo).
- **Purge 90 jours** : nouvelle fonction planifiée `purgeOldClientNotifications`
  (toutes les 24h, déployée), requête de groupe de collection sur
  `createdAt < now - 90j`, suppression par lots de 450.
- Rien côté apps clientes n'a été touché — uniquement Cloud Functions +
  règles + index, comme convenu.
