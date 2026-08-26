# Prompt — Persister les notifications pour un historique client (`nomade_client` backend + admin)

> À copier-coller tel quel à l'agent Claude qui travaille sur le **backend
> partagé** (`nomade_client/functions`, règles Firestore) et sur l'**app admin**.
>
> Contexte : Velox est une app VTC + livraison de repas à Djibouti. Les clients
> iOS et Android partagent le même backend Firebase. Aujourd'hui les
> notifications partent en **push FCM uniquement** : dès que l'utilisateur
> balaie la notification, ou qu'iOS purge son centre de notifications, le
> contenu est **définitivement perdu**. C'est particulièrement gênant pour les
> campagnes promo envoyées depuis l'admin.
>
> Objectif : **persister** chaque notification dans Firestore pour que les apps
> clientes affichent une page « Notifications » avec un historique et une
> pastille de non-lus. Le push FCM actuel ne change pas — on ajoute une écriture
> en base à côté, pas un remplacement.
>
> Décisions déjà prises côté produit, à ne pas rediscuter :
> - l'historique couvre **les 3 catégories** : promos admin, commandes food, courses VTC ;
> - le statut lu/non-lu est **stocké côté serveur** (il doit suivre l'utilisateur d'un appareil à l'autre) ;
> - rétention **90 jours**.

---

## 1. Collection à créer

**`users/{uid}/notifications/{notificationId}`** — une sous-collection par
utilisateur (et non une collection globale), imposée par le besoin de statut
lu/non-lu par personne.

```jsonc
{
  "type": "promo" | "order" | "ride",

  "title": "string",        // titre court, identique à celui du push
  "body":  "string",        // ⚠️ TEXTE COMPLET, non tronqué — voir §5

  "createdAt": Timestamp,   // date d'envoi, sert au tri et à la purge
  "read":      false,       // basculé à true par le client
  "readAt":    Timestamp | null,

  // Routage au tap, côté client
  "actionType":  "none" | "order" | "ride" | "restaurant" | "url" | "whatsapp",
  "actionValue": "string | null",   // orderId / rideId / restaurantId / URL / numéro

  "imageUrl":   "string | null",    // optionnel, promo illustrée
  "campaignId": "string | null"     // promos : identifiant de campagne, cf. §3
}
```

**Index requis** : `createdAt` décroissant sur la sous-collection, plus un index
de **groupe de collection** sur `notifications` / `createdAt` pour la purge (§6).

---

## 2. Qui écrit : les Cloud Functions, jamais le client

Toutes les écritures passent par l'Admin SDK. **Il ne faut pas ajouter d'appel
Firestore côté app cliente** : ce serait une source de vérité concurrente et
falsifiable.

Le principe directeur : **la fonction qui envoie déjà le push écrit aussi le
document**, dans la même exécution. Une seule source, donc aucune divergence
possible entre ce qui est notifié et ce qui est historisé.

Points d'accroche existants à instrumenter :

| Origine | `type` | `actionType` / `actionValue` |
|---|---|---|
| `onOrderCreated` et les changements de statut de commande | `order` | `order` / `orderId` |
| `onTaxiRideCreated`, `onRideUpdated`, `assignDriverToRide` | `ride` | `ride` / `rideId` |
| Campagne envoyée depuis l'app admin | `promo` | selon la campagne, cf. §3 |

Les types de push déjà consommés par les apps clientes — à **réutiliser tels
quels**, ne pas en inventer de nouveaux :

```
order_update, order_ready_client,
driver_accepted, driver_arriving, driver_arrived,
ride_started, ride_completed, ride_cancelled,
no_driver_available, ride_accepted, ride_update
```

Mapper chacun vers `type: "order"` ou `type: "ride"`, en conservant le libellé
d'origine dans le `title`/`body` déjà utilisé pour le push.

---

## 3. Campagnes promo : diffusion vers tous les comptes

C'est le seul point qui demande un vrai travail. Une campagne admin doit
produire **un document par utilisateur**.

- Écrire une fonction callable (ou un trigger sur une collection
  `campaigns/{id}` alimentée par l'admin) qui parcourt les utilisateurs et
  écrit en lot. Utiliser **`BulkWriter`** ou des batches de **500 écritures
  maximum**, avec pagination sur la collection `users` — une diffusion à
  quelques milliers de comptes dépasse largement le budget d'une seule requête.
- Renseigner `campaignId` sur chaque document produit. Cela permet de rejouer
  une campagne sans doublon, de la retirer, et de mesurer sa portée.
- La fonction doit être **idempotente** : une seconde exécution avec le même
  `campaignId` ne doit pas créer un second exemplaire chez les utilisateurs
  déjà servis.

⚠️ Le coût d'écriture est proportionnel au nombre de comptes. C'est le prix du
statut lu/non-lu par utilisateur, qui a été explicitement demandé — mais
mentionnez l'ordre de grandeur avant de déployer si la base a beaucoup grossi.

---

## 4. Règles Firestore

Le client doit pouvoir **lire** ses notifications et **uniquement** basculer
`read` / `readAt`. Il ne doit jamais pouvoir en créer, en modifier le contenu,
ni en supprimer.

```
match /users/{uid}/notifications/{notificationId} {
  allow read: if isAuth() && request.auth.uid == uid;

  // Seuls `read` et `readAt` sont modifiables par le client.
  allow update: if isAuth() && request.auth.uid == uid
                && request.resource.data.diff(resource.data)
                     .affectedKeys().hasOnly(['read', 'readAt']);

  allow create, delete: if false;   // Admin SDK uniquement
}
```

À placer avec les autres règles utilisateur, dans le même style que les blocs
`banners` et `config` existants.

---

## 5. Texte complet, pas de troncature

Les apps clientes vont afficher ces notifications **en entier**, avec
possibilité de les déplier. Le champ `body` doit donc contenir le **message
complet**, même s'il dépasse ce qu'un push affiche.

Si le code actuel raccourcit le texte pour le push (limite d'affichage iOS),
gardez la version courte pour le push et écrivez la **version longue** dans le
document Firestore. Les deux peuvent différer, c'est voulu.

---

## 5 bis. `aps.category` dans la charge utile APNs — indispensable

Les apps clientes viennent d'enregistrer trois **catégories de notification
iOS**. C'est ce qui rend une notification dépliable, avec des boutons d'action,
au lieu d'une simple bannière tronquée.

Mais une catégorie enregistrée par l'app ne sert à rien si le message ne la
désigne pas. Or **quand l'app est en arrière-plan ou fermée, iOS rend
directement la charge utile APNs** : l'app n'a aucun moyen d'intervenir. Il faut
donc que le backend renseigne `category` dans chaque message FCM :

```jsonc
{
  "apns": {
    "payload": {
      "aps": {
        "category":  "VELOX_ORDER",   // ou VELOX_RIDE / VELOX_PROMO
        "thread-id": "VELOX_ORDER",   // regroupe les notifications d'une même famille
        "mutable-content": 1          // requis si `imageUrl` est utilisé un jour
      }
    }
  }
}
```

Correspondance à respecter, identique à celle codée côté client :

| `type` du push | `category` |
|---|---|
| `order_update`, `order_ready_client` | `VELOX_ORDER` |
| `driver_accepted`, `driver_arriving`, `driver_arrived`, `ride_started`, `ride_completed`, `ride_cancelled`, `no_driver_available`, `ride_accepted`, `ride_update` | `VELOX_RIDE` |
| campagnes promo | `VELOX_PROMO` |

Sans ce champ, l'agrandissement ne fonctionnera **que** lorsque l'app est déjà
ouverte au premier plan — c'est-à-dire dans le cas le moins fréquent.

---

## 6. Purge à 90 jours

Fonction planifiée quotidienne, sur le modèle de `autoResendReadyOrders` qui
existe déjà :

- requête de **groupe de collection** sur `notifications`, filtre
  `createdAt < now - 90 jours` ;
- suppression par lots, avec pagination — ne pas tenter de tout supprimer en une
  seule exécution ;
- prévoir l'index de groupe de collection correspondant, sans quoi la requête
  échouera au premier déclenchement.

---

## 7. Ce qu'il ne faut pas faire

- Ne pas supprimer ni modifier l'envoi push FCM existant : on ajoute une
  persistance à côté, le comportement de notification actuel reste identique.
- Ne pas écrire ces documents depuis les apps clientes.
- Ne pas créer une collection `notifications` globale : elle rendrait le statut
  lu/non-lu par utilisateur impossible, or il a été explicitement demandé.
- Ne pas inventer de nouveaux `type` de push : réutiliser ceux listés en §2, que
  les apps clientes routent déjà.

---

## 8. À renvoyer à l'équipe iOS une fois fait

Pour que le client puisse être développé sans deviner :

1. Le **chemin exact** de la collection et la forme finale du document, si elle
   a divergé de ce qui est décrit ici.
2. La liste des **index déployés**.
3. La confirmation que les règles §4 sont **en production**.
4. Un **exemple de document réel** pour chacun des trois `type`, tel qu'écrit
   par les fonctions.
5. Le nom de la callable de diffusion de campagne, si l'app admin doit
   l'appeler.
