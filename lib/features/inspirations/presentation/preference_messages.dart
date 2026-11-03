import 'package:flutter/material.dart';

import '../../../core/domain/result.dart';
import '../../../l10n/app_localizations.dart';
import '../../wardrobe/domain/garment_attributes.dart';
import '../../wardrobe/domain/reference_color.dart';
import '../domain/inspiration.dart';
import '../domain/inspiration_repository.dart';
import '../domain/style_preference.dart';

/// Mostra o erro de uma operação; `true` se correu bem.
bool reportPreference<T>(BuildContext context, PreferenceResult<T> result) {
  final l10n = AppLocalizations.of(context);
  final message = switch (result) {
    Ok() => null,
    Err(failure: InvalidPreference()) => l10n.preferenceInvalid,
    Err(failure: DuplicatePreference()) => l10n.preferenceDuplicate,
    Err(failure: PreferenceNotFound()) => l10n.preferenceNotFound,
    Err(failure: PreferenceStorageFailure()) => l10n.preferenceSaveFailed,
  };
  if (message == null) return true;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
  return false;
}

/// Valores que se podem escolher para [subject] (cores: RGB em decimal).
List<String> preferenceValues(PreferenceSubject subject) => switch (subject) {
  PreferenceSubject.color => [
    for (final c in ReferenceColor.values) '${c.rgb}',
  ],
  PreferenceSubject.pattern => [for (final p in GarmentPattern.values) p.id],
  PreferenceSubject.texture => [for (final t in SurfaceTexture.values) t.id],
  PreferenceSubject.formality => [for (final f in Formality.values) f.id],
  PreferenceSubject.combo => [for (final c in StyleCombo.values) c.id],
};

String preferenceValueLabel(
  AppLocalizations l10n,
  PreferenceSubject subject,
  String value,
) => switch (subject) {
  PreferenceSubject.color => l10n.colorLabel(
    ReferenceColor.fromRgb(int.tryParse(value) ?? -1)?.id ?? 'custom',
  ),
  PreferenceSubject.pattern => l10n.patternLabel(value),
  PreferenceSubject.texture => l10n.textureLabel(value),
  PreferenceSubject.formality => l10n.formalityLabel(value),
  PreferenceSubject.combo => l10n.comboLabel(value),
};

/// "Gosto: Azul-marinho".
String preferenceTitle(AppLocalizations l10n, StylePreference p) =>
    l10n.preferenceTitle(
      p.stance.id,
      preferenceValueLabel(l10n, p.subject, p.value),
    );

/// "Cor · Sempre" ou "Padrão · Casual, Noite / saída".
String preferenceContext(AppLocalizations l10n, StylePreference p) => [
  l10n.preferenceSubjectLabel(p.subject.id),
  if (p.occasions.isEmpty)
    l10n.preferenceAlways
  else
    [
      for (final o in Occasion.values)
        if (p.occasions.contains(o)) l10n.occasionLabel(o.id),
    ].join(', '),
].join(' · ');
