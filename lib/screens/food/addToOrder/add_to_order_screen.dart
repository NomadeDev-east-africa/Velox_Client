import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../models/menu_item.dart';
import '../../../models/option_group.dart';
import '../../../models/option_selection.dart';
import '../../../models/restaurant.dart';
import '../../../models/extra_option.dart';
import '../../../models/sauce_option.dart';
import '../../../models/order_item.dart';
import '../../../models/promotion.dart';
import '../../../providers/all_providers.dart';
import '../../../services/promotion_service.dart';
import '../../../theme/app_colors.dart';
import '../orderDetails/order_details_screen.dart';

class AddToOrderScreen extends ConsumerStatefulWidget {
  final MenuItem   menuItem;
  final Restaurant restaurant;
  /// Promo déjà résolue par l'écran appelant (liste resto). Si `null`, l'écran
  /// la récupère lui-même : le prix facturé reste ainsi correct depuis n'importe
  /// quel point d'entrée (à la une, recherche, catégorie...).
  final Promotion? promotion;

  const AddToOrderScreen({
    super.key,
    required this.menuItem,
    required this.restaurant,
    this.promotion,
  });

  @override
  ConsumerState<AddToOrderScreen> createState() => _AddToOrderScreenState();
}

class _AddToOrderScreenState extends ConsumerState<AddToOrderScreen> {
  late AppColors _c;

  int _quantity = 1;

  /// Promo active applicable à ce plat (null = aucune).
  Promotion? _promotion;

  /// Sélections par groupe (aligné sur `menuItem.optionGroups`).
  /// Pour un groupe `single`, le Set contient 0 ou 1 index ; pour `multiple`, 0..N.
  final List<Set<int>> _groupSelections = [];

  List<OptionGroup> get _optionGroups => widget.menuItem.optionGroups;
  bool get _isDataDriven => _optionGroups.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _promotion = widget.promotion;
    if (_isDataDriven) {
      _initializeOptionGroups();
    }
    // Plat sans optionGroups : aucune section d'options à afficher
    // (plus d'extras/sauces inventés par défaut, cf. fix aligné sur l'app Android).
    // Filet de sécurité : si l'appelant n'a pas fourni la promo, on la résout
    // ici pour ne jamais facturer un plat en promo au plein tarif.
    if (_promotion == null) _resolvePromotion();
  }

  Future<void> _resolvePromotion() async {
    final promos = await PromotionService()
        .getActivePromotionsForRestaurant(widget.restaurant.id);
    if (!mounted) return;
    final resolved = PromotionService.resolveForItem(promos, widget.menuItem);
    if (resolved != null) setState(() => _promotion = resolved);
  }

  // ── PRIX & PROMO ────────────────────────────────────────────────────────────
  bool get _hasPromo =>
      _promotion != null && _promotion!.discountPercent > 0;

  int get _discountPercent => _hasPromo ? _promotion!.discountPercent : 0;

  /// Prix de base après remise (la remise porte sur le plat, pas sur les
  /// suppléments — cohérent avec l'affichage de la fiche resto).
  double get _discountedBasePrice => _hasPromo
      ? widget.menuItem.price * (1 - _discountPercent / 100)
      : widget.menuItem.price;

  /// Initialise les sélections data-driven. Présélectionne le 1er choix d'un
  /// groupe `single + required` pour qu'un choix soit toujours valide.
  void _initializeOptionGroups() {
    for (final group in _optionGroups) {
      final selected = <int>{};
      if (group.isSingle && group.required && group.choices.isNotEmpty) {
        selected.add(0);
      }
      _groupSelections.add(selected);
    }
  }

  int get _optionsSurcharge => _isDataDriven
      ? OptionSelection.surcharge(_optionGroups, _groupSelections)
      : 0;

  int get _totalPrice =>
      ((_discountedBasePrice + _optionsSurcharge) * _quantity).round();

  // ── RÈGLE D'OR : AFFICHER LE CONTRAT ADMIN, RIEN DE PLUS ───────────────────
  // Les groupes sont rendus dans l'ORDRE EXACT du tableau `optionGroups` de
  // Firestore, tous visibles, sans aucune règle métier déduite du nom du groupe.
  // Le nom d'un groupe est un texte libre saisi par chaque restaurant : la prod
  // contient « Shake, Juice & Drink », « Hot Berevage », « Roti/Bread »,
  // « Envie d'une Gauffre ? »… — toute heuristique par mot-clé y échoue en
  // silence. Seule la présence/absence d'un champ pilote l'affichage, jamais son
  // libellé. (Le seul usage restant du nom est le rangement des choix « sauce »
  // dans `sauces` au moment de construire le panier — pur format de stockage
  // pour l'app resto, invisible à l'écran, cf. `OptionSelection.toCart`.)

  // ── SÉLECTION DATA-DRIVEN ───────────────────────────────────────────────────

  void _toggleChoice(int groupIndex, int choiceIndex) {
    final group = _optionGroups[groupIndex];
    final selected = _groupSelections[groupIndex];

    // Plafond générique piloté par l'admin (`maxChoices`, groupes `multiple`
    // uniquement). 0 = illimité. Bloque l'ajout au-delà, comme l'app Android.
    if (!group.isSingle &&
        group.maxChoices > 0 &&
        !selected.contains(choiceIndex) &&
        selected.length >= group.maxChoices) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(
            '${group.maxChoices} choix maximum pour ${group.name}.',
            style: TextStyle(color: _c.onSurface),
          ),
          backgroundColor: _c.surfaceHigh,
          behavior: SnackBarBehavior.floating,
        ));
      return;
    }

    setState(() {
      if (group.isSingle) {
        // Radio : un seul choix. Si requis, on ne peut pas désélectionner.
        if (selected.contains(choiceIndex) && !group.required) {
          selected.clear();
        } else {
          selected
            ..clear()
            ..add(choiceIndex);
        }
      } else {
        // Checkbox : 0..N choix.
        if (selected.contains(choiceIndex)) {
          selected.remove(choiceIndex);
        } else {
          selected.add(choiceIndex);
        }
      }
    });
  }

  /// Premier groupe requis sans sélection, ou `null` si tout est valide.
  /// Tous les groupes sont affichés, donc tous sont vérifiés : plus aucun choix
  /// requis ne peut être réclamé sans être visible à l'écran.
  OptionGroup? _firstUnsatisfiedRequiredGroup() {
    for (var gi = 0; gi < _optionGroups.length; gi++) {
      final group = _optionGroups[gi];
      if (group.required && _groupSelections[gi].isEmpty) return group;
    }
    return null;
  }

  // ── LOGIQUE PANIER ────────────────────────────────────────────────────────

  void _proceedAddToCart() {
    // Garde-fou : un restaurant fermé ne doit recevoir aucune commande.
    // `canOrder` s'appuie sur isOpen, calculé backend selon les horaires.
    if (!widget.restaurant.canOrder) {
      _showClosedMessage();
      return;
    }
    if (_isDataDriven) {
      final missing = _firstUnsatisfiedRequiredGroup();
      if (missing != null) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text(
              'Veuillez choisir : ${missing.name}',
              style: TextStyle(color: _c.onSurface),
            ),
            backgroundColor: _c.surfaceHigh,
            behavior: SnackBarBehavior.floating,
          ));
        return;
      }
    }
    final cart = ref.read(cartProvider);
    if (cart.isDifferentRestaurant(widget.restaurant.id)) {
      _showDifferentRestaurantDialog(cart.selectedRestaurant?.name);
    } else {
      _addItemToCart();
      Navigator.pop(context);
    }
  }

  void _showClosedMessage() {
    final reopen = widget.restaurant.reopeningLabel;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(
          reopen == null
              ? '${widget.restaurant.name} est actuellement fermé.'
              : '${widget.restaurant.name} est fermé. $reopen.',
          style: TextStyle(color: _c.onSurface),
        ),
        backgroundColor: _c.surfaceHigh,
        behavior: SnackBarBehavior.floating,
      ));
  }

  void _showDifferentRestaurantDialog(String? currentRestaurantName) {
    final c = _c;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        title: Text('Restaurant différent',
            style: TextStyle(color: c.onSurface, fontWeight: FontWeight.bold)),
        content: Text(
          'Vous avez déjà des articles de '
          '"${currentRestaurantName ?? "un autre restaurant"}". '
          'Voulez-vous vider votre panier et ajouter cet article '
          'de "${widget.restaurant.name}" ?',
          style: TextStyle(color: c.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('Annuler', style: TextStyle(color: c.onSurfaceVariant)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _clearCartAndAddNewItem();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: c.primary,
              foregroundColor: c.onPrimary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
            child: const Text('Vider le panier',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _clearCartAndAddNewItem() {
    ref.read(cartProvider.notifier).clearCart();
    ref.read(cartProvider.notifier).setRestaurant(widget.restaurant);
    _addItemToCart();
    Navigator.pop(context);
  }

  void _addItemToCart() {
    final cart = ref.read(cartProvider);
    if (cart.selectedRestaurant == null) {
      ref.read(cartProvider.notifier).setRestaurant(widget.restaurant);
    }

    // Reverser les choix dans extras/sauces pour rester lisible par l'app resto.
    final List<ExtraOption> extras;
    final List<SauceOption> sauces;
    if (_isDataDriven) {
      final mapping = OptionSelection.toCart(_optionGroups, _groupSelections);
      extras = mapping.extras;
      sauces = mapping.sauces;
    } else {
      // Plat sans optionGroups : pas d'extras/sauces.
      extras = <ExtraOption>[];
      sauces = <SauceOption>[];
    }

    final orderItem = OrderItem(
      menuId:      widget.menuItem.id,
      name:        widget.menuItem.name,
      description: widget.menuItem.description,
      imageUrl:    widget.menuItem.imageUrl ?? '',
      category:    widget.menuItem.category,
      // Prix promo appliqué : le client doit payer le tarif remisé, pas le plein
      // tarif. La remise porte sur le plat ; extras/sauces s'ajoutent au tarif normal.
      basePrice:   _discountedBasePrice.round(),
      quantity:    _quantity,
      extras:      extras,
      sauces:      sauces,
    );
    ref.read(cartProvider.notifier).addItem(orderItem);
  }

  // ── UI COMPONENTS ─────────────────────────────────────────────────────────

  Widget _buildHeroImage() {
    final hasImage = widget.menuItem.imageUrl != null &&
        widget.menuItem.imageUrl!.isNotEmpty;

    return SizedBox(
      height: 300,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          hasImage
              ? CachedNetworkImage(
                  imageUrl: widget.menuItem.imageUrl!,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    color: _c.surfaceHigh,
                    child: Center(
                      child: CircularProgressIndicator(
                          color: _c.primary, strokeWidth: 2),
                    ),
                  ),
                  errorWidget: (context, url, error) => Container(
                    color: _c.surfaceHigh,
                    child: Icon(Icons.fastfood, color: _c.onSurfaceVariant, size: 60),
                  ),
                )
              : Container(
                  color: _c.surfaceHigh,
                  child: Icon(Icons.fastfood, color: _c.onSurfaceVariant, size: 60),
                ),
          // Gradient overlay bottom
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    _c.bg.withValues(alpha: 0.5),
                    _c.bg,
                  ],
                  stops: const [0.4, 0.75, 1.0],
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _c.primary.withValues(alpha: 0.15),
                    border: Border.all(color: _c.primary.withValues(alpha: 0.6)),
                  ),
                  child: Text(
                    'AVAILABLE_UNIT_01',
                    style: TextStyle(
                      color: _c.primary,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.menuItem.name.toUpperCase(),
                  style: TextStyle(
                    color: _c.onSurface,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                    height: 1.1,
                  ),
                ),
                if (widget.menuItem.description.isNotEmpty)
                  Text(
                    widget.menuItem.description,
                    style: TextStyle(color: _c.onSurfaceVariant, fontSize: 13),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceAndQuantity() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.only(left: 12),
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: _c.primary, width: 2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'BASE COST',
                      style: TextStyle(
                        color: _c.onSurfaceVariant,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.8,
                      ),
                    ),
                    if (_hasPromo) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        color: const Color(0xFF6EFF6E),
                        child: Text(
                          '-$_discountPercent%',
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${_discountedBasePrice.toStringAsFixed(1)} FDJ',
                      style: TextStyle(
                        color: _c.primary,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.5,
                      ),
                    ),
                    if (_hasPromo) ...[
                      const SizedBox(width: 8),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Text(
                          '${widget.menuItem.price.toStringAsFixed(0)} FDJ',
                          style: TextStyle(
                            color: _c.onSurfaceVariant,
                            fontSize: 13,
                            decoration: TextDecoration.lineThrough,
                            decorationColor: _c.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const Spacer(),
          Container(
            decoration: BoxDecoration(
              color: _c.surfaceHigh,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                _buildQtyButton(
                  icon: Icons.remove,
                  onTap: _quantity > 1 ? () => setState(() => _quantity--) : null,
                ),
                Container(
                  width: 48,
                  alignment: Alignment.center,
                  child: Text(
                    _quantity.toString().padLeft(2, '0'),
                    style: TextStyle(
                      color: _c.onSurface,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                _buildQtyButton(
                  icon: Icons.add,
                  onTap: () => setState(() => _quantity++),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQtyButton({required IconData icon, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        color: onTap != null ? _c.surface : _c.surfaceLow,
        child: Icon(icon,
            color: onTap != null ? _c.onSurface : _c.outlineVariant, size: 18),
      ),
    );
  }

  Widget _buildSectionHeader(String title, {bool required = false}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 0),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: _c.onSurfaceVariant,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 2,
                ),
              ),
              if (required)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _c.primary.withValues(alpha: 0.12),
                    border: Border.all(color: _c.primary.withValues(alpha: 0.5)),
                  ),
                  child: Text(
                    'REQUIRED',
                    style: TextStyle(
                      color: _c.primary,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Divider(color: _c.outlineVariant.withValues(alpha: 0.3), height: 1),
        ],
      ),
    );
  }

  // ── RENDU DATA-DRIVEN ───────────────────────────────────────────────────────

  Widget _buildGroupSection(int groupIndex) {
    final group = _optionGroups[groupIndex];
    final title = group.name.trim().isEmpty
        ? 'OPTIONS'
        : group.name.toUpperCase();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(title, required: group.required),
        ...List.generate(
          group.choices.length,
          (ci) => _buildChoiceRow(groupIndex, ci),
        ),
      ],
    );
  }

  Widget _buildChoiceRow(int groupIndex, int choiceIndex) {
    final group    = _optionGroups[groupIndex];
    final choice   = group.choices[choiceIndex];
    final selected = _groupSelections[groupIndex].contains(choiceIndex);
    final isSingle = group.isSingle;

    const animDuration = Duration(milliseconds: 220);
    const animCurve = Curves.easeOut;

    return GestureDetector(
      onTap: () => _toggleChoice(groupIndex, choiceIndex),
      child: AnimatedContainer(
        duration: animDuration,
        curve: animCurve,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: _c.outlineVariant.withValues(alpha: 0.2)),
          ),
          color: selected ? _c.primary.withValues(alpha: 0.05) : Colors.transparent,
        ),
        child: Row(
          children: [
            // Radio (cercle) pour single, checkbox (carré) pour multiple.
            AnimatedContainer(
              duration: animDuration,
              curve: animCurve,
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: isSingle ? BoxShape.circle : BoxShape.rectangle,
                color: selected ? _c.primary : Colors.transparent,
                border: Border.all(
                  color: selected ? _c.primary : _c.outlineVariant,
                  width: 1.5,
                ),
              ),
              child: selected
                  ? Icon(Icons.check, color: _c.onPrimary, size: 14)
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: AnimatedDefaultTextStyle(
                duration: animDuration,
                curve: animCurve,
                style: TextStyle(
                  color: selected ? _c.onSurface : _c.onSurfaceVariant,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
                child: Text(choice.name.toUpperCase()),
              ),
            ),
            AnimatedDefaultTextStyle(
              duration: animDuration,
              curve: animCurve,
              style: TextStyle(
                color: choice.price > 0
                    ? (selected ? _c.primary : _c.onSurfaceVariant)
                    : _c.onSurfaceVariant,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              child: Text(choice.price > 0 ? '+ ${choice.price} FDJ' : 'INCLUS'),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildAddToCartButton() {
    final closed = !widget.restaurant.canOrder;
    return Container(
      color: _c.bg,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: GestureDetector(
        onTap: _proceedAddToCart,
        child: Container(
          height: 56,
          color: closed ? _c.surfaceHigh : _c.primary,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                closed
                    ? 'RESTAURANT FERMÉ'
                    : 'AJOUTER AU PANIER ($_totalPrice FDJ)',
                style: TextStyle(
                  color: closed ? _c.onSurfaceVariant : _c.onPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(width: 10),
              Icon(closed ? Icons.schedule_rounded : Icons.bolt_rounded,
                  color: closed ? _c.onSurfaceVariant : _c.onPrimary, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = ref.watch(themeNotifierProvider).isDarkMode;
    _c = isDark ? AppColors.dark : AppColors.light;

    return Scaffold(
      backgroundColor: _c.bg,
      appBar: AppBar(
        backgroundColor: _c.bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: _c.primary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.restaurant.name.toUpperCase(),
          style: TextStyle(
            color: _c.primary,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.shopping_cart_outlined, color: _c.onSurfaceVariant),
            tooltip: 'Voir le panier',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const OrderDetailsScreen()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeroImage(),
                  _buildPriceAndQuantity(),
                  // Plat sans optionGroups : aucune section d'options affichée.
                  // Sinon : TOUS les groupes, dans l'ordre exact de Firestore.
                  if (_isDataDriven)
                    ...List.generate(
                      _optionGroups.length,
                      _buildGroupSection,
                    ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
          _buildAddToCartButton(),
        ],
      ),
    );
  }
}
