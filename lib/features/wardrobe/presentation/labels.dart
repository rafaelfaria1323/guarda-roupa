import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../domain/availability.dart';

IconData availabilityIcon(Availability availability) => switch (availability) {
  Availability.available => Icons.check_circle_outline,
  Availability.drying => Icons.air,
  Availability.washing => Icons.local_laundry_service_outlined,
  Availability.atCleaners => Icons.dry_cleaning_outlined,
  Availability.needsCleaning => Icons.cleaning_services_outlined,
};

class AvailabilityChip extends StatelessWidget {
  const AvailabilityChip({required this.availability, super.key});

  final Availability availability;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = availability.isAvailable ? scheme.primary : scheme.tertiary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(availabilityIcon(availability), size: 18, color: color),
        const SizedBox(width: 4),
        Text(
          AppLocalizations.of(context).availabilityLabel(availability.id),
          style: TextStyle(color: color),
        ),
      ],
    );
  }
}
