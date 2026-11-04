import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/features/wardrobe/domain/photo_colors.dart';
import 'package:guarda_roupa/features/wardrobe/domain/reference_color.dart';
import 'package:image/image.dart' as img;

img.ColorRgb8 rgb(ReferenceColor c) =>
    img.ColorRgb8((c.rgb >> 16) & 0xFF, (c.rgb >> 8) & 0xFF, c.rgb & 0xFF);

/// Fundo [bg] com um retângulo central (60 % de cada lado) feito de faixas
/// verticais [stripes].
Uint8List photo(
  ReferenceColor bg,
  List<ReferenceColor> stripes, {
  int w = 200,
  int h = 160,
}) {
  final image = img.Image(width: w, height: h)..clear(rgb(bg));
  final x0 = (w * 0.2).round();
  final x1 = (w * 0.8).round();
  final band = (x1 - x0) / stripes.length;
  for (final (i, c) in stripes.indexed) {
    img.fillRect(
      image,
      x1: (x0 + band * i).round(),
      y1: (h * 0.2).round(),
      x2: (x0 + band * (i + 1)).round() - 1,
      y2: (h * 0.8).round() - 1,
      color: rgb(c),
    );
  }
  return img.encodePng(image);
}

Map<ReferenceColor?, int> percents(Uint8List bytes) => {
  for (final c in PhotoColors.suggest(bytes))
    ReferenceColor.fromRgb(c.rgb): (c.proportion * 100).round(),
};

void main() {
  test('peça de uma cor num fundo: tira o fundo', () {
    expect(percents(photo(ReferenceColor.white, [ReferenceColor.red])), {
      ReferenceColor.red: 100,
    });
  });

  test('duas cores, metade cada', () {
    expect(
      percents(
        photo(ReferenceColor.grey, [ReferenceColor.navy, ReferenceColor.beige]),
      ),
      {ReferenceColor.navy: 50, ReferenceColor.beige: 50},
    );
  });

  test('peça da cor do fundo: não a apaga', () {
    expect(percents(photo(ReferenceColor.white, [ReferenceColor.white])), {
      ReferenceColor.white: 100,
    });
  });

  test('cores próximas da referência vão para ela', () {
    final image = img.Image(width: 50, height: 50)
      ..clear(img.ColorRgb8(0x2A, 0x36, 0x52)); // quase azul-marinho
    expect(percents(img.encodePng(image)), {ReferenceColor.navy: 100});
  });

  test('sugestões ficam por confirmar e somam 100 %', () {
    final colors = PhotoColors.suggest(
      photo(ReferenceColor.white, [
        ReferenceColor.red,
        ReferenceColor.green,
        ReferenceColor.blue,
      ]),
    );
    expect(colors, hasLength(3));
    expect(colors.every((c) => !c.confirmed), isTrue);
    expect(colors.fold(0, (s, c) => s + (c.proportion * 100).round()), 100);
  });

  test('ficheiro que não é imagem: nada', () {
    expect(PhotoColors.suggest(Uint8List.fromList([1, 2, 3])), isEmpty);
  });
}
