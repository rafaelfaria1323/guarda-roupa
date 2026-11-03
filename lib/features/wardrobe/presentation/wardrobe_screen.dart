import 'package:flutter/material.dart';

import '../../../core/widgets/empty_state.dart';
import '../../../l10n/app_localizations.dart';

class WardrobeScreen extends StatelessWidget {
  const WardrobeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return EmptyState(
      icon: Icons.checkroom_outlined,
      message: l10n.wardrobeEmpty,
      hint: l10n.wardrobeEmptyHint,
    );
  }
}
