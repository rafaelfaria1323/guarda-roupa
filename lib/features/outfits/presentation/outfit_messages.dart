import 'package:flutter/material.dart';

import '../../../core/domain/result.dart';
import '../../../l10n/app_localizations.dart';
import '../../wardrobe/domain/availability.dart';
import '../../wardrobe/domain/garment.dart';
import '../domain/outfit.dart';
import '../domain/outfit_repository.dart';

/// Mostra o erro de uma operação; `true` se correu bem.
bool reportOutfit<T>(BuildContext context, OutfitResult<T> result) {
  final l10n = AppLocalizations.of(context);
  final message = switch (result) {
    Ok() => null,
    Err(failure: InvalidOutfit(:final problem)) => switch (problem) {
      OutfitProblem.noItems => l10n.outfitNoItems,
      OutfitProblem.tooManyItems => l10n.outfitTooManyItems,
      OutfitProblem.duplicateGarment ||
      OutfitProblem.roleTaken => l10n.outfitRoleTaken,
      OutfitProblem.nameTooLong => l10n.outfitNameTooLong,
    },
    Err(failure: UnknownOutfitGarment()) => l10n.outfitUnknownGarment,
    Err(failure: OutfitNotFound()) => l10n.outfitNotFound,
    Err(failure: OutfitStorageFailure()) => l10n.outfitSaveFailed,
  };
  if (message == null) return true;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
  return false;
}

/// "Falta: calçado" / "Conjunto completo."
String outfitShape(AppLocalizations l10n, Iterable<OutfitItem> items) {
  final missing = OutfitRules.missing(items);
  if (missing.isEmpty) return l10n.outfitComplete;
  final names = [
    for (final r in OutfitRole.values)
      if (missing.contains(r)) l10n.outfitRoleLabel(r.id).toLowerCase(),
  ];
  return l10n.outfitMissing(names.join(', '));
}

/// Porque é que uma peça do conjunto não pode ser usada agora; `null` se
/// pode. Nunca muda nada sozinho: é só um aviso.
String? pieceWarning(AppLocalizations l10n, Garment? g) {
  if (g == null) return l10n.outfitGonePiece;
  if (g.isArchived) return l10n.outfitArchivedPiece;
  if (g.availability != Availability.available) {
    return l10n.availabilityLabel(g.availability.id);
  }
  return null;
}
