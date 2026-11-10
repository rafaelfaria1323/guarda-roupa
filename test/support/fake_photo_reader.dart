import 'dart:typed_data';

import 'package:guarda_roupa/core/domain/result.dart';
import 'package:guarda_roupa/features/photo_ai/domain/photo_reader.dart';

/// Gemini a fingir: devolve sempre [garment] e [label], e conta os pedidos.
final class FakePhotoReader implements PhotoReader {
  FakePhotoReader({
    this.garment = const Err(PhotoReadFailure.failed),
    this.label = const Err(PhotoReadFailure.failed),
  });

  Result<GarmentReading, PhotoReadFailure> garment;
  Result<LabelReading, PhotoReadFailure> label;
  final garmentPhotos = <Uint8List>[];
  final labelPhotos = <Uint8List>[];

  /// Fotos em cada leitura de etiqueta.
  final labelReads = <int>[];

  @override
  Future<Result<GarmentReading, PhotoReadFailure>> readGarment(
    Uint8List jpeg,
  ) async {
    garmentPhotos.add(jpeg);
    return garment;
  }

  @override
  Future<Result<LabelReading, PhotoReadFailure>> readLabel(
    List<Uint8List> jpegs,
  ) async {
    labelReads.add(jpegs.length);
    labelPhotos.addAll(jpegs);
    return label;
  }
}
