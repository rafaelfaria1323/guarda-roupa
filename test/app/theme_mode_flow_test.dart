import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/app/theme.dart';

import '../support/app_harness.dart';

void main() {
  testWidgets('aspeto: automático, escuro e claro, e fica guardado', (
    tester,
  ) async {
    final app = await pumpApp(tester);
    Brightness now() =>
        Theme.of(tester.element(find.byType(Scaffold).first)).brightness;
    expect(now(), Brightness.light, reason: 'o aparelho do teste é claro');

    await tester.tap(find.byTooltip('Definições'));
    await settle(tester);
    expect(find.text('Automático'), findsOne);
    await tester.tap(find.text('Escuro'));
    await settle(tester);
    expect(now(), Brightness.dark);
    expect(
      Theme.of(tester.element(find.byType(Scaffold).first))
          .scaffoldBackgroundColor,
      AppColors.dark.background,
    );
    // A base trabalha enquanto a app anda: pede e vai avançando.
    String? saved;
    unawaited(
      app.db
          .get("SELECT value FROM local_settings WHERE key = 'theme_mode'")
          .then((r) => saved = r['value'] as String?),
    );
    for (var i = 0; i < 100 && saved == null; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(saved, 'dark');

    await tester.tap(find.text('Claro'));
    await settle(tester);
    expect(now(), Brightness.light);
  });

  test('o texto lê-se bem nos dois temas', () {
    double contrast(Color a, Color b) {
      final (x, y) = (a.computeLuminance(), b.computeLuminance());
      return (x > y ? x + 0.05 : y + 0.05) / (x > y ? y + 0.05 : x + 0.05);
    }

    for (final c in [AppColors.light, AppColors.dark]) {
      for (final bg in [c.background, c.surface]) {
        expect(contrast(c.onSurface, bg), greaterThan(12));
        expect(contrast(c.onSurfaceMuted, bg), greaterThan(4.5));
        expect(contrast(c.accent, bg), greaterThan(4.5));
      }
      expect(contrast(c.onAccent, c.accent), greaterThan(4.5));
      expect(contrast(c.onAccentSoft, c.accentSoft), greaterThan(4.5));
      expect(contrast(c.onInverse, c.onSurface), greaterThan(12));
      expect(contrast(c.onCareSoft, c.background), greaterThan(4.5));
    }
  });
}
