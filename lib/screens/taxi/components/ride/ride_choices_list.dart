import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nomade_client/models/ride_choice.dart';
import 'package:nomade_client/providers/all_providers.dart';
import 'package:nomade_client/theme/app_colors.dart';
import 'ride_choice_card.dart';

/// Liste des choix de véhicules
class RideChoicesList extends ConsumerStatefulWidget {
  const RideChoicesList({
    super.key,
    required this.distance,
    required this.onRideSelected,
    required this.c,
    this.selectedRideId,
  });

  final double distance;
  final ValueChanged<RideChoice> onRideSelected;
  final String? selectedRideId;
  final AppColors c;

  @override
  ConsumerState<RideChoicesList> createState() => _RideChoicesListState();
}

class _RideChoicesListState extends ConsumerState<RideChoicesList> {
  /// Véhicule sélectionné, mémorisé par ID : la liste est rechargée dès que
  /// l'admin change les tarifs, et l'instance `RideChoice` change avec elle.
  String? _selectedRideId;

  @override
  void initState() {
    super.initState();
    _selectedRideId = widget.selectedRideId;
  }

  @override
  Widget build(BuildContext context) {
    final rideChoices = ref.watch(rideChoicesProvider);
    final selectedRide = rideChoices.firstWhere(
      (r) => r.id == _selectedRideId,
      orElse: () => rideChoices.first,
    );

    return ListView.separated(
      // CORRECTION: Permet le scroll et enlève shrinkWrap
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: rideChoices.length,
      separatorBuilder: (context, index) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        final ride = rideChoices[index];
        final isSelected = ride.id == selectedRide.id;

        return RideChoiceCard(
          ride: ride,
          distance: widget.distance,
          isSelected: isSelected,
          c: widget.c,
          onTap: () {
            setState(() {
              _selectedRideId = ride.id;
            });
            widget.onRideSelected(ride);
          },
        );
      },
    );
  }
}