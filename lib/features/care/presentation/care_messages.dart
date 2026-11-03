import 'package:flutter/material.dart';

import '../../../core/domain/result.dart';
import '../../../l10n/app_localizations.dart';
import '../domain/care_repository.dart';

/// Mostra a falha de uma escrita; devolve se correu bem.
bool reportCare<T>(BuildContext context, CareResult<T> result) {
  final l10n = AppLocalizations.of(context);
  final message = switch (result) {
    Ok() => null,
    Err(failure: InvalidCare(:final problem)) => l10n.careProblem(problem.name),
    Err(failure: CleaningNotFound()) => l10n.careProblem('notFound'),
    Err(failure: CareStorageFailure()) => l10n.careSaveFailed,
  };
  if (message == null) return true;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
  return false;
}
