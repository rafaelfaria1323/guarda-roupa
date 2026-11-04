import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/features/wardrobe/data/powersync_wardrobe_repository.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_category.dart';
import 'package:guarda_roupa/features/wear/application/wear_providers.dart';
import 'package:guarda_roupa/features/weather/application/weather_providers.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:powersync/powersync.dart';

import '../../support/app_harness.dart';
import '../wardrobe/domain/fakes.dart';
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

  Finder day(int i, String part) => find.byKey(Key('week-day-$i-$part'));

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

  Future<void> generate(WidgetTester tester, String outcome) async {
    await tap(tester, find.byKey(const Key('week-generate')));
    await settleUntil(tester, find.text(outcome));
  }

  String text(WidgetTester tester, Finder finder) =>
      tester.widget<Text>(finder).data!;

  testWidgets('planear a semana, aceitar, deixar o fim de semana vazio e '
      'confirmar hoje', (tester) async {
    final app = await pumpApp(
      tester,
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
    await seed(tester, app.db);
    await tester.scrollUntilVisible(
      day(0, 'state'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Esta semana'), findsOne);
    expect(text(tester, day(0, 'state')), 'Por planear');

    await generate(tester, '7 dias propostos.');
    for (var i = 0; i < 7; i++) {
      expect(text(tester, day(i, 'state')), 'Proposto');
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

    // Terça fica; sábado fica vazio.
    final tuesday = text(tester, day(1, 'items'));
    await tap(tester, day(1, 'accept'));
    expect(text(tester, day(1, 'state')), 'Aceite');
    await tap(tester, day(5, 'leave-empty'));
    expect(text(tester, day(5, 'state')), 'Aceite');
    expect(text(tester, day(5, 'items')), 'Fica vazio.');

    // Voltar a planear só mexe nos dias propostos.
    await generate(tester, '5 dias propostos.');
    expect(text(tester, day(1, 'items')), tuesday);
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

  testWidgets('mudar a ocasião e resolver uma proposta de outro dispositivo', (
    tester,
  ) async {
    final app = await pumpApp(
      tester,
      overrides: [
        clockProvider.overrideWithValue(
          FixedClock(DateTime.utc(2026, 11, 9, 12)),
        ),
        httpClientProvider.overrideWithValue(
          MockClient((_) async => http.Response('', 503)),
        ),
      ],
    );
    await seed(tester, app.db);
    await generate(tester, '7 dias propostos.');

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
}
