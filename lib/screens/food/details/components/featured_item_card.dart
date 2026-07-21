import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../../components/small_dot.dart';
import '../../../../constants.dart';
import '../../../../models/menu_item.dart';
import '../../../../models/promotion.dart';

class FeaturedItemCard extends StatelessWidget {
  const FeaturedItemCard({
    super.key,
    required this.menuItem,
    required this.press,
    this.promotion,
  });

  final MenuItem menuItem;
  final VoidCallback press;
  final Promotion? promotion;

  bool get _hasPromo => promotion != null && promotion!.discountPercent > 0;

  double get _discountedPrice => _hasPromo
      ? menuItem.price * (1 - promotion!.discountPercent / 100)
      : menuItem.price;

  @override
  Widget build(BuildContext context) {
    TextStyle textStyle = Theme.of(context).textTheme.labelLarge!.copyWith(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.64),
          fontWeight: FontWeight.normal,
        );
    return InkWell(
      borderRadius: const BorderRadius.all(Radius.circular(8)),
      onTap: press,
      child: Padding(
        padding: const EdgeInsets.all(5.0),
        child: SizedBox(
          width: 140,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.all(Radius.circular(8)),
                      child: menuItem.imageUrl != null
                          ? CachedNetworkImage(
                              imageUrl: menuItem.imageUrl!,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: double.infinity,
                              placeholder: (context, url) => Container(
                                color: Colors.grey[300],
                                child: const Center(
                                  child: CircularProgressIndicator(),
                                ),
                              ),
                              errorWidget: (context, url, error) => Container(
                                color: Colors.grey[300],
                                child: const Icon(Icons.fastfood, size: 40),
                              ),
                            )
                          : Container(
                              color: Colors.grey[300],
                              child: const Icon(Icons.fastfood, size: 40),
                            ),
                    ),
                    if (_hasPromo)
                      Positioned(
                        top: 0,
                        left: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 3),
                          decoration: const BoxDecoration(
                            color: Color(0xFF6EFF6E),
                            borderRadius: BorderRadius.only(
                              topLeft: Radius.circular(8),
                              bottomRight: Radius.circular(8),
                            ),
                          ),
                          child: Text(
                            '-${promotion!.discountPercent}%',
                            style: const TextStyle(
                              color: Colors.black,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                menuItem.name,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    "${_discountedPrice.toStringAsFixed(0)} FDJ",
                    style: textStyle.copyWith(color: primaryColor),
                  ),
                  if (_hasPromo) ...[
                    const SizedBox(width: 4),
                    Text(
                      menuItem.price.toStringAsFixed(0),
                      style: textStyle.copyWith(
                        fontSize: 11,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                  ],
                  const Padding(
                    padding:
                        EdgeInsets.symmetric(horizontal: defaultPadding / 2),
                    child: SmallDot(),
                  ),
                  Expanded(
                    child: Text(
                      menuItem.category,
                      style: textStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  )
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
