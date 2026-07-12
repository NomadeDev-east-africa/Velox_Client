import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../constants.dart';
import '../../rating.dart';
import '../../small_dot.dart';
import '../../../models/restaurant.dart';

class RestaurantInfoMediumCard extends StatelessWidget {
  const RestaurantInfoMediumCard({
    super.key,
    required this.restaurant,
    required this.deliverytTime,
    required this.press,
  });

  final Restaurant restaurant;
  final int deliverytTime;
  final VoidCallback press;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: press,
      child: SizedBox(
        width: 200,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1.25,
              child: ClipRRect(
                borderRadius: const BorderRadius.all(Radius.circular(10)),
                child: CachedNetworkImage(
                  imageUrl: restaurant.imageUrl,
                  fit: BoxFit.cover,
                  memCacheWidth: (200 * MediaQuery.of(context).devicePixelRatio).toInt(),
                  placeholder: (context, url) => Container(
                    color: Colors.grey[300],
                    child: const Center(
                      child: CircularProgressIndicator(),
                    ),
                  ),
                  errorWidget: (context, url, error) => Container(
                    color: Colors.grey[300],
                    child: const Icon(Icons.restaurant, size: 50),
                  ),
                ),
              ),
            ),
            const SizedBox(height: defaultPadding / 2),
            Text(
              restaurant.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: defaultPadding / 4),
            Text(
              restaurant.address,
              maxLines: 1,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: defaultPadding / 2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Rating(rating: restaurant.rating),
                Text(
                  "$deliverytTime min",
                  style: Theme.of(context)
                      .textTheme
                      .labelLarge!
                      .copyWith(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.74)),
                ),
                const SmallDot(),
                Text(
                  "500 FDJ",
                  style: Theme.of(context)
                      .textTheme
                      .labelMedium!
                      .copyWith(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.74)),
                )
              ],
            )
          ],
        ),
      ),
    );
  }
}
