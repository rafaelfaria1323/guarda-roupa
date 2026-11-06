import 'dart:typed_data';

import '../../../core/domain/result.dart';
import '../../local_ai/domain/background_remover.dart';
import '../../local_ai/domain/category_suggester.dart';
import '../../photo_ai/domain/photo_reader.dart';
import '../data/photo_processor.dart';
import '../domain/foreground_mask.dart';
import '../domain/garment.dart';
import '../domain/garment_attributes.dart';
import '../domain/garment_category.dart';
import '../domain/garment_color.dart';
import '../domain/garment_photo.dart';
import '../domain/photo_colors.dart';
import '../domain/wardrobe_repository.dart';

/// Quantas fotos de uma vez (cada uma é uma peça e conta para a quota).
const batchMaxPhotos = 20;

/// O que aconteceu a uma foto de "Várias fotos de uma vez".
sealed class BatchOutcome {
  const BatchOutcome();
}

/// Peça criada. [suggestions] são as categorias prováveis pela foto (a
/// primeira já escolhida); vazio sem o modelo neste dispositivo.
final class BatchCreated extends BatchOutcome {
  const BatchCreated(this.garment, this.suggestions, {this.readFailure});

  final Garment garment;
  final List<GarmentCategory> suggestions;

  /// Porque o Gemini não leu a foto (seguiu-se sem ele); `null` = leu ou
  /// não estava ligado.
  final PhotoReadFailure? readFailure;
}

/// A foto não serviu ([problem] `null` = a peça não se gravou).
final class BatchFailed extends BatchOutcome {
  const BatchFailed(this.problem);

  final PhotoProblem? problem;
}

/// Uma peça a partir de uma foto, como se fosse introduzida à mão, mas com
/// o que a foto sugere: a categoria mais provável (sem o modelo, "Outro") e
/// as cores, sem o fundo quando há recorte. As cores ficam por confirmar e
/// a categoria muda-se depois com um toque. Nada aqui lança: o que falhar
/// segue sem essa sugestão.
///
/// Com o Gemini ligado ([reader]), é ele que lê a categoria, o nome, as
/// cores e os atributos; se falhar, segue pelo caminho deste dispositivo.
Future<BatchOutcome> addPhotoAsGarment(
  Uint8List bytes, {
  required WardrobeRepository repo,
  required Future<PhotoProcessing> Function(Uint8List) process,
  CategorySuggester? suggester,
  BackgroundRemover? remover,
  PhotoReader? reader,
}) async {
  final ProcessedPhoto photo;
  switch (await process(bytes)) {
    case Err(:final failure):
      return BatchFailed(failure);
    case Ok(:final value):
      photo = value;
  }
  final thumb = photo.thumb;

  GarmentReading? reading;
  PhotoReadFailure? readFailure;
  if (reader != null) {
    try {
      switch (await reader.readGarment(photo.main)) {
        case Ok(:final value):
          reading = value;
        case Err(:final failure):
          readFailure = failure;
      }
    } on Object {
      readFailure = PhotoReadFailure.failed;
    }
  }

  var suggestions = const <GarmentCategory>[];
  if (reading?.category case final category?) {
    suggestions = [category];
  } else if (suggester != null) {
    try {
      suggestions = await suggester.suggest(thumb) ?? const [];
    } on Object {
      suggestions = const [];
    }
  }
  var colors = reading?.colors ?? const <GarmentColor>[];
  if (colors.isEmpty) {
    ForegroundMask? mask;
    if (remover != null) {
      try {
        mask = await remover.mask(thumb);
      } on Object {
        mask = null;
      }
    }
    try {
      colors = PhotoColors.suggest(thumb, mask: mask);
    } on Object {
      colors = const [];
    }
  }

  final created = await repo.addGarment(
    GarmentDraft(
      category: suggestions.firstOrNull ?? GarmentCategory.other,
      name: reading?.name,
      colors: colors,
      attributes:
          reading?.fillUnknown(const GarmentAttributes()) ??
          const GarmentAttributes(),
    ),
  );
  if (created case Ok(value: final garment)) {
    final withPhoto = await repo.addPhoto(garment.id, photo);
    return BatchCreated(
      switch (withPhoto) {
        Ok(:final value) => value,
        Err() => garment,
      },
      suggestions,
      readFailure: readFailure,
    );
  }
  return const BatchFailed(null);
}

/// A mesma peça com outra categoria.
GarmentDraft withCategory(Garment g, GarmentCategory category) => GarmentDraft(
  category: category,
  name: g.name,
  brand: g.brand,
  notes: g.notes,
  colors: g.colors,
  attributes: g.attributes,
);
