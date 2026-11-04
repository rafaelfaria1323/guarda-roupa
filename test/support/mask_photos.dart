import 'dart:typed_data';

import 'package:guarda_roupa/features/wardrobe/domain/foreground_mask.dart';
import 'package:image/image.dart' as img;

/// Peça vermelha (retângulo central) num fundo bege em gradiente: a borda
/// não tem uma cor dominante e o método simples deixa o fundo entrar.
Uint8List gradientPhoto() {
  const w = 200;
  const h = 250;
  final image = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    final f = 0.75 + 0.35 * y / h;
    for (var x = 0; x < w; x++) {
      image.setPixelRgb(
        x,
        y,
        (215 * f).clamp(0, 255).round(),
        (200 * f).clamp(0, 255).round(),
        (175 * f).clamp(0, 255).round(),
      );
    }
  }
  img.fillRect(
    image,
    x1: 50,
    y1: 40,
    x2: 149,
    y2: 219,
    color: img.ColorRgb8(0xC0, 0x39, 0x2B),
  );
  return img.encodePng(image);
}

/// Máscara do mesmo retângulo, como a daria o recorte.
ForegroundMask rectMask() {
  const side = U2Netp.side;
  final values = Uint8List(side * side);
  for (var y = 0; y < side; y++) {
    for (var x = 0; x < side; x++) {
      final u = (x + 0.5) / side;
      final v = (y + 0.5) / side;
      if (u >= 0.25 && u < 0.75 && v >= 0.16 && v < 0.88) {
        values[y * side + x] = 255;
      }
    }
  }
  return ForegroundMask(side, values);
}
