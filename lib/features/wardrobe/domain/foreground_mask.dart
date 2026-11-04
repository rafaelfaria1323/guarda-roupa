import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Onde está a peça numa foto: uma grelha quadrada de 0 (fundo) a 255
/// (peça), esticada sobre a foto inteira.
final class ForegroundMask {
  ForegroundMask(this.side, this.values) : assert(values.length == side * side);

  final int side;
  final Uint8List values;

  /// [u] e [v] em [0, 1): posição relativa na foto.
  bool isForeground(double u, double v) {
    final x = (u * side).floor().clamp(0, side - 1);
    final y = (v * side).floor().clamp(0, side - 1);
    return values[y * side + x] >= 128;
  }

  /// Fração da foto que é peça.
  double get share {
    var n = 0;
    for (final v in values) {
      if (v >= 128) n++;
    }
    return n / values.length;
  }
}

/// Entrada e saída do U²-Netp (recorte de fundo), como no `rembg`:
/// imagem 320×320, dividida pelo valor máximo e normalizada com as médias
/// e desvios do ImageNet; a saída (já com sigmoide) normaliza-se para 0–1.
abstract final class U2Netp {
  static const side = 320;
  static const _mean = [0.485, 0.456, 0.406];
  static const _std = [0.229, 0.224, 0.225];

  /// Tensor `[1, 3, 320, 320]` (NCHW). `null` se a imagem não se ler.
  static Float32List? input(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null || decoded.width == 0 || decoded.height == 0) {
      return null;
    }
    final image = img.copyResize(
      decoded,
      width: side,
      height: side,
      interpolation: img.Interpolation.linear,
    );
    final plane = side * side;
    final rgb = Float32List(plane * 3);
    var max = 0.0;
    for (var y = 0; y < side; y++) {
      for (var x = 0; x < side; x++) {
        final p = image.getPixel(x, y);
        final i = y * side + x;
        final scale = 255 / p.maxChannelValue;
        rgb[i] = p.r * scale;
        rgb[plane + i] = p.g * scale;
        rgb[2 * plane + i] = p.b * scale;
      }
    }
    for (final v in rgb) {
      if (v > max) max = v;
    }
    if (max < 1e-6) max = 1e-6;
    for (var c = 0; c < 3; c++) {
      for (var i = 0; i < plane; i++) {
        final k = c * plane + i;
        rgb[k] = (rgb[k] / max - _mean[c]) / _std[c];
      }
    }
    return rgb;
  }

  /// A primeira saída (`[1, 1, 320, 320]`, achatada) como máscara.
  static ForegroundMask? output(List<num> values) {
    if (values.length != side * side) return null;
    var lo = double.infinity;
    var hi = double.negativeInfinity;
    for (final v in values) {
      final d = v.toDouble();
      if (d < lo) lo = d;
      if (d > hi) hi = d;
    }
    final range = hi - lo;
    if (!range.isFinite || range < 1e-6) return null;
    return ForegroundMask(
      side,
      Uint8List.fromList([
        for (final v in values) ((v - lo) / range * 255).round().clamp(0, 255),
      ]),
    );
  }
}
