import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../components/rating_with_counter.dart';
import '../../../../constants.dart';
import '../../../../translations/app_translations.dart';
import '../../../../models/restaurant.dart';
import '../../../../providers/all_providers.dart';

class RestaurantInfo extends ConsumerWidget {
  final Restaurant restaurant;

  const RestaurantInfo({
    super.key,
    required this.restaurant,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFav = ref.watch(
      favoritesNotifierProvider.select((ids) => ids.contains(restaurant.id)),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: defaultPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  restaurant.name,
                  style: Theme.of(context).textTheme.headlineMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                onPressed: () => ref
                    .read(favoritesNotifierProvider.notifier)
                    .toggleFavorite(restaurant.id),
                icon: Icon(
                  isFav ? Icons.favorite : Icons.favorite_border,
                  color: isFav ? Colors.redAccent : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: defaultPadding / 2),
          Text(
            restaurant.address,
            style: Theme.of(context).textTheme.bodyMedium,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: defaultPadding / 2),
          RatingWithCounter(
            rating: restaurant.rating,
            numOfRating: restaurant.totalOrders,
          ),
          const SizedBox(height: defaultPadding),
          Row(
            children: [
              DeliveryInfo(
                iconSrc: "assets/icons/delivery.svg",
                text: tr('free'),
                subText: tr('delivery'),
              ),
              const SizedBox(width: defaultPadding),
              DeliveryInfo(
                iconSrc: "assets/icons/clock.svg",
                text: "35",
                subText: tr('minutes'),
              ),
              const Spacer(),
              OutlinedButton(
                onPressed: () {},
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text("Take away"),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class DeliveryInfo extends StatelessWidget {
  const DeliveryInfo({
    super.key,
    required this.iconSrc,
    required this.text,
    required this.subText,
  });

  final String iconSrc, text, subText;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SvgPicture.asset(
          iconSrc,
          height: 20,
          width: 20,
          colorFilter: const ColorFilter.mode(
            primaryColor,
            BlendMode.srcIn,
          ),
        ),
        const SizedBox(width: 8),
        Text.rich(
          TextSpan(
            text: "$text\n",
            style: Theme.of(context).textTheme.labelLarge,
            children: [
              TextSpan(
                text: subText,
                style: Theme.of(context)
                    .textTheme
                    .labelSmall!
                    .copyWith(fontWeight: FontWeight.normal),
              )
            ],
          ),
        ),
      ],
    );
  }
}
