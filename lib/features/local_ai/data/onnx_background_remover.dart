import 'dart:typed_data';

import '../../wardrobe/domain/foreground_mask.dart';
import '../domain/background_remover.dart';
import '../domain/local_model.dart';
import 'onnx_model.dart';

/// U²-Netp com o ONNX Runtime.
final class OnnxBackgroundRemover implements BackgroundRemover {
  OnnxBackgroundRemover(ModelStore store, LocalModel model)
    : _model = OnnxModel(store, model);

  final OnnxModel _model;

  @override
  Future<ForegroundMask?> mask(Uint8List bytes) async {
    final input = U2Netp.input(bytes);
    if (input == null) return null;
    final out = await _model.run(input, const [1, 3, U2Netp.side, U2Netp.side]);
    return out == null ? null : U2Netp.output(out);
  }

  @override
  Future<void> close() => _model.close();
}
