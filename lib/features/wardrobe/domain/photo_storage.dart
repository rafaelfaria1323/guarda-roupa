import 'dart:typed_data';

/// Ficheiros no Storage privado. Os caminhos vêm de
/// `PhotoRules.storagePath`.
abstract interface class PhotoStorage {
  /// Idempotente: enviar de novo o mesmo ficheiro não é erro.
  Future<void> upload(String path, Uint8List bytes);

  Future<Uint8List> download(String path);

  Future<void> remove(List<String> paths);

  /// Um link que deixa ver o ficheiro durante uns minutos, sem sessão
  /// (para o mostrar a um serviço de fora, a pedido do utilizador). Falha
  /// se o ficheiro ainda não estiver no Storage.
  Future<Uri> temporaryLink(String path);
}
