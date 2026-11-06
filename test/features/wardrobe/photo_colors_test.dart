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

  test('fundo de estúdio em gradiente (bege a creme): tira o fundo', () {
    // Como as fotos da Massimo Dutti: o fundo cai entre duas cores de
    // referência e nenhuma chega sozinha a 60 % da borda.
    const w = 200, h = 160;
    final image = img.Image(width: w, height: h);
    for (var y = 0; y < h; y++) {
      final t = y / (h - 1);
      final c = img.ColorRgb8(
        (0xE0 + (0xEC - 0xE0) * t).round(),
        (0xD2 + (0xE0 - 0xD2) * t).round(),
        (0xB8 + (0xC8 - 0xB8) * t).round(),
      );
      for (var x = 0; x < w; x++) {
        image.setPixel(x, y, c);
      }
    }
    img.fillRect(
      image,
      x1: 60,
      y1: 40,
      x2: 139,
      y2: 119,
      color: rgb(ReferenceColor.navy),
    );
    expect(percents(img.encodePng(image)), {ReferenceColor.navy: 100});
  });

  test('detalhe pequeno e vivo entra como detalhe', () {
    // Como a estrela vermelha de uns ténis brancos num fundo de estúdio.
    const w = 200, h = 160;
    final image = img.Image(width: w, height: h)
      ..clear(rgb(ReferenceColor.grey));
    img.fillRect(
      image,
      x1: 40,
      y1: 40,
      x2: 159,
      y2: 119,
      color: rgb(ReferenceColor.navy),
    );
    img.fillRect(
      image,
      x1: 90,
      y1: 70,
      x2: 109,
      y2: 89,
      color: rgb(ReferenceColor.red),
    );
    expect(percents(img.encodePng(image)), {
      ReferenceColor.navy: 95,
      ReferenceColor.red: 5,
    });
  });

  test('detalhe neutro pequeno não entra', () {
    const w = 200, h = 160;
    final image = img.Image(width: w, height: h)
      ..clear(rgb(ReferenceColor.grey));
    img.fillRect(
      image,
      x1: 40,
      y1: 40,
      x2: 159,
      y2: 119,
      color: rgb(ReferenceColor.red),
    );
    img.fillRect(
      image,
      x1: 90,
      y1: 70,
      x2: 109,
      y2: 89,
      color: rgb(ReferenceColor.black),
    );
    expect(percents(img.encodePng(image)), {ReferenceColor.red: 100});
  });

  test('peça pequena num fundo de estúdio liso: tira o fundo', () {
    // Fotos de loja com muita margem: a peça ocupa menos de 15 %.
    const w = 200, h = 160;
    final image = img.Image(width: w, height: h)
      ..clear(img.ColorRgb8(0xEC, 0xE7, 0xE1));
    img.fillRect(
      image,
      x1: 80,
      y1: 60,
      x2: 119,
      y2: 99,
      color: rgb(ReferenceColor.navy),
    );
    expect(percents(img.encodePng(image)), {ReferenceColor.navy: 100});
  });

  test('PNG de 16 bits (captura do iPhone)', () {
    final image = img.Image(width: 50, height: 50, format: img.Format.uint16);
    for (final p in image) {
      p.setRgb(0xC0C0, 0x3939, 0x2B2B);
    }
    expect(percents(img.encodePng(image)), {ReferenceColor.red: 100});
  });

  test('metálicos não vêm da foto', () {
    final image = img.Image(width: 50, height: 50)
      ..clear(rgb(ReferenceColor.silver));
    expect(
      percents(img.encodePng(image)).keys,
      isNot(contains(ReferenceColor.silver)),
    );
  });
}
