import 'package:flutter/material.dart';

import '../../../core/widgets/empty_state.dart';
import '../../../l10n/app_localizations.dart';

class StyleScreen extends StatelessWidget {
  const StyleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return EmptyState(
      icon: Icons.auto_awesome_outlined,
      message: l10n.styleEmpty,
      hint: l10n.styleEmptyHint,
    );
  }
}
