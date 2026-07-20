import 'package:cloud_firestore/cloud_firestore.dart';

class Restaurant {
  final String id;
  final String name;
  final String address;
  final String description;
  final String email;
  final String phone;
  final String imageUrl;
  final double latitude;
  final double longitude;
  final double rating;
  final int totalOrders;
  final double totalRevenue;
  final bool isActive;
  /// Statut « ouvert maintenant », calculé côté backend toutes les 5 min par la
  /// Cloud Function `updateRestaurantOpenStatus` à partir de `openingHours` (en
  /// heure de Djibouti). Le client s'y fie tel quel plutôt que de recalculer les
  /// horaires (risque de divergence de fuseau / créneaux passant minuit).
  final bool isOpen;
  /// Horaires par jour (clé = jour en anglais minuscule), utilisés seulement
  /// pour afficher l'heure de réouverture — pas pour décider ouvert/fermé.
  final Map<String, List<OpeningInterval>> openingHours;
  final DateTime createdAt;
  final DateTime? updatedAt;

  Restaurant({
    required this.id,
    required this.name,
    required this.address,
    required this.description,
    required this.email,
    required this.phone,
    required this.imageUrl,
    required this.latitude,
    required this.longitude,
    this.rating = 0.0,
    this.totalOrders = 0,
    this.totalRevenue = 0.0,
    this.isActive = true,
    this.isOpen = true,
    this.openingHours = const {},
    required this.createdAt,
    this.updatedAt,
  });

  /// Le restaurant peut-il recevoir une commande maintenant.
  bool get canOrder => isOpen;

  /// Libellé « réouvre aujourd'hui à 18h00 » quand c'est fermé, au mieux.
  /// Retourne null si aucun horaire exploitable (message générique alors).
  String? get reopeningLabel {
    const days = [
      'monday', 'tuesday', 'wednesday', 'thursday',
      'friday', 'saturday', 'sunday',
    ];
    // Heure de Djibouti (UTC+3, pas de changement d'heure) pour coller au backend.
    final now = DateTime.now().toUtc().add(const Duration(hours: 3));
    final nowMinutes = now.hour * 60 + now.minute;

    for (var offset = 0; offset < 7; offset++) {
      final day = days[(now.weekday - 1 + offset) % 7];
      final intervals = openingHours[day];
      if (intervals == null || intervals.isEmpty) continue;
      for (final iv in intervals) {
        final open = iv.openMinutes;
        if (open == null) continue;
        // Aujourd'hui : ne proposer qu'un créneau encore à venir.
        if (offset == 0 && open <= nowMinutes) continue;
        final when = iv.open;
        if (offset == 0) return 'Réouverture aujourd\'hui à $when';
        if (offset == 1) return 'Réouverture demain à $when';
        return 'Réouverture ${_dayFr(day)} à $when';
      }
    }
    return null;
  }

  static String _dayFr(String en) => const {
        'monday': 'lundi', 'tuesday': 'mardi', 'wednesday': 'mercredi',
        'thursday': 'jeudi', 'friday': 'vendredi', 'saturday': 'samedi',
        'sunday': 'dimanche',
      }[en] ?? en;

  static Map<String, List<OpeningInterval>> _parseOpeningHours(dynamic raw) {
    if (raw is! Map) return const {};
    final out = <String, List<OpeningInterval>>{};
    raw.forEach((day, value) {
      if (value is List) {
        out[day.toString()] = value
            .whereType<Map>()
            .map((m) => OpeningInterval(
                  open: m['open']?.toString(),
                  close: m['close']?.toString(),
                ))
            .toList();
      }
    });
    return out;
  }

  // Créer depuis Firestore
  factory Restaurant.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Restaurant(
      id: doc.id,
      name: data['name'] ?? '',
      address: data['address'] ?? '',
      description: data['description'] ?? '',
      email: data['email'] ?? '',
      phone: data['phone'] ?? '',
      imageUrl: data['imageUrl'] ?? '',
      latitude: (data['latitude'] ?? 0.0).toDouble(),
      longitude: (data['longitude'] ?? 0.0).toDouble(),
      rating: (data['rating'] ?? 0.0).toDouble(),
      totalOrders: data['totalOrders'] ?? 0,
      totalRevenue: (data['totalRevenue'] ?? 0.0).toDouble(),
      isActive: data['isActive'] ?? true,
      isOpen: data['isOpen'] ?? true,
      openingHours: _parseOpeningHours(data['openingHours']),
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      updatedAt: data['updatedAt'] != null 
          ? (data['updatedAt'] as Timestamp).toDate() 
          : null,
    );
  }

  // Convertir en Map pour Firestore
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'address': address,
      'description': description,
      'email': email,
      'phone': phone,
      'imageUrl': imageUrl,
      'latitude': latitude,
      'longitude': longitude,
      'rating': rating,
      'totalOrders': totalOrders,
      'totalRevenue': totalRevenue,
      'isActive': isActive,
      'isOpen': isOpen,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
    };
  }

  // CopyWith
  Restaurant copyWith({
    String? id,
    String? name,
    String? address,
    String? description,
    String? email,
    String? phone,
    String? imageUrl,
    double? latitude,
    double? longitude,
    double? rating,
    int? totalOrders,
    double? totalRevenue,
    bool? isActive,
    bool? isOpen,
    Map<String, List<OpeningInterval>>? openingHours,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Restaurant(
      id: id ?? this.id,
      name: name ?? this.name,
      address: address ?? this.address,
      description: description ?? this.description,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      imageUrl: imageUrl ?? this.imageUrl,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      rating: rating ?? this.rating,
      totalOrders: totalOrders ?? this.totalOrders,
      totalRevenue: totalRevenue ?? this.totalRevenue,
      isActive: isActive ?? this.isActive,
      isOpen: isOpen ?? this.isOpen,
      openingHours: openingHours ?? this.openingHours,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// Un créneau d'ouverture « HH:MM » → « HH:MM ».
class OpeningInterval {
  final String? open;
  final String? close;

  const OpeningInterval({this.open, this.close});

  /// Minutes depuis minuit pour l'heure d'ouverture, ou null si illisible.
  int? get openMinutes => _toMinutes(open);

  static int? _toMinutes(String? hhmm) {
    if (hhmm == null) return null;
    final parts = hhmm.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return h * 60 + m;
  }
}
