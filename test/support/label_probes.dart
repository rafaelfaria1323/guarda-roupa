import 'dart:typed_data';

import 'package:guarda_roupa/features/photo_ai/domain/label_auto_shutter.dart';

/// Riscas finas, como letra miúda nítida. [shift] desloca-as (câmara a
/// mexer).
LabelProbe sharpProbe({int shift = 0}) {
  const w = 60;
  const h = 40;
  final gray = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      gray[y * w + x] = ((x + shift) ~/ 2).isEven ? 30 : 230;
    }
  }
  return LabelProbe(w, h, gray);
}

/// Uma superfície lisa: nada para ler.
LabelProbe flatProbe([int value = 120]) =>
    LabelProbe(60, 40, Uint8List(60 * 40)..fillRange(0, 60 * 40, value));
