import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../domain/garment_color.dart';
import '../domain/reference_color.dart';

/// Escolha de cores e da proporção aproximada de cada uma (passos de 10%).
/// As cores escolhidas ou ajustadas aqui ficam confirmadas pelo utilizador;
/// as sugeridas pela foto ([onSuggest]) ficam marcadas até lá.
class ColorsEditor extends StatelessWidget {
  const ColorsEditor({
    required this.value,
    required this.onChanged,
    this.onSuggest,
    super.key,
  });

  static const maxColors = 5;

  final List<GarmentColor> value;
  final ValueChanged<List<GarmentColor>> onChanged;

  /// Sugerir pela foto; `null` sem foto (ou a processar).
  final VoidCallback? onSuggest;

  static int percentOf(GarmentColor c) => (c.proportion * 100).round();

  static int totalPercent(List<GarmentColor> colors) =>
      colors.fold(0, (sum, c) => sum + percentOf(c));

  static GarmentColor _color(int rgb, int percent) => GarmentColor.create(
    rgb: rgb,
    proportion: percent / 100,
    confirmed: true,
  )!;

  void _toggle(ReferenceColor color) {
    final existing = value.indexWhere((c) => c.rgb == color.rgb);
    if (existing >= 0) {
      onChanged([...value]..removeAt(existing));
      return;
    }
    if (value.length >= maxColors) return;
    final remaining = 100 - totalPercent(value);
    onChanged([...value, _color(color.rgb, remaining.clamp(10, 100))]);
  }

  void _setPercent(int index, int percent) {
    onChanged([
      for (final (i, c) in value.indexed)
        i == index ? _color(c.rgb, percent) : c,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final total = totalPercent(value);
    final suggested = value.any((c) => !c.confirmed);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.garmentColors,
                style: theme.textTheme.titleSmall,
              ),
            ),
            if (onSuggest != null)
              TextButton.icon(
                key: const Key('colors-from-photo'),
                onPressed: onSuggest,
                icon: const Icon(Icons.colorize_outlined),
                label: Text(l10n.colorsFromPhoto),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(l10n.garmentColorsHint, style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final color in ReferenceColor.values)
              ColorDot(
                key: Key('color-${color.id}'),
                rgb: color.rgb,
                label: l10n.colorLabel(color.id),
                selected: value.any((c) => c.rgb == color.rgb),
                onTap: () => _toggle(color),
              ),
          ],
        ),
        for (final (i, c) in value.indexed)
          Row(
            children: [
              ColorDot(rgb: c.rgb, label: _name(l10n, c), size: 24),
              const SizedBox(width: 8),
              SizedBox(
                width: 112,
                child: Text(
                  c.confirmed
                      ? _name(l10n, c)
                      : '${_name(l10n, c)} · ${l10n.colorSuggestedTag}',
                  key: Key('color-name-$i'),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Expanded(
                child: Slider(
                  key: Key('color-percent-$i'),
                  value: percentOf(c).clamp(10, 100).toDouble(),
                  min: 10,
                  max: 100,
                  divisions: 9,
                  label: '${percentOf(c)}%',
                  onChanged: (v) => _setPercent(i, v.round()),
                ),
              ),
              SizedBox(
                width: 44,
                child: Text('${percentOf(c)}%', textAlign: TextAlign.end),
              ),
            ],
          ),
        if (suggested)
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.colorsSuggestedHint,
                  style: theme.textTheme.bodySmall,
                ),
              ),
              TextButton(
                key: const Key('colors-confirm'),
                onPressed: () => onChanged([
                  for (final c in value)
                    GarmentColor.create(
                      rgb: c.rgb,
                      proportion: c.proportion,
                      confirmed: true,
                    )!,
                ]),
                child: Text(l10n.colorsConfirm),
              ),
            ],
          ),
        if (value.isNotEmpty)
          Text(
            total > 100
                ? l10n.garmentColorsExceed
                : value.length >= maxColors
                ? l10n.garmentColorsMax(maxColors)
                : l10n.garmentColorRemaining(100 - total),
            style: total > 100
                ? theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  )
                : theme.textTheme.bodySmall,
          ),
      ],
    );
  }

  static String _name(AppLocalizations l10n, GarmentColor c) =>
      l10n.colorLabel(ReferenceColor.fromRgb(c.rgb)?.id ?? 'custom');
}

/// Círculo de cor tocável (com visto quando escolhida).
class ColorDot extends StatelessWidget {
  const ColorDot({
    required this.rgb,
    required this.label,
    this.selected = false,
    this.onTap,
    this.size = 36,
    super.key,
  });

  final int rgb;
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = Color(0xFF000000 | rgb);
    final dark = color.computeLuminance() < 0.4;
    return Tooltip(
      message: label,
      child: Semantics(
        button: onTap != null,
        selected: selected,
        label: label,
        child: InkResponse(
          onTap: onTap,
          radius: size / 2 + 4,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? scheme.primary : scheme.outlineVariant,
                width: selected ? 3 : 1,
              ),
            ),
            child: selected
                ? Icon(
                    Icons.check,
                    size: size * 0.55,
                    color: dark ? Colors.white : Colors.black,
                  )
                : null,
          ),
        ),
      ),
    );
  }
}
