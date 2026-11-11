import 'diagnostics_store.dart';

export 'diagnostics_store.dart';

DiagnosticsStore platformDiagnosticsStore() => MemoryDiagnosticsStore();

/// O browser e o sistema, para o cabeçalho do relatório.
String platformDescription() => 'app';
