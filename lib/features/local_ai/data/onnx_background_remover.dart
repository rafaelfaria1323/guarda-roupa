import 'dart:typed_data';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import '../../wardrobe/domain/foreground_mask.dart';
import '../domain/background_remover.dart';
import '../domain/local_model.dart';
import 'ort_loader.dart';

/// U²-Netp com o ONNX Runtime. A sessão abre-se no primeiro uso e fica
/// aberta até [close].
final class OnnxBackgroundRemover implements BackgroundRemover {
  OnnxBackgroundRemover(this._store, this._model);

  final ModelStore _store;
  final LocalModel _model;
  Future<OrtSession>? _session;

  Future<OrtSession> _open() async {
    await ensureOrtLoaded();
    return OnnxRuntime().createSession(await _store.location(_model));
  }

  @override
  Future<ForegroundMask?> mask(Uint8List bytes) async {
    final input = U2Netp.input(bytes);
    if (input == null) return null;
    final opening = _session ??= _open();
    final OrtSession session;
    try {
      session = await opening;
    } on Object {
      _session = null; // tenta de novo da próxima vez
      rethrow;
    }
    final tensor = await OrtValue.fromList(input, const [
      1,
      3,
      U2Netp.side,
      U2Netp.side,
    ]);
    try {
      final outputs = await session.run({session.inputNames.first: tensor});
      try {
        final first = outputs[session.outputNames.first];
        if (first == null) return null;
        return U2Netp.output((await first.asFlattenedList()).cast<num>());
      } finally {
        for (final v in outputs.values) {
          await v.dispose();
        }
      }
    } finally {
      await tensor.dispose();
    }
  }

  @override
  Future<void> close() async {
    final session = _session;
    _session = null;
    if (session == null) return;
    try {
      await (await session).close();
    } on Object {
      // Nunca chegou a abrir.
    }
  }
}
