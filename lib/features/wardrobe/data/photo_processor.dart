import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../../../core/domain/result.dart';
import '../domain/garment_photo.dart';

enum PhotoProblem {
  /// HEIC/HEIF (fotos de iPhone): a biblioteca não descodifica.
  heic,
  unsupportedFormat,
  tooLarge,
}

typedef PhotoProcessing = Result<ProcessedPhoto, PhotoProblem>;

/// Prepara uma fotografia para guardar: valida, corrige a orientação,
/// reduz para 1600 px e 320 px (miniatura) e grava JPEG sem metadados
/// (EXIF, localização, perfis).
///
/// Em Android corre noutro isolate; na Web pode correr na thread da UI.
Future<PhotoProcessing> processPhoto(Uint8List input) =>
    compute(processPhotoSync, input);

const _accepted = {
  img.ImageFormat.jpg,
  img.ImageFormat.png,
  img.ImageFormat.webp,
};

PhotoProcessing processPhotoSync(Uint8List input) {
  if (input.length > PhotoRules.maxInputBytes) {
    return const Err(PhotoProblem.tooLarge);
  }
  if (_isHeic(input)) return const Err(PhotoProblem.heic);

  // Só formatos de fotografia: alguns descodificadores (ex.: TGA) aceitam
  // quase qualquer sequência de bytes.
  final format = img.findFormatForData(input);
  if (!_accepted.contains(format)) {
    return const Err(PhotoProblem.unsupportedFormat);
  }
  final decoder = img.createDecoderForFormat(format)!;
  final info = decoder.startDecode(input);
  if (info == null || info.width <= 0 || info.height <= 0) {
    return const Err(PhotoProblem.unsupportedFormat);
  }
  if (info.width * info.height > PhotoRules.maxInputPixels) {
    return const Err(PhotoProblem.tooLarge);
  }

  final img.Image? decoded;
  try {
    decoded = decoder.decode(input, frame: 0);
  } on Object {
    return const Err(PhotoProblem.unsupportedFormat);
  }
  if (decoded == null) return const Err(PhotoProblem.unsupportedFormat);

  final upright = img.bakeOrientation(decoded);
  final main = _fit(upright, PhotoRules.mainMaxSide);
  final thumb = _fit(upright, PhotoRules.thumbMaxSide);
  final mainBytes = img.encodeJpg(main, quality: PhotoRules.mainQuality);
  final thumbBytes = img.encodeJpg(thumb, quality: PhotoRules.thumbQuality);
  if (mainBytes.length > PhotoRules.maxStoredBytes) {
    return const Err(PhotoProblem.tooLarge);
  }
  return Ok(
    ProcessedPhoto(
      width: main.width,
      height: main.height,
      main: mainBytes,
      thumb: thumbBytes,
      sha256: sha256.convert(mainBytes).toString(),
    ),
  );
}

/// Reduz (nunca amplia) e devolve uma imagem RGB sem metadados.
img.Image _fit(img.Image source, int maxSide) {
  final longest = source.width > source.height ? source.width : source.height;
  final resized = longest <= maxSide
      ? img.Image.from(source)
      : img.copyResize(
          source,
          width: source.width >= source.height ? maxSide : null,
          height: source.height > source.width ? maxSide : null,
          interpolation: img.Interpolation.average,
        );
  // JPEG não tem transparência: compor sobre branco, não sobre preto.
  final flat = resized.hasAlpha
      ? (img.Image(width: resized.width, height: resized.height)
          ..clear(img.ColorRgb8(255, 255, 255)))
      : null;
  final out = flat == null ? resized : img.compositeImage(flat, resized);
  out
    ..exif = img.ExifData()
    ..iccProfile = null
    ..textData = null;
  return out;
}

/// Caixa ISO-BMFF `ftyp` com marca HEIF (heic, heix, mif1, ...).
bool _isHeic(Uint8List bytes) {
  if (bytes.length < 12) return false;
  final box = String.fromCharCodes(bytes.sublist(4, 8));
  if (box != 'ftyp') return false;
  final brand = String.fromCharCodes(bytes.sublist(8, 12));
  return const {
    'heic',
    'heix',
    'hevc',
    'hevx',
    'heim',
    'heis',
    'mif1',
    'msf1',
  }.contains(brand);
}
