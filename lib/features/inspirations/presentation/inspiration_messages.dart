import 'package:flutter/material.dart';

import '../../../core/domain/result.dart';
import '../../../l10n/app_localizations.dart';
import '../domain/inspiration.dart';
import '../domain/inspiration_repository.dart';

/// Mostra o erro de uma operação; `true` se correu bem.
bool reportInspiration<T>(BuildContext context, InspirationResult<T> result) {
  final l10n = AppLocalizations.of(context);
  final message = switch (result) {
    Ok() => null,
    Err(failure: InvalidInspiration(:final problem)) => inspirationProblem(
      l10n,
      problem,
    ),
    Err(failure: InspirationNotFound()) => l10n.inspirationNotFound,
    Err(failure: InspirationStorageFailure()) => l10n.inspirationSaveFailed,
  };
  if (message == null) return true;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
  return false;
}

String inspirationProblem(AppLocalizations l10n, InspirationProblem p) =>
    switch (p) {
      InspirationProblem.empty => l10n.inspirationEmptyDraft,
      InspirationProblem.titleTooLong => l10n.inspirationTitleTooLong,
      InspirationProblem.invalidUrl => l10n.inspirationInvalidUrl,
      InspirationProblem.notesTooLong => l10n.inspirationNotesTooLong,
      InspirationProblem.tooManyColors => l10n.inspirationTooManyColors,
    };

/// "Casual cuidado · Trabalho informal · Riscas", ou "Sem etiquetas".
String inspirationTags(AppLocalizations l10n, Inspiration i) {
  final parts = [
    if (i.formality case final f?) l10n.formalityLabel(f.id),
    for (final o in i.occasions) l10n.occasionLabel(o.id),
    for (final p in i.patterns) l10n.patternLabel(p.id),
    for (final t in i.textures) l10n.textureLabel(t.id),
  ];
  if (parts.isEmpty && i.palette.isEmpty) return l10n.inspirationNoTags;
  return parts.join(' · ');
}
