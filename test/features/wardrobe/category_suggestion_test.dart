import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/features/wardrobe/domain/category_suggestion.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_category.dart';
import 'package:image/image.dart' as img;

CategoryTexts texts(Map<String, List<double>> m) =>
    CategoryTexts.fromJson({'categories': m})!;

void main() {
  group('FashionClip.input', () {
    test('lado menor a 224, recorte central e normalização do CLIP', () {
      // 448×224: o recorte central fica com a metade do meio (branca).
      final image = img.Image(width: 448, height: 224)
        ..clear(img.ColorRgb8(0, 0, 0));
      img.fillRect(
        image,
        x1: 112,
        y1: 0,
        x2: 335,
        y2: 223,
        color: img.ColorRgb8(255, 255, 255),
      );
      final x = FashionClip.input(img.encodePng(image))!;
      const plane = FashionClip.side * FashionClip.side;
      expect(x.length, 3 * plane);
      for (final i in [0, plane ~/ 2, plane - 1]) {
        expect(x[i], closeTo((1 - 0.48145466) / 0.26862954, 1e-3));
        expect(x[2 * plane + i], closeTo((1 - 0.40821073) / 0.27577711, 1e-3));
      }
    });

    test('imagem pequena amplia-se; ilegível dá null', () {
      final small = img.encodePng(
        img.Image(width: 30, height: 20)..clear(img.ColorRgb8(0, 0, 0)),
      );
      final x = FashionClip.input(small)!;
      expect(x[0], closeTo(-0.48145466 / 0.26862954, 1e-3));
      expect(FashionClip.input(Uint8List.fromList([1, 2])), isNull);
    });
  });

  group('FashionClip.rank', () {
    final t = texts({
      't_shirt': [1, 0, 0],
      'jeans': [0, 1, 0],
      'boots': [0, 0, 1],
      'dress': [1, 1, 0],
    });

    test('ordena pelo cosseno, sem depender da escala', () {
      expect(FashionClip.rank([10, 0.5, 0], t), [
        GarmentCategory.tShirt,
        GarmentCategory.dress,
        GarmentCategory.jeans,
      ]);
      expect(FashionClip.rank([0, 0, 3], t, top: 1), [GarmentCategory.boots]);
    });

    test('dimensão errada não sugere', () {
      expect(FashionClip.rank([1, 0], t), isEmpty);
    });
  });

  group('CategoryTexts.fromJson', () {
    test('rejeita categorias desconhecidas, valores e dimensões erradas', () {
      expect(CategoryTexts.fromJson(null), isNull);
      expect(
        CategoryTexts.fromJson({'categories': <String, Object?>{}}),
        isNull,
      );
      expect(
        CategoryTexts.fromJson({
          'categories': {
            'nope': [1.0],
          },
        }),
        isNull,
      );
      expect(
        CategoryTexts.fromJson({
          'categories': {
            'jeans': [1.0, 'x'],
          },
        }),
        isNull,
      );
      expect(
        CategoryTexts.fromJson({
          'categories': {
            'jeans': [1.0, 0.0],
            'boots': [1.0],
          },
        }),
        isNull,
      );
    });

    test('o asset tem todas as categorias menos "outra", em 512 dimensões', () {
      final json = jsonDecode(
        File('assets/models/fashionclip_categories.json').readAsStringSync(),
      );
      final t = CategoryTexts.fromJson(json)!;
      expect(
        t.embeddings.keys.toSet(),
        GarmentCategory.values.toSet()..remove(GarmentCategory.other),
      );
      expect(t.embeddings.values.every((e) => e.length == 512), isTrue);
    });
  });
}
