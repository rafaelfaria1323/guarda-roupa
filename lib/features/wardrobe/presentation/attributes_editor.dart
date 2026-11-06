import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../domain/garment_attributes.dart';

/// Secção "Detalhes" do formulário: atributos opcionais. Nada escolhido é
/// "não sei"; voltar a tocar na opção escolhida desfaz a escolha.
///
/// O material e os cuidados vêm dos [material] e [care] do formulário, para
/// serem validados com os outros campos.
class AttributesEditor extends StatelessWidget {
  const AttributesEditor({
    required this.value,
    required this.onChanged,
    required this.material,
    required this.care,
    required this.maxLength,
    super.key,
  });

  final GarmentAttributes value;
  final ValueChanged<GarmentAttributes> onChanged;
  final TextEditingController material;
  final TextEditingController care;
  final String? Function(String?) Function(int max) maxLength;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final known =
        !value.isEmpty || material.text.isNotEmpty || care.text.isNotEmpty;
    return ExpansionTile(
      key: const Key('garment-details'),
      title: Text(l10n.garmentDetails),
      subtitle: Text(l10n.garmentDetailsHint),
      initiallyExpanded: known,
      // Os campos de texto têm de existir fechada, para validar.
      maintainState: true,
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Choice(
          title: l10n.garmentPattern,
          keyPrefix: 'pattern',
          values: GarmentPattern.values,
          idOf: (v) => v.id,
          label: (v) => l10n.patternLabel(v.id),
          selected: value.pattern,
          onSelected: (v) => onChanged(value.copyWith(pattern: () => v)),
        ),
        _Choice(
          title: l10n.garmentTexture,
          keyPrefix: 'texture',
          values: SurfaceTexture.values,
          idOf: (v) => v.id,
          label: (v) => l10n.textureLabel(v.id),
          selected: value.texture,
          onSelected: (v) => onChanged(value.copyWith(texture: () => v)),
        ),
        _Choice(
          title: l10n.garmentWarmth,
          keyPrefix: 'warmth',
          values: Warmth.values,
          idOf: (v) => v.id,
          label: (v) => l10n.warmthLabel(v.id),
          selected: value.warmth,
          onSelected: (v) => onChanged(value.copyWith(warmth: () => v)),
        ),
        _YesNo(
          title: l10n.garmentRain,
          keyPrefix: 'rain',
          value: value.rainOk,
          onChanged: (v) => onChanged(value.copyWith(rainOk: () => v)),
        ),
        _YesNo(
          title: l10n.garmentWind,
          keyPrefix: 'wind',
          value: value.windOk,
          onChanged: (v) => onChanged(value.copyWith(windOk: () => v)),
        ),
        _Choice(
          title: l10n.garmentFormality,
          keyPrefix: 'formality',
          values: Formality.values,
          idOf: (v) => v.id,
          label: (v) => l10n.formalityLabel(v.id),
          selected: value.formality,
          onSelected: (v) => onChanged(value.copyWith(formality: () => v)),
        ),
        _Title(l10n.garmentOccasions),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final o in Occasion.values)
              FilterChip(
                key: Key('occasion-${o.id}'),
                label: Text(l10n.occasionLabel(o.id)),
                selected: value.occasions.contains(o),
                onSelected: (on) => onChanged(
                  value.copyWith(
                    occasions: on
                        ? {...value.occasions, o}
                        : value.occasions.difference({o}),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        TextFormField(
          key: const Key('garment-material'),
          controller: material,
          decoration: InputDecoration(
            labelText: l10n.garmentMaterial,
            border: const OutlineInputBorder(),
          ),
          validator: maxLength(GarmentAttributes.maxMaterialLength),
        ),
        const SizedBox(height: 16),
        TextFormField(
          key: const Key('garment-care'),
          controller: care,
          decoration: InputDecoration(
            labelText: l10n.garmentCare,
            border: const OutlineInputBorder(),
          ),
          minLines: 1,
          maxLines: 4,
          validator: maxLength(GarmentAttributes.maxCareLength),
        ),
      ],
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 8),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );
}

class _Choice<T> extends StatelessWidget {
  const _Choice({
    required this.title,
    required this.keyPrefix,
    required this.values,
    required this.idOf,
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String title;
  final String keyPrefix;
  final List<T> values;
  final String Function(T) idOf;
  final String Function(T) label;
  final T? selected;
  final ValueChanged<T?> onSelected;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _Title(title),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final v in values)
            ChoiceChip(
              key: Key('$keyPrefix-${idOf(v)}'),
              label: Text(label(v)),
              selected: selected == v,
              onSelected: (on) => onSelected(on ? v : null),
            ),
        ],
      ),
    ],
  );
}

class _YesNo extends StatelessWidget {
  const _YesNo({
    required this.title,
    required this.keyPrefix,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String keyPrefix;
  final bool? value;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final options = <(bool?, String, String)>[
      (true, 'yes', l10n.answerYes),
      (false, 'no', l10n.answerNo),
      (null, 'unknown', l10n.answerUnknown),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Title(title),
        Wrap(
          spacing: 8,
          children: [
            for (final (v, id, text) in options)
              ChoiceChip(
                key: Key('$keyPrefix-$id'),
                label: Text(text),
                selected: value == v,
                onSelected: (_) => onChanged(v),
              ),
          ],
        ),
      ],
    );
  }
}
