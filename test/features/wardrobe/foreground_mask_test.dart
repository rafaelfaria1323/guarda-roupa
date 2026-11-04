import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/features/wardrobe/domain/foreground_mask.dart';
import 'package:guarda_roupa/features/wardrobe/domain/photo_colors.dart';
import 'package:guarda_roupa/features/wardrobe/domain/reference_color.dart';
import 'package:image/image.dart' as img;

import '../../support/mask_photos.dart';

Map<ReferenceColor?, int> percents(Uint8List bytes, {ForegroundMask? mask}) => {
  for (final c in PhotoColors.suggest(bytes, mask: mask))
    ReferenceColor.fromRgb(c.rgb): (c.proportion * 100).round(),
};

void main() {
  group('U2Netp.input', () {
    test('NCHW 320×320 normalizado pelo máximo e pelo ImageNet', () {
      final png = img.encodePng(
        img.Image(width: 10, height: 8)..clear(img.ColorRgb8(255, 0, 0)),
      );
      final x = U2Netp.input(png)!;
      const plane = U2Netp.side * U2Netp.side;
      expect(x.length, 3 * plane);
      expect(x[0], closeTo((1 - 0.485) / 0.229, 1e-4));
      expect(x[plane], closeTo((0 - 0.456) / 0.224, 1e-4));
      expect(x[2 * plane + plane - 1], closeTo((0 - 0.406) / 0.225, 1e-4));
    });

    test('imagem ilegível', () {
      expect(U2Netp.input(Uint8List.fromList([1, 2, 3])), isNull);
    });
  });

  group('U2Netp.output', () {
    test('normaliza de 0 a 255', () {
      const n = U2Netp.side * U2Netp.side;
      final out = List<double>.generate(n, (i) => i < n / 2 ? 0.2 : 0.6);
      final m = U2Netp.output(out)!;
      expect(m.values.first, 0);
      expect(m.values.last, 255);
      expect(m.share, 0.5);
      expect(m.isForeground(0.5, 0.9), isTrue);
      expect(m.isForeground(0.5, 0.1), isFalse);
    });

    test('tamanho errado ou saída constante não dão máscara', () {
      expect(U2Netp.output([0.1, 0.2]), isNull);
      expect(
        U2Netp.output(List<double>.filled(U2Netp.side * U2Netp.side, 0.4)),
        isNull,
      );
    });
  });

  group('PhotoColors com máscara', () {
    test('sem máscara, o gradiente do fundo entra nas cores', () {
      final p = percents(gradientPhoto());
      expect(p[ReferenceColor.red], lessThan(100));
      expect(p.length, greaterThan(1));
    });

    test('com máscara, só conta a peça', () {
      expect(percents(gradientPhoto(), mask: rectMask()), {
        ReferenceColor.red: 100,
      });
    });

    test('máscara vazia ou cheia ignora-se', () {
      const side = U2Netp.side;
      final empty = ForegroundMask(side, Uint8List(side * side));
      final full = ForegroundMask(
        side,
        Uint8List(side * side)..fillRange(0, side * side, 255),
      );
      final plain = percents(gradientPhoto());
      expect(percents(gradientPhoto(), mask: empty), plain);
      expect(percents(gradientPhoto(), mask: full), plain);
    });
  });
}
