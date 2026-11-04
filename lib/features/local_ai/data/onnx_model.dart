import 'dart:typed_data';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import '../domain/local_model.dart';
import 'ort_loader.dart';

/// Um modelo ONNX com uma entrada e uma saída float. A sessão abre-se no
/// primeiro uso e fica aberta até [close]; se abrir falhar, tenta de novo
/// no uso seguinte.
final class OnnxModel {
  OnnxModel(this._store, this._model);

  final ModelStore _store;
  final LocalModel _model;
  Future<OrtSession>? _session;

  Future<OrtSession> _open() async {
    await ensureOrtLoaded();
    return OnnxRuntime().createSession(await _store.location(_model));
  }

  /// A primeira saída, achatada; `null` se não houver.
  Future<List<num>?> run(Float32List input, List<int> shape) async {
    final opening = _session ??= _open();
    final OrtSession session;
    try {
      session = await opening;
    } on Object {
      _session = null;
      rethrow;
    }
    final tensor = await OrtValue.fromList(input, shape);
    try {
      final outputs = await session.run({session.inputNames.first: tensor});
      try {
        final first = outputs[session.outputNames.first];
        if (first == null) return null;
        return (await first.asFlattenedList()).cast<num>();
      } finally {
        for (final v in outputs.values) {
          await v.dispose();
        }
      }
    } finally {
      await tensor.dispose();
    }
  }

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
