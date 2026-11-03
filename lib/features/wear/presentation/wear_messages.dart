import 'package:flutter/material.dart';

import '../../../core/domain/result.dart';
import '../../../l10n/app_localizations.dart';
import '../domain/wear_repository.dart';

/// Mostra a falha de uma escrita de utilização; devolve se correu bem.
bool reportWear<T>(BuildContext context, WearResult<T> result) {
  final l10n = AppLocalizations.of(context);
  final message = switch (result) {
    Ok() => null,
    Err(failure: InvalidWear(:final problem)) => l10n.wearProblem(problem.name),
    Err(failure: WearNotFound()) => l10n.wearNotFound,
    Err(failure: WearStorageFailure()) => l10n.wearSaveFailed,
  };
  if (message == null) return true;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
  return false;
}
