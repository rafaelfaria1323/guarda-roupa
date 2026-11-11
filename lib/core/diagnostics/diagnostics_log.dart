import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'diagnostics_store_io.dart'
    if (dart.library.js_interop) 'diagnostics_store_web.dart';

/// Um erro que a app apanhou, para o ecrã Diagnóstico.
@immutable
final class DiagnosticsEntry {
  const DiagnosticsEntry({
    required this.at,
    required this.where,
    required this.message,
  });

  final DateTime at;

  /// Onde aconteceu ("ecrã", "fundo" ou o nome que quem regista der).
  final String where;
  final String message;

  Map<String, Object?> toJson() => {
    'at': at.toUtc().toIso8601String(),
    'where': where,
    'message': message,
  };

  static DiagnosticsEntry? fromJson(Object? json) {
    if (json is! Map) return null;
    final at = DateTime.tryParse('${json['at']}');
    final where = json['where'];
    final message = json['message'];
    if (at == null || where is! String || message is! String) return null;
    return DiagnosticsEntry(at: at, where: where, message: message);
  }
}

/// Os últimos erros deste dispositivo, para o utilizador os copiar em
/// Definições › Diagnóstico. Nada sai do aparelho sozinho: não há serviço
/// de erros. Na Web ficam no `localStorage` (sobrevivem a recarregar a
/// página); nas outras plataformas só em memória.
///
/// O texto é encurtado e limpo de coisas com cara de chave
/// ([DiagnosticsLog.redact]).
final class DiagnosticsLog extends ChangeNotifier {
  DiagnosticsLog({DiagnosticsStore? store, DateTime Function()? now})
    : _store = store ?? platformDiagnosticsStore(),
      _now = now ?? DateTime.now {
    try {
      final saved = jsonDecode(_store.read() ?? '[]');
      if (saved is List) {
        _entries.addAll(saved.map(DiagnosticsEntry.fromJson).nonNulls);
      }
    } on Object {
      // O que estava guardado não se lê: começa vazio.
    }
  }

  /// O registo da app, criado antes dos providers para apanhar os erros
  /// de arranque.
  static final instance = DiagnosticsLog();

  static const maxEntries = 40;
  static const maxMessage = 400;

  final DiagnosticsStore _store;
  final DateTime Function() _now;
  final _entries = <DiagnosticsEntry>[];

  /// Do mais recente para o mais antigo.
  List<DiagnosticsEntry> get entries => _entries.reversed.toList();

  void record(String where, Object error, [StackTrace? stack]) {
    final frames = stack == null
        ? const <String>[]
        : stack
              .toString()
              .split('\n')
              .where((l) => l.trim().isNotEmpty)
              .take(3);
    var message = redact([error.toString(), ...frames].join('\n'));
    if (message.length > maxMessage) {
      message = '${message.substring(0, maxMessage - 1)}…';
    }
    // O mesmo erro em ciclo (um ecrã que falha a cada frame) conta uma vez.
    if (_entries.isNotEmpty &&
        _entries.last.where == where &&
        _entries.last.message == message) {
      return;
    }
    _entries.add(DiagnosticsEntry(at: _now(), where: where, message: message));
    if (_entries.length > maxEntries) {
      _entries.removeRange(0, _entries.length - maxEntries);
    }
    _save();
    notifyListeners();
  }

  void clear() {
    _entries.clear();
    _save();
    notifyListeners();
  }

  void _save() {
    try {
      _store.write(jsonEncode([for (final e in _entries) e.toJson()]));
    } on Object {
      // Sem espaço ou sem acesso: fica só em memória.
    }
  }

  /// Tira o que tem cara de chave ou de sessão: JWT, chaves do Supabase e
  /// do atalho, e os valores de `token`, `apikey` e `key` nos links.
  static String redact(String text) => text
      .replaceAll(
        RegExp(r'eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]+(\.[A-Za-z0-9_-]+)?'),
        '[jwt]',
      )
      .replaceAll(
        RegExp(r'\bsb_(secret|publishable)_[A-Za-z0-9_-]+'),
        '[chave]',
      )
      .replaceAll(RegExp(r'\bfio_[0-9a-f]{16,}'), '[chave]')
      .replaceAllMapped(
        RegExp(r'\b(token|apikey|key|access_token|refresh_token)=[^&\s]+'),
        (m) => '${m[1]}=[…]',
      )
      .replaceAllMapped(
        RegExp(r'(Bearer|bearer) [A-Za-z0-9._-]+'),
        (m) => '${m[1]} [...]',
      );

  /// O texto para copiar: o cabeçalho e os erros, do mais recente ao mais
  /// antigo.
  String report(List<String> header) => [
    ...header,
    '',
    if (_entries.isEmpty) '(sem erros registados)',
    for (final e in entries)
      '${e.at.toUtc().toIso8601String()} [${e.where}] ${e.message}',
  ].join('\n');
}
