import 'package:cloud_firestore/cloud_firestore.dart';

/// Type de rendu d'une bannière d'accueil.
enum BannerType {
  /// Titre + sous-titre sur fond coloré plein.
  text,

  /// Image plein cadre chargée depuis Storage.
  image,
}

/// Action déclenchée au tap sur une bannière.
enum BannerActionType {
  /// Bannière décorative, non cliquable.
  none,

  /// Ouvre WhatsApp sur le numéro contenu dans [PromoBanner.actionValue].
  whatsapp,

  /// Ouvre une URL externe dans le navigateur.
  url,

  /// Navigue vers la fiche du restaurant dont l'ID est dans `actionValue`.
  restaurant,

  /// Navigue vers la liste des plats de la catégorie dans `actionValue`.
  category,
}

/// Bannière promotionnelle de l'accueil Food, pilotée depuis l'admin.
///
/// Source : collection Firestore `banners` (lecture pour tout utilisateur
/// connecté, écriture réservée aux admins). Un seul texte par bannière, affiché
/// tel quel quelle que soit la langue du téléphone — pas de multi-langue.
class PromoBanner {
  const PromoBanner({
    required this.id,
    required this.type,
    required this.order,
    required this.active,
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.actionType,
    this.actionValue,
  });

  /// ID du document Firestore.
  final String id;

  /// Rendu texte ou image.
  final BannerType type;

  /// Ordre d'affichage croissant dans le carrousel.
  final int order;

  /// Bannière visible ou non (filtré côté client, cf. [BannerService]).
  final bool active;

  /// Titre — utilisé seulement si [type] vaut [BannerType.text].
  final String title;

  /// Sous-titre — utilisé seulement si [type] vaut [BannerType.text].
  final String subtitle;

  /// URL Storage publique — utilisée seulement si [type] vaut
  /// [BannerType.image].
  final String imageUrl;

  /// Action au tap.
  final BannerActionType actionType;

  /// Cible de l'action : numéro WhatsApp, URL, ID restaurant ou nom de
  /// catégorie selon [actionType]. `null` si [BannerActionType.none].
  final String? actionValue;

  /// Vrai si la bannière déclenche une action au tap.
  bool get isTappable =>
      actionType != BannerActionType.none &&
      (actionValue?.trim().isNotEmpty ?? false);

  /// Vrai si la bannière a de quoi s'afficher (évite les cartes vides quand un
  /// document admin est incomplet).
  bool get isRenderable => type == BannerType.image
      ? imageUrl.trim().isNotEmpty
      : title.trim().isNotEmpty || subtitle.trim().isNotEmpty;

  factory PromoBanner.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? const {};

    return PromoBanner(
      id: doc.id,
      type: _parseType(data['type']),
      // Les docs admin peuvent stocker l'ordre en num ; les bannières sans
      // `order` partent en fin de liste plutôt qu'en tête.
      order: (data['order'] as num?)?.toInt() ?? 9999,
      active: data['active'] as bool? ?? false,
      title: data['title'] as String? ?? '',
      subtitle: data['subtitle'] as String? ?? '',
      imageUrl: data['imageUrl'] as String? ?? '',
      actionType: _parseActionType(data['actionType']),
      actionValue: (data['actionValue'] as String?)?.trim(),
    );
  }

  static BannerType _parseType(dynamic raw) =>
      raw == 'image' ? BannerType.image : BannerType.text;

  static BannerActionType _parseActionType(dynamic raw) {
    switch (raw) {
      case 'whatsapp':
        return BannerActionType.whatsapp;
      case 'url':
        return BannerActionType.url;
      case 'restaurant':
        return BannerActionType.restaurant;
      case 'category':
        return BannerActionType.category;
      default:
        return BannerActionType.none;
    }
  }
}
