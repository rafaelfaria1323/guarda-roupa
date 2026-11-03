import 'package:flutter/material.dart';

import '../../../core/widgets/empty_state.dart';
import '../../../l10n/app_localizations.dart';
import '../../wear/presentation/today_wear_card.dart';

class PlannerScreen extends StatelessWidget {
  const PlannerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const TodayWearCard(),
        EmptyState(
          icon: Icons.calendar_today_outlined,
          message: l10n.plannerEmpty,
          hint: l10n.plannerEmptyHint,
        ),
      ],
    );
  }
}
