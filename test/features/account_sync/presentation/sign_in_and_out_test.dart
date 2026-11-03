import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/app/config.dart';

import '../../../support/app_harness.dart';

void main() {
  testWidgets('sem sessão mostra o login e entra com Google', (tester) async {
    final app = await pumpApp(tester, user: null);

    expect(find.byType(NavigationBar), findsNothing);
    await tester.tap(find.text('Entrar com Google'));
    await settle(tester);

    expect(app.auth.signInCalls, 1);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('sem configuração do Supabase o login fica desativado', (
    tester,
  ) async {
    await pumpApp(
      tester,
      user: null,
      config: const AppConfig(
        supabaseUrl: '',
        supabasePublishableKey: '',
        powerSyncUrl: '',
      ),
    );

    final button = tester.widget<ButtonStyleButton>(
      find.ancestor(
        of: find.text('Entrar com Google'),
        matching: find.bySubtype<ButtonStyleButton>(),
      ),
    );
    expect(button.onPressed, isNull);
    expect(find.textContaining('compilada sem a configuração'), findsOneWidget);
  });

  testWidgets('terminar sessão sem pendências pede confirmação e sai', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.byTooltip('Definições'));
    await settle(tester);
    await tester.tap(find.text('Terminar sessão'));
    await tester.pumpAndSettle();
    expect(find.text('Terminar sessão?'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Terminar sessão'));
    await settleUntil(tester, find.text('Entrar com Google'));
    expect(find.text('Entrar com Google'), findsOneWidget);
  });
}
