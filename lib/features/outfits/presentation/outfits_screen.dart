import 'package:flutter/material.dart';

import '../../../core/widgets/empty_state.dart';
import '../../../l10n/app_localizations.dart';

class OutfitsScreen extends StatelessWidget {
  const OutfitsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return EmptyState(
      icon: Icons.style_outlined,
      message: l10n.outfitsEmpty,
      hint: l10n.outfitsEmptyHint,
    );
  }
}
