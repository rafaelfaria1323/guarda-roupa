import 'dart:typed_data';

import 'package:guarda_roupa/features/wardrobe/domain/photo_picker.dart';
import 'package:guarda_roupa/features/wardrobe/domain/photo_storage.dart';
import 'package:image/image.dart' as img;

/// Imagem PNG de teste, de uma cor.
Uint8List testPng({int width = 40, int height = 30, int r = 200}) =>
    img.encodePng(
      img.Image(width: width, height: height)..clear(img.ColorRgb8(r, 10, 10)),
    );

/// Picker programado: devolve, por ordem, os resultados em [next]
/// (`null` = cancelado). Lança [failWith] se definido.
final class FakePhotoPicker implements PhotoPicker {
  final next = <Uint8List?>[];
  final sources = <PhotoSource>[];
  Object? failWith;

  @override
  Future<Uint8List?> pick(PhotoSource source) async {
    sources.add(source);
    if (failWith case final e?) throw e;
    return next.isEmpty ? null : next.removeAt(0);
  }

  /// Resultado do próximo [pickMany] (`[]` = cancelado).
  List<Uint8List> nextMany = [];
  final manyLimits = <int>[];

  @override
  Future<List<Uint8List>> pickMany({required int limit}) async {
    manyLimits.add(limit);
    if (failWith case final e?) throw e;
    final out = nextMany.take(limit).toList();
    nextMany = [];
    return out;
  }
}

/// Storage em memória.
final class FakePhotoStorage implements PhotoStorage {
  final files = <String, Uint8List>{};
  final downloads = <String>[];

  @override
  Future<void> upload(String path, Uint8List bytes) async =>
      files[path] = bytes;

  @override
  Future<Uint8List> download(String path) async {
    downloads.add(path);
    return files[path] ?? (throw StateError('404 $path'));
  }

  @override
  Future<void> remove(List<String> paths) async => paths.forEach(files.remove);
}
