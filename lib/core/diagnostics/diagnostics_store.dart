/// Onde o registo de erros fica guardado entre aberturas da app.
abstract interface class DiagnosticsStore {
  String? read();
  void write(String value);
}

/// Só em memória.
final class MemoryDiagnosticsStore implements DiagnosticsStore {
  String? _value;

  @override
  String? read() => _value;

  @override
  void write(String value) => _value = value;
}
