import 'dart:typed_data';

/// Versões guardadas de cada fotografia. Os ficheiros são imutáveis: mudar a
/// foto é remover uma e adicionar outra, com id novo.
enum PhotoVariant {
  main('main'),
  thumb('thumb');

  const PhotoVariant(this.id);
  final String id;

  static PhotoVariant? fromId(String id) {
    for (final v in values) {
      if (v.id == id) return v;
    }
    return null;
  }
}

/// Metadados de uma fotografia ligada a uma peça. Os bytes ficam fora da
/// peça: na cache local e no Storage privado.
final class GarmentPhoto {
  const GarmentPhoto({
    required this.id,
    required this.width,
    required this.height,
    required this.bytes,
    required this.thumbBytes,
    required this.sha256,
  });

  final String id;
  final int width;
  final int height;
  final int bytes;
  final int thumbBytes;

  /// Da imagem principal, para verificar o ficheiro descarregado.
  final String sha256;

  @override
  bool operator ==(Object other) =>
      other is GarmentPhoto && other.id == id && other.sha256 == sha256;

  @override
  int get hashCode => Object.hash(id, sha256);
}

/// Fotografia já processada no dispositivo, ainda sem id.
final class ProcessedPhoto {
  const ProcessedPhoto({
    required this.width,
    required this.height,
    required this.main,
    required this.thumb,
    required this.sha256,
  });

  final int width;
  final int height;
  final Uint8List main;
  final Uint8List thumb;
  final String sha256;

  GarmentPhoto toPhoto(String id) => GarmentPhoto(
    id: id,
    width: width,
    height: height,
    bytes: main.length,
    thumbBytes: thumb.length,
    sha256: sha256,
  );

  Uint8List bytesOf(PhotoVariant variant) => switch (variant) {
    PhotoVariant.main => main,
    PhotoVariant.thumb => thumb,
  };
}

abstract final class PhotoRules {
  static const maxPerGarment = 5;

  /// Pontos de partida (docs/features/fotografias-e-ficheiros.md), a medir.
  static const mainMaxSide = 1600;
  static const thumbMaxSide = 320;
  static const mainQuality = 85;
  static const thumbQuality = 75;

  /// Ficheiro escolhido: acima disto nem se tenta descodificar.
  static const maxInputBytes = 40 * 1024 * 1024;

  /// Evita esgotar a memória ao descodificar (ex.: panorâmicas enormes).
  static const maxInputPixels = 64 * 1000 * 1000;

  /// Igual ao limite do bucket.
  static const maxStoredBytes = 5 * 1024 * 1024;

  /// Caminho no bucket privado: a primeira pasta é sempre o utilizador.
  static String storagePath(
    String ownerId,
    String photoId,
    PhotoVariant variant,
  ) => '$ownerId/$photoId/${variant.id}.jpg';
}
