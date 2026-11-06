import 'dart:typed_data';

enum PhotoSource { camera, gallery }

/// Câmara ou galeria. Devolve `null` se o utilizador cancelar; lança se a
/// permissão for recusada ou o sistema falhar.
abstract interface class PhotoPicker {
  Future<Uint8List?> pick(PhotoSource source);

  /// Várias fotos da galeria, no máximo [limit]. `[]` se cancelar.
  Future<List<Uint8List>> pickMany({required int limit});
}
