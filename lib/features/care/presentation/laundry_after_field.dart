import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';

/// Escolha do aviso de lavagem: predefinido (`null`), sem aviso (`0`) ou
/// após N utilizações.
class LaundryAfterField extends StatelessWidget {
  const LaundryAfterField({
    required this.value,
    required this.defaultValue,
    required this.onChanged,
    this.label,
    super.key,
  });

  final int? value;
  final int defaultValue;
  final ValueChanged<int?> onChanged;
  final String? label;

  static const _choices = [0, 1, 2, 3, 4, 5, 6, 7, 8, 10];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final current = value;
    final choices = [
      ..._choices,
      if (current != null && !_choices.contains(current)) current,
    ];
    return DropdownButtonFormField<int?>(
      initialValue: current,
      isExpanded: true,
      decoration: InputDecoration(labelText: label ?? l10n.laundryAfterLabel),
      items: [
        DropdownMenuItem<int?>(
          child: Text(
            l10n.laundryDefault(l10n.laundryAfterValue(defaultValue)),
          ),
        ),
        for (final n in choices)
          DropdownMenuItem<int?>(
            value: n,
            child: Text(l10n.laundryAfterValue(n)),
          ),
      ],
      onChanged: onChanged,
    );
  }
}
