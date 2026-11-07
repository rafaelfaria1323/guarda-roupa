import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/features/wardrobe/data/powersync_wardrobe_repository.dart';
import 'package:guarda_roupa/features/wardrobe/domain/availability.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_category.dart';
import 'package:guarda_roupa/features/wear/application/wear_providers.dart';
import 'package:guarda_roupa/features/wear/domain/calendar_day.dart';
import 'package:guarda_roupa/features/weather/application/weather_providers.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:powersync/powersync.dart';

import '../../support/app_harness.dart';
import '../wardrobe/domain/fakes.dart';
import '../weather/weather_test.dart' show hourly;
import '../wear/wear_flow_test.dart' show save;

void main() {
  Future<void> seed(WidgetTester tester, PowerSyncDatabase db) async {
    final repo = PowerSyncWardrobeRepository(db: db, ownerId: 'user-a');
    await tester.runAsync(() async {
      for (final (c, name) in [
        (GarmentCategory.tShirt, 'T1'),
        (GarmentCategory.tShirt, 'T2'),
        (GarmentCategory.tShirt, 'T3'),
        (GarmentCategory.jeans, 'C1'),
        (GarmentCategory.jeans, 'C2'),
        (GarmentCategory.jeans, 'C3'),
        (GarmentCategory.sneakers, 'Ténis'),
      ]) {
        await repo.addGarment(GarmentDraft(category: c, name: name));
      }
    });
    await settle(tester);
  }

  Future<void> openWeek(WidgetTester tester) async {
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Semana'),
      ),
    );
    await settle(tester);
  }

  Finder day(int i, String part, {bool skipOffstage = true}) =>
      find.byKey(Key('week-day-$i-$part'), skipOffstage: skipOffstage);

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(finder);
    // A escrita local corre em I/O real: dar-lhe tempo antes de olhar.
    await settle(tester, minRounds: 10);
  }

  /// Com peças no Armário, os dias por planear enchem-se sozinhos.
  Future<void> autoPlanned(WidgetTester tester) async {
    await tester.scrollUntilVisible(
      day(0, 'state'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    // O aviso só aparece depois de gravados todos os dias.
    await settleUntil(tester, find.textContaining('Planeei 7 dias'));
  }

  Future<void> generate(WidgetTester tester, String outcome) async {
    await tap(tester, find.byKey(const Key('week-generate')));
    await settleUntil(tester, find.text(outcome));
  }

  String text(WidgetTester tester, Finder finder) =>
      tester.widget<Text>(finder).data!;

  testWidgets('a semana planeia-se sozinha; alterar, deixar o fim de semana '
      'vazio, planear de novo e confirmar hoje', (tester) async {
    final app = await pumpApp(
      tester,
      autopilot: true,
      overrides: [
        // Segunda-feira, 9/11.
        clockProvider.overrideWithValue(
          FixedClock(DateTime.utc(2026, 11, 9, 12)),
        ),
        httpClientProvider.overrideWithValue(
          MockClient((_) async => throw http.ClientException('offline')),
        ),
      ],
    );
    await openWeek(tester);
    expect(find.text('NOVEMBRO DE 2026'), findsOne);
    // Tocar num dia da faixa leva ao seu cartão.
    expect(tester.getTopLeft(day(6, 'state')).dy, greaterThan(800));
    await tester.tap(find.byKey(const Key('week-strip-6')));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(day(6, 'state')).dy, lessThan(800));
    await tester.fling(
      find.byType(Scrollable).first,
      const Offset(0, 3000),
      3000,
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      day(0, 'state'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('A tua semana'), findsOne);
    expect(text(tester, day(0, 'state')), 'Por planear', reason: 'sem peças');

    await seed(tester, app.db);
    await autoPlanned(tester);
    for (var i = 0; i < 7; i++) {
      expect(text(tester, day(i, 'state')), 'Aceite');
      expect(text(tester, day(i, 'items')), contains('Ténis'));
    }
    // Úteis no trabalho; fim de semana a decidir e provisório (P-19).
    expect(
      find.descendant(
        of: day(0, 'occasion'),
        matching: find.text('Trabalho (smart casual)'),
      ),
      findsOne,
    );
    expect(
      find.descendant(of: day(5, 'occasion'), matching: find.text('A decidir')),
      findsOne,
    );
    expect(tester.widget<FilterChip>(day(5, 'tentative')).selected, isTrue);
    expect(tester.widget<FilterChip>(day(0, 'tentative')).selected, isFalse);

    // Alterar volta a proposto; sábado fica vazio.
    await tap(tester, day(1, 'reopen'));
    expect(text(tester, day(1, 'state')), 'Proposto');
    await tap(tester, day(5, 'leave-empty'));
    expect(text(tester, day(5, 'state')), 'Aceite');
    expect(text(tester, day(5, 'items')), 'Fica vazio.');

    // Planear de novo refaz os dias por vestir, menos o que ficou vazio.
    await generate(tester, '6 dias planeados.');
    expect(text(tester, day(1, 'state')), 'Aceite');
    expect(text(tester, day(5, 'items')), 'Fica vazio.');

    // Planear não é usar; "Vesti isto hoje" com as peças por confirmar.
    final rows = await tester.runAsync(
      () => app.db.getAll('SELECT * FROM wear_events'),
    );
    expect(rows, isEmpty);
    await tap(tester, day(0, 'wear'));
    expect(find.text('O que vestiste hoje?'), findsOne);
    expect(find.text('3 peças escolhidas'), findsOne);
    await save(tester);
    expect(text(tester, day(0, 'state')), 'Vestido');
    final wear = await tester.runAsync(
      () => app.db.get('SELECT plan_entry_id FROM wear_events'),
    );
    expect(wear!['plan_entry_id'], isNotNull);
  });

  testWidgets('cada dia planeado diz o acessório que a previsão pede', (
    tester,
  ) async {
    final app = await pumpApp(
      tester,
      autopilot: true,
      overrides: [
        clockProvider.overrideWithValue(
          FixedClock(DateTime.utc(2026, 11, 9, 12)),
        ),
        // A partir de 9/11: chove só no segundo dia (10/11).
        httpClientProvider.overrideWithValue(
          MockClient(
            (_) async => http.Response(
              jsonEncode(
                hourly(
                  days: 7,
                  start: CalendarDay(2026, 11, 9),
                  feels: (_, _) => 18,
                  rain: (d, _) => d == 1 ? 1 : 0,
                ),
              ),
              200,
            ),
          ),
        ),
      ],
    );
    await openWeek(tester);
    await tester.runAsync(
      () =>
          PowerSyncWardrobeRepository(db: app.db, ownerId: 'user-a').addGarment(
            const GarmentDraft(
              category: GarmentCategory.umbrella,
              name: 'Guarda',
            ),
          ),
    );
    await seed(tester, app.db);
    await autoPlanned(tester);

    await tester.scrollUntilVisible(
      day(1, 'accessories'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      text(tester, day(1, 'accessories')),
      'Leva também: Guarda (vai chover)',
    );
    expect(day(0, 'accessories'), findsNothing);
    expect(day(2, 'accessories', skipOffstage: false), findsNothing);
    // Não fica no plano: as peças do dia são as do conjunto.
    expect(text(tester, day(1, 'items')), isNot(contains('Guarda')));
  });

  testWidgets('mudar a ocasião e resolver uma proposta de outro dispositivo', (
    tester,
  ) async {
    final app = await pumpApp(
      tester,
      autopilot: true,
      overrides: [
        clockProvider.overrideWithValue(
          FixedClock(DateTime.utc(2026, 11, 9, 12)),
        ),
        httpClientProvider.overrideWithValue(
          MockClient((_) async => http.Response('', 503)),
        ),
      ],
    );
    await openWeek(tester);
    await seed(tester, app.db);
    await autoPlanned(tester);

    await tap(tester, day(2, 'occasion'));
    await tester.tap(find.text('A decidir').last);
    await settleUntil(
      tester,
      find.descendant(of: day(2, 'occasion'), matching: find.text('A decidir')),
    );
    expect(
      find.descendant(of: day(2, 'occasion'), matching: find.text('A decidir')),
      findsOne,
    );

    // Uma edição com versão antiga chegou do servidor como proposta.
    await tester.runAsync(
      () => app.db.execute(
        "UPDATE plan_entries SET proposal = ? WHERE day = '2026-11-12'",
        [
          jsonEncode({'occasion': 'evening'}),
        ],
      ),
    );
    await settle(tester);
    expect(day(3, 'proposal'), findsOne);
    expect(find.text('Noite / saída'), findsOne);
    await tap(tester, day(3, 'proposal-apply'));
    expect(day(3, 'proposal'), findsNothing);
    expect(
      find.descendant(
        of: day(3, 'occasion'),
        matching: find.text('Noite / saída'),
      ),
      findsOne,
    );
  });

  testWidgets('uma peça planeada vai para lavar: troca-se sozinha, com '
      'aviso e desfazer', (tester) async {
    final app = await pumpApp(
      tester,
      autopilot: true,
      overrides: [
        clockProvider.overrideWithValue(
          FixedClock(DateTime.utc(2026, 11, 9, 12)),
        ),
        httpClientProvider.overrideWithValue(
          MockClient((_) async => http.Response('', 503)),
        ),
      ],
    );
    await openWeek(tester);
    await seed(tester, app.db);
    await autoPlanned(tester);
    expect(day(2, 'changed'), findsNothing);

    // A t-shirt de quarta vai para lavar.
    final before = text(tester, day(2, 'items'));
    final shirt = before.split(' · ').firstWhere((n) => n.startsWith('T'));
    final repo = PowerSyncWardrobeRepository(db: app.db, ownerId: 'user-a');
    await tester.runAsync(() async {
      final row = await app.db.get('SELECT id FROM garments WHERE name = ?', [
        shirt,
      ]);
      await repo.setAvailability(
        GarmentId(row['id']! as String),
        Availability.washing,
      );
    });
    await settleUntil(tester, find.byKey(const Key('week-auto-changed')));
    final after = text(tester, day(2, 'items'));
    expect(after, isNot(contains(shirt)));
    expect(after, contains('Ténis'));
    expect(text(tester, day(2, 'state')), 'Aceite');
    expect(
      find.textContaining('$shirt está indisponível (a lavar)'),
      findsNothing,
      reason: 'a troca resolveu',
    );

    // Desfazer volta ao plano e não se volta a aplicar; o aviso fica.
    await tester.tap(find.text('Desfazer'));
    await settleUntil(tester, day(2, 'changed'));
    expect(text(tester, day(2, 'items')), before);
    expect(
      find.textContaining('$shirt está indisponível (a lavar)'),
      findsWidgets,
    );
    expect(day(2, 'change-apply'), findsNothing);
  });
}
