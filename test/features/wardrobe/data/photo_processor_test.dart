import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/core/domain/result.dart';
import 'package:guarda_roupa/features/wardrobe/data/photo_processor.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_photo.dart';
import 'package:image/image.dart' as img;

import '../../../support/fake_photos.dart';

ProcessedPhoto ok(PhotoProcessing r) => switch (r) {
  Ok(:final value) => value,
  Err(:final failure) => fail('Esperava sucesso, obteve $failure'),
};

PhotoProblem problem(PhotoProcessing r) => switch (r) {
  Ok() => fail('Esperava falha'),
  Err(:final failure) => failure,
};

/// JPEG com EXIF de orientação e GPS, como os de um telemóvel.
Uint8List phoneJpeg({required int width, required int height}) {
  final image = img.Image(width: width, height: height)
    ..clear(img.ColorRgb8(0, 0, 255));
  // Marca no canto superior esquerdo, para verificar a rotação.
  img.fillRect(
    image,
    x1: 0,
    y1: 0,
    x2: 9,
    y2: 9,
    color: img.ColorRgb8(255, 0, 0),
  );
  image.exif.imageIfd.orientation = 6; // rodar 90° para a direita
  image.exif.gpsIfd['GPSLatitude'] = img.IfdValueRational(38, 1);
  return img.encodeJpg(image);
}

void main() {
  test('reduz para 1600 px e miniatura 320 px, em JPEG', () {
    final photo = ok(processPhotoSync(testPng(width: 4000, height: 3000)));
    expect((photo.width, photo.height), (1600, 1200));
    final main = img.decodeJpg(photo.main)!;
    final thumb = img.decodeJpg(photo.thumb)!;
    expect((main.width, main.height), (1600, 1200));
    expect((thumb.width, thumb.height), (320, 240));
    expect(photo.sha256, sha256.convert(photo.main).toString());
  });

  test('retrato: o lado maior é a altura', () {
    final photo = ok(processPhotoSync(testPng(width: 900, height: 2400)));
    expect((photo.width, photo.height), (600, 1600));
  });

  test('imagens pequenas não são ampliadas', () {
    final photo = ok(processPhotoSync(testPng(width: 40, height: 30)));
    expect((photo.width, photo.height), (40, 30));
  });

  test('aplica a orientação EXIF e remove os metadados', () {
    final photo = ok(processPhotoSync(phoneJpeg(width: 60, height: 40)));
    expect((photo.width, photo.height), (40, 60), reason: 'rodada');

    final main = img.decodeJpg(photo.main)!;
    expect(main.exif.isEmpty, isTrue, reason: 'sem EXIF nem GPS');
    expect(img.decodeJpg(photo.thumb)!.exif.isEmpty, isTrue);
    // A marca do canto superior esquerdo passa para o superior direito.
    final corner = main.getPixel(main.width - 3, 2);
    expect(corner.r, greaterThan(200));
    expect(corner.b, lessThan(80));
  });

  test('transparência fica branca, não preta', () {
    final png = img.encodePng(
      img.Image(width: 10, height: 10, numChannels: 4)
        ..clear(img.ColorRgba8(0, 0, 0, 0)),
    );
    final pixel = img.decodeJpg(ok(processPhotoSync(png)).main)!.getPixel(5, 5);
    expect(pixel.r, greaterThan(240));
  });

  test('HEIC tem erro próprio', () {
    final heic = Uint8List.fromList([
      0,
      0,
      0,
      24,
      ...'ftypheic'.codeUnits,
      0,
      0,
      0,
      0,
      ...'mif1heic'.codeUnits,
    ]);
    expect(problem(processPhotoSync(heic)), PhotoProblem.heic);
  });

  test('ficheiro que não é imagem é rejeitado', () {
    final bytes = Uint8List.fromList('olá, não sou uma imagem'.codeUnits);
    expect(problem(processPhotoSync(bytes)), PhotoProblem.unsupportedFormat);
  });

  test('imagem truncada é rejeitada sem rebentar', () {
    final png = testPng(width: 200, height: 200);
    final cut = Uint8List.sublistView(png, 0, png.length ~/ 3);
    expect(processPhotoSync(cut), isA<Err<ProcessedPhoto, PhotoProblem>>());
  });

  test('ficheiro demasiado grande é rejeitado antes de descodificar', () {
    final big = Uint8List(PhotoRules.maxInputBytes + 1);
    expect(problem(processPhotoSync(big)), PhotoProblem.tooLarge);
  });

  test('processPhoto (isolate) dá o mesmo resultado', () async {
    final photo = ok(await processPhoto(testPng()));
    expect((photo.width, photo.height), (40, 30));
  });
}
