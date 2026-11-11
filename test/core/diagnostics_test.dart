import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/core/diagnostics/diagnostics_log.dart';
import 'package:guarda_roupa/features/account_sync/presentation/settings_screen.dart';
import 'package:guarda_roupa/core/diagnostics/diagnostics_screen.dart';
import 'package:guarda_roupa/core/diagnostics/diagnostics_store.dart';

import '../support/app_harness.dart';

void main() {
  DiagnosticsLog log([DiagnosticsStore? store]) => DiagnosticsLog(
    store: store ?? MemoryDiagnosticsStore(),
    now: () => DateTime.utc(2026, 11, 11, 20),
  );

  test('regista, encurta, não repete o mesmo erro e guarda só os últimos', () {
    final l = log();
    l.record('ecrã', StateError('falhou'), StackTrace.fromString('a\nb\nc\nd'));
    expect(l.entries.single.message, 'Bad state: falhou\na\nb\nc');
    l.record('ecrã', StateError('falhou'), StackTrace.fromString('a\nb\nc\nd'));
    expect(l.entries, hasLength(1));
    l.record('fundo', 'x' * 1000);
    expect(l.entries.first.message.length, DiagnosticsLog.maxMessage);
    for (var i = 0; i < 60; i++) {
      l.record('fundo', 'erro $i');
    }
    expect(l.entries, hasLength(DiagnosticsLog.maxEntries));
    expect(l.entries.first.message, 'erro 59');
    l.clear();
    expect(l.entries, isEmpty);
  });

  test('tira o que tem cara de chave', () {
    final jwt = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.abc_def-123';
    final text = DiagnosticsLog.redact(
      'GET https://x.supabase.co/f?apikey=sb_publishable_abc123&token=t0k3n '
      'Authorization: Bearer $jwt x-fio-key fio_${'0a' * 32} $jwt',
    );
    for (final secret in ['abc123', 't0k3n', 'eyJ', '0a0a0a']) {
      expect(text.contains(secret), false, reason: secret);
    }
    expect(text.contains('https://x.supabase.co/f'), true);
  });

  test('o que ficou guardado volta ao abrir; lixo começa vazio', () {
    final store = MemoryDiagnosticsStore();
    log(store).record('fundo', 'ficou');
    expect(log(store).entries.single.message, 'ficou');
    expect(
      log(MemoryDiagnosticsStore()..write('{não é json')).entries,
      isEmpty,
    );
  });

  testWidgets('Definições › Diagnóstico: ver, copiar e limpar', (tester) async {
    final l = log()..record('fundo', 'A imagem não carregou');
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    await pumpApp(
      tester,
      overrides: [diagnosticsLogProvider.overrideWithValue(l)],
    );
    await tester.tap(find.byTooltip('Definições'));
    await settle(tester);
    final tile = find.byKey(const Key('diagnostics'));
    await tester.scrollUntilVisible(
      tile,
      200,
      scrollable: find
          .descendant(
            of: find.byType(SettingsScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.ensureVisible(tile);
    await tester.pumpAndSettle();
    await tester.tap(tile);
    await settle(tester);

    expect(find.text('A imagem não carregou'), findsOneWidget);
    await tester.tap(find.byKey(const Key('diagnostics-copy')));
    await tester.pumpAndSettle();
    expect(copied, contains('fio local'));
    expect(copied, contains('[fundo] A imagem não carregou'));

    await tester.tap(find.byKey(const Key('diagnostics-clear')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('diagnostics-empty')), findsOneWidget);
    expect(find.byKey(const Key('diagnostics-clear')), findsNothing);
  });
}
