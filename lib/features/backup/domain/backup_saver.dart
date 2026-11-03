import 'dart:typed_data';

enum SaveOutcome {
  /// Gravado onde o utilizador escolheu.
  saved,

  /// Web: a transferência começou; não prova que o ficheiro ficou guardado.
  downloadStarted,

  /// O utilizador fechou o diálogo sem guardar.
  cancelled,
}

/// Guarda o ficheiro fora da app (diálogo "Guardar como" do sistema).
abstract interface class BackupSaver {
  Future<SaveOutcome> save(String name, Uint8List zip);
}
