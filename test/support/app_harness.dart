import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/app/app.dart';
import 'package:guarda_roupa/app/config.dart';
import 'package:guarda_roupa/features/account_sync/application/providers.dart';
import 'package:guarda_roupa/features/account_sync/domain/auth_service.dart';
import 'package:guarda_roupa/features/local_ai/application/local_ai_providers.dart';
import 'package:guarda_roupa/features/planner/application/plan_providers.dart';
import 'package:powersync/powersync.dart';

import 'fake_auth.dart';
import 'test_database.dart';

const phone = Size(400, 800);
const desktop = Size(1200, 800);

const testConfig = AppConfig(
  supabaseUrl: 'https://example.supabase.co',
  supabasePublishableKey: 'sb_publishable_test',
  powerSyncUrl: '',
);

/// Arranca a app real com uma base PowerSync real (SQLite em ficheiro) e
/// autenticação falsa. Sem sincronização: as operações ficam pendentes.
/// A semana sozinha fica desligada salvo [autopilot]: escreveria na base
/// em segundo plano e bloquearia as escritas do próprio teste. Os modelos
/// de IA também só se descarregam sozinhos com [modelsAuto].
Future<({FakeAuthService auth, PowerSyncDatabase db})> pumpApp(
  WidgetTester tester, {
  Size size = phone,
  AuthUser? user = const AuthUser(id: 'user-a', email: 'a@example.com'),
  AppConfig config = testConfig,
  List<Override> overrides = const [],
  bool autopilot = false,
  bool modelsAuto = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final db = (await tester.runAsync(openTestDatabase))!;
  final auth = FakeAuthService(user: user);
  // Desmonta a app enquanto o relógio falso ainda avança: o fecho da base
  // pedido pelo provider precisa dele para terminar.
  addTearDown(() => unmount(tester));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(config),
        authServiceProvider.overrideWithValue(auth),
        databaseOpenerProvider.overrideWithValue((_) async => db),
        weekAutopilotEnabledProvider.overrideWithValue(autopilot),
        localAiAutoDownloadEnabledProvider.overrideWithValue(modelsAuto),
        ...overrides,
      ],
      child: const GuardaRoupaApp(),
    ),
  );
  await settle(tester);
  return (auth: auth, db: db);
}

/// A base local responde em I/O real, fora do relógio falso dos testes de
/// widgets: alterna entre deixar o I/O correr e avançar o relógio até não
/// haver nada a carregar, e depois espera pelo fim das animações.
Future<void> settle(WidgetTester tester, {int minRounds = 3}) async {
  // Também fora do ecrã: um cartão abaixo da dobra ainda a carregar conta.
  final loading = find.byType(CircularProgressIndicator, skipOffstage: false);
  for (var i = 0; i < 100; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 50));
    if (i >= minRounds && loading.evaluate().isEmpty) {
      await tester.pumpAndSettle();
      return;
    }
  }
  fail('A app continuou a carregar.');
}

/// Como [settle], mas espera até [finder] encontrar algo (ou, com [gone],
/// deixar de encontrar), por exemplo o fecho de um ecrã depois de guardar.
Future<void> settleUntil(
  WidgetTester tester,
  Finder finder, {
  bool gone = false,
}) async {
  for (var i = 0; i < 100; i++) {
    if (finder.evaluate().isNotEmpty != gone) return settle(tester);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  fail('Não apareceu: $finder');
}

/// Desmonta a app avançando o relógio, para o fecho da base terminar.
Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 200));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  }
}
