import 'dart:async';
import 'dart:typed_data';

import 'package:guarda_roupa/features/local_ai/domain/background_remover.dart';
import 'package:guarda_roupa/features/local_ai/domain/local_model.dart';
import 'package:guarda_roupa/features/wardrobe/domain/foreground_mask.dart';

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
