import 'package:flutter/material.dart';

import '../../../core/widgets/empty_state.dart';
import '../../../l10n/app_localizations.dart';

class PlannerScreen extends StatelessWidget {
  const PlannerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return EmptyState(
      icon: Icons.calendar_today_outlined,
      message: l10n.plannerEmpty,
      hint: l10n.plannerEmptyHint,
    );
  }
}
