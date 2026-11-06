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
import '../weather/weather_test.dart' show hourly;

void main() {
  Future<void> seed(WidgetTester tester, PowerSyncDatabase db) async {
    final repo = PowerSyncWardrobeRepository(db: db, ownerId: 'user-a');
    await tester.runAsync(() async {
      for (final (c, name) in [
        (GarmentCategory.tShirt, 'Branca'),
        (GarmentCategory.jeans, 'Azul'),
        (GarmentCategory.sneakers, 'Brancos'),
      ]) {
        await repo.addGarment(GarmentDraft(category: c, name: name));
      }
    });
    await settle(tester); // já abre no Planeador
  }

  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('sugere um conjunto com a previsão e abre "Vesti hoje" com as '
      'peças por confirmar', (tester) async {
    var calls = 0;
    final app = await pumpApp(
      tester,
      overrides: [
        clockProvider.overrideWithValue(
          FixedClock(DateTime.utc(2026, 11, 3, 12)),
        ),
        httpClientProvider.overrideWithValue(
          MockClient((req) async {
            calls++;
            return http.Response(
              jsonEncode(hourly(days: 7, feels: (_, _) => 18)),
              200,
            );
          }),
        ),
      ],
    );
    await seed(tester, app.db);

    expect(find.text('Sugestões para hoje'), findsOne);
    expect(
      find.textContaining('Torres Vedras: sensação 18 °C'),
      findsOneWidget,
    );
    expect(find.textContaining('Open-Meteo.com'), findsOneWidget);
    expect(calls, 1);

    await scrollTo(tester, find.byKey(const Key('suggestion-0-wear')));
    expect(find.textContaining('Sugestão 1 de'), findsOne);
    for (final name in ['Branca', 'Azul', 'Brancos']) {
      expect(
        find.descendant(
          of: find.byKey(const Key('suggestion-0')),
          matching: find.textContaining(name),
        ),
        findsOne,
      );
    }
    // Sem ocasiões nem aquecimento indicados: diz-se, não se inventa.
    await scrollTo(tester, find.byKey(const Key('suggestion-0-why')));
    await tester.tap(find.byKey(const Key('suggestion-0-why')));
    await tester.pumpAndSettle();
    expect(find.textContaining('aquecimento desconhecido'), findsWidgets);

    await tester.tap(find.byKey(const Key('suggestion-0-wear')));
    await settle(tester);
    expect(find.text('O que vestiste hoje?'), findsOne);
    expect(find.text('3 peças escolhidas'), findsOne);
    await save(tester);
    // A única t-shirt foi para lavar sozinha (P-07): sem parte de cima
    // disponível, a sugestão explica porquê.
    expect(
      find.text('Utilização registada. Marquei para lavar: Branca.'),
      findsOne,
    );
    expect(
      find.text(
        'Top principal: todas indisponíveis ou arquivadas',
        skipOffstage: false,
      ),
      findsOne,
    );
    expect(find.byKey(const Key('suggestion-0-wear')), findsNothing);
  });

  testWidgets('guardar a sugestão como conjunto marca-a e não repete', (
    tester,
  ) async {
    final app = await pumpApp(
      tester,
      overrides: [
        clockProvider.overrideWithValue(
          FixedClock(DateTime.utc(2026, 11, 3, 12)),
        ),
        httpClientProvider.overrideWithValue(
          MockClient((_) async => throw http.ClientException('offline')),
        ),
      ],
    );
    await seed(tester, app.db);
    await scrollTo(tester, find.byKey(const Key('suggestion-0-save')));
    expect(find.byKey(const Key('suggestion-0-saved')), findsNothing);

    await tester.tap(find.byKey(const Key('suggestion-0-save')));
    await settleUntil(tester, find.byKey(const Key('suggestion-0-saved')));
    expect(find.text('Um dos teus conjuntos'), findsOne);
    expect(find.byKey(const Key('suggestion-0-save')), findsNothing);
    expect(
      find.text(
        'Guardado nos teus conjuntos. Passa a ser preferido nas sugestões.',
      ),
      findsOne,
    );

    final rows = (await tester.runAsync(
      () => app.db.getAll('SELECT items FROM outfits'),
    ))!;
    expect(rows, hasLength(1));
    final roles = [
      for (final i in jsonDecode(rows.single['items']! as String) as List)
        (i as Map)['role'],
    ];
    expect(roles, ['main_top', 'bottom', 'footwear']);
  });

  testWidgets('sem previsão diz isso e aceita o tempo indicado à mão', (
    tester,
  ) async {
    final app = await pumpApp(
      tester,
      overrides: [
        httpClientProvider.overrideWithValue(
          MockClient((_) async => throw http.ClientException('offline')),
        ),
      ],
    );
    await seed(tester, app.db);
    expect(find.byKey(const Key('weather-none')), findsOne);

    await tester.tap(find.byKey(const Key('weather-manual-set')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('weather-manual-cold')));
    await tester.pumpAndSettle();
    expect(find.text('Tempo indicado à mão: Frio'), findsOne);

    await tester.tap(find.byKey(const Key('weather-manual-clear')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('weather-none')), findsOne);
  });

  testWidgets('guarda-roupa vazio: explica o que falta', (tester) async {
    await pumpApp(
      tester,
      overrides: [
        httpClientProvider.overrideWithValue(
          MockClient((_) async => http.Response('', 503)),
        ),
      ],
    );
    expect(find.byKey(const Key('suggestions-insufficient')), findsOne);
  });
}
