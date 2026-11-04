import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'package:guarda_roupa/features/local_ai/domain/background_remover.dart';
import 'package:guarda_roupa/features/local_ai/domain/category_suggester.dart';
import 'package:guarda_roupa/features/local_ai/domain/image_embedder.dart';
import 'package:guarda_roupa/features/local_ai/domain/local_model.dart';
import 'package:guarda_roupa/features/wardrobe/domain/foreground_mask.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_category.dart';

/// Modelos em memória. [pending] controla a descarga em curso: o teste
/// envia o progresso e termina-a (ou falha-a).
final class FakeModelStore implements ModelStore {
  final ready = <String>{};
  StreamController<double>? pending;

  @override
  Future<bool> isReady(LocalModel model) async => ready.contains(model.id);

  @override
  Future<void> download(
    LocalModel model, {
    required void Function(double progress) onProgress,
  }) async {
    final c = pending = StreamController<double>();
    await for (final p in c.stream) {
      onProgress(p);
    }
    ready.add(model.id);
  }

  @override
  Future<void> remove(LocalModel model) async => ready.remove(model.id);

  @override
  Future<String> location(LocalModel model) async => 'memory:${model.id}';
}

/// Recorte programado: devolve sempre [result] (ou lança [failWith]).
final class FakeBackgroundRemover implements BackgroundRemover {
  FakeBackgroundRemover(this.result);

  final ForegroundMask? result;
  Object? failWith;
  var calls = 0;

  @override
  Future<ForegroundMask?> mask(Uint8List bytes) async {
    calls++;
    if (failWith case final e?) throw e;
    return result;
  }

  @override
  Future<void> close() async {}
}

/// Sugestão de categoria programada.
final class FakeCategorySuggester implements CategorySuggester {
  FakeCategorySuggester(this.result);

  final List<GarmentCategory>? result;
  var calls = 0;

  @override
  Future<List<GarmentCategory>?> suggest(Uint8List bytes) async {
    calls++;
    return result;
  }

  @override
  Future<void> close() async {}
}

/// Embedding programado pelo vermelho médio da imagem: imagens com
/// vermelho próximo ficam parecidas. `null` se não se ler.
final class FakeImageEmbedder implements ImageEmbedder {
  var calls = 0;

  @override
  String get modelId => 'fake';

  @override
  Future<Float32List?> embed(Uint8List bytes) async {
    calls++;
    final image = img.decodeImage(bytes);
    if (image == null) return null;
    var r = 0.0;
    for (final p in image) {
      r += p.r;
    }
    final angle = r / (image.width * image.height) / 255 * math.pi / 2;
    return Float32List.fromList([math.cos(angle), math.sin(angle)]);
  }

  @override
  Future<void> close() async {}
}
