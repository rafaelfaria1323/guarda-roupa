import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';

/// Escolha de um valor de política: predefinido (`null`), `0` ou N.
class PolicyValueField extends StatelessWidget {
  const PolicyValueField({
    required this.value,
    required this.defaultValue,
    required this.onChanged,
    required this.label,
    required this.describe,
    required this.choices,
    super.key,
  });

  /// Aviso de lavagem: sem aviso, após cada utilização, após N.
  factory PolicyValueField.laundry({
    required BuildContext context,
    required int? value,
    required int defaultValue,
    required ValueChanged<int?> onChanged,
    String? label,
    Key? key,
  }) {
    final l10n = AppLocalizations.of(context);
    return PolicyValueField(
      key: key,
      value: value,
      defaultValue: defaultValue,
      onChanged: onChanged,
      label: label ?? l10n.laundryAfterLabel,
      describe: l10n.laundryAfterValue,
      choices: const [0, 1, 2, 3, 4, 5, 6, 7, 8, 10],
    );
  }

  /// Rotação: sem intervalo ou N dias entre utilizações.
  factory PolicyValueField.rotation({
    required BuildContext context,
    required int? value,
    required int defaultValue,
    required ValueChanged<int?> onChanged,
    String? label,
    Key? key,
  }) {
    final l10n = AppLocalizations.of(context);
    return PolicyValueField(
      key: key,
      value: value,
      defaultValue: defaultValue,
      onChanged: onChanged,
      label: label ?? l10n.rotationDaysLabel,
      describe: l10n.rotationDaysValue,
      choices: const [0, 1, 2, 3, 4, 5, 7, 10, 14],
    );
  }

  final int? value;
  final int defaultValue;
  final ValueChanged<int?> onChanged;
  final String label;
  final String Function(int) describe;
  final List<int> choices;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final current = value;
    final all = [
      ...choices,
      if (current != null && !choices.contains(current)) current,
    ];
    return DropdownButtonFormField<int?>(
      initialValue: current,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        DropdownMenuItem<int?>(
          child: Text(l10n.laundryDefault(describe(defaultValue))),
        ),
        for (final n in all)
          DropdownMenuItem<int?>(value: n, child: Text(describe(n))),
      ],
      onChanged: onChanged,
    );
  }
}
