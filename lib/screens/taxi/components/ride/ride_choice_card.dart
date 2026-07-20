import 'package:flutter/material.dart';
import 'package:nomade_client/models/ride_choice.dart';
import 'package:nomade_client/constants.dart';
import 'package:nomade_client/theme/app_colors.dart';

/// Card pour un choix de véhicule – Design horizontal compact (style Uber/Bolt)
/// Utilisé dans TaxiHomeScreen pour la sélection de véhicule
class RideChoiceCard extends StatelessWidget {
  const RideChoiceCard({
    super.key,
    required this.ride,
    required this.onTap,
    required this.c,
    this.distance = 0.0,
    this.isSelected = false,
  });

  final RideChoice ride;
  final double distance; // 0 si pas de destination (affiche prix de base)
  final VoidCallback onTap;
  final bool isSelected;
  final AppColors c;

  @override
  Widget build(BuildContext context) {
    final price = distance > 0
        ? ride.calculatePrice(distance)
        : ride.basePrice;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? kNeonGreen : c.surfaceLow,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha:isSelected ? 0.15 : 0.06),
              blurRadius: isSelected ? 14 : 8,
              offset: const Offset(0, 4),
            ),
          ],
          border: isSelected
              ? null
              : Border.all(color: c.outlineVariant),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Badge "Pop" si applicable (standard ou comfort)
            if (ride.id == 'standard' || ride.id == 'comfort')
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                margin: const EdgeInsets.only(bottom: 4),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Colors.orange, Colors.deepOrange],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  '🔥 Pop',
                  style: TextStyle(
                    fontSize: 8,
                    color: blanc,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

            // Image véhicule
            SizedBox(
              height: 65,
              child: Image.asset(
                _getVehicleImage(),
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => Icon(
                  Icons.directions_car,
                  size: 48,
                  color: isSelected ? kNeonGreenDark : vertPrincipal,
                ),
              ),
            ),
            const SizedBox(height: 6),

            // Nom véhicule
            Text(
              ride.name,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: isSelected ? kNeonGreenDark : c.onSurface,
              ),
            ),

            // Climatisation : réservée au Confort
            if (ride.type == RideType.comfort)
              Text(
                '+ clim',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? kNeonGreenDark : drapeauVert,
                ),
              ),
            const SizedBox(height: 2),

            // Délai d'arrivée
            if (ride.estimatedArrivalTime != null)
              Text(
                ride.estimatedArrivalTime!,
                style: TextStyle(
                  fontSize: 10,
                  color: isSelected ? kNeonGreenDark.withValues(alpha: 0.7) : c.onSurfaceVariant,
                ),
              ),
            const SizedBox(height: 3),

            // Prix
            Text(
              '${price.toStringAsFixed(0)} FDJ',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isSelected ? kNeonGreenDark : drapeauVert,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Chemins d'images pour les 3 types de véhicules
  String _getVehicleImage() {
    switch (ride.type) {
      case RideType.standard:
        return 'assets/vehicule/taxi-B.png';
      case RideType.comfort:
        return 'assets/vehicule/taxi-A.png';
      case RideType.van:
        return 'assets/vehicule/taxiprobox.png';
      default:
        return 'assets/vehicule/taxi-A.png';
    }
  }
}