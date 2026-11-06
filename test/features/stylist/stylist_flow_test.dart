import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/core/domain/result.dart';
import 'package:guarda_roupa/features/photo_ai/domain/photo_reader.dart';
import 'package:guarda_roupa/features/stylist/application/stylist_providers.dart';
import 'package:guarda_roupa/features/stylist/domain/stylist.dart';
import 'package:guarda_roupa/features/wardrobe/data/powersync_wardrobe_repository.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_category.dart';
import 'package:guarda_roupa/features/wear/application/wear_providers.dart';
import 'package:guarda_roupa/features/weather/application/weather_providers.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:powersync/powersync.dart';

import '../../support/app_harness.dart';
import '../../support/fake_auth.dart';
import '../wardrobe/domain/fakes.dart';

/// Escolhe a peça de cada categoria pedida, pela ordem de [picks].
final class FakeStylist implements Stylist {
  FakeStylist(this.picks);

  final List<Object> picks;
  final briefs = <Map<String, Object?>>[];

  @override
  Future<Result<StylistReply, PhotoReadFailure>> suggest(
    Map<String, Object?> brief,
  ) async {
    briefs.add(brief);
    final next = picks[(briefs.length - 1) % picks.length];
    if (next is PhotoReadFailure) return Err(next);
    final garments = brief['garments']! as List;
    String id(String category) =>
        (garments.firstWhere((g) => (g as Map)['category'] == category)
                as Map)['id']!
            as String;
    final names = next as List<(String, String)>;
    return Ok(
      StylistReply(
        name: 'Ideia ${briefs.length}',
        why: 'Porque combina (${briefs.length}).',
        items: [for (final (c, role) in names) (id(c), role)],
      ),
    );
  }
}

void main() {
  Future<void> seed(WidgetTester tester, PowerSyncDatabase db) async {
    final repo = PowerSyncWardrobeRepository(db: db, ownerId: 'user-a');
    await tester.runAsync(() async {
      for (final (c, name) in [
        (GarmentCategory.tShirt, 'Branca'),
        (GarmentCategory.shirt, 'Oxford'),
        (GarmentCategory.jeans, 'Azul'),
        (GarmentCategory.sneakers, 'Brancos'),
      ]) {
        await repo.addGarment(GarmentDraft(category: c, name: name));
      }
    });
    await settle(tester);
  }

  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  Future<({FakeAuthService auth, PowerSyncDatabase db})> start(
    WidgetTester tester,
    Stylist? stylist,
  ) => pumpApp(
    tester,
    overrides: [
      clockProvider.overrideWithValue(
        FixedClock(DateTime.utc(2026, 11, 3, 12)),
      ),
      httpClientProvider.overrideWithValue(
        MockClient((_) async => throw http.ClientException('offline')),
      ),
      activeStylistProvider.overrideWithValue(stylist),
    ],
  );

  testWidgets('pedir ao stylist: ideia com a razão, outra ideia e mudança', (
    tester,
  ) async {
    final stylist = FakeStylist([
      [('t_shirt', 'main_top'), ('jeans', 'bottom'), ('sneakers', 'footwear')],
      [('shirt', 'main_top'), ('jeans', 'bottom'), ('sneakers', 'footwear')],
      PhotoReadFailure.busy,
    ]);
    final app = await start(tester, stylist);
    await seed(tester, app.db);

    await scrollTo(tester, find.byKey(const Key('stylist-ask')));
    await tester.tap(find.byKey(const Key('stylist-ask')));
    await settleUntil(tester, find.byKey(const Key('stylist-why')));
    expect(find.text('Ideia 1'), findsOne);
    expect(find.text('Porque combina (1).'), findsOne);
    expect(
      find.descendant(
        of: find.byKey(const Key('stylist-pick')),
        matching: find.textContaining('Branca'),
      ),
      findsOne,
    );

    await scrollTo(tester, find.byKey(const Key('stylist-another')));
    await tester.tap(find.byKey(const Key('stylist-another')));
    await settleUntil(tester, find.text('Ideia 2'));
    // "Outra ideia" manda a anterior para não a repetir.
    expect((stylist.briefs[1]['previous']! as List), hasLength(3));
    expect(stylist.briefs[1]['ask'], isNull);
    expect(
      find.descendant(
        of: find.byKey(const Key('stylist-pick')),
        matching: find.textContaining('Oxford'),
      ),
      findsOne,
    );

    await scrollTo(tester, find.byKey(const Key('stylist-change')));
    await tester.enterText(
      find.byKey(const Key('stylist-change')),
      'mais arranjado',
    );
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await settleUntil(tester, find.byKey(const Key('stylist-error')));
    expect(stylist.briefs[2]['ask'], 'mais arranjado');
    // Falhou: a ideia anterior e a sugestão do motor continuam.
    expect(find.text('Ideia 2'), findsOne);
    expect(find.byKey(const Key('suggestion-0')), findsOne);

    await scrollTo(tester, find.byKey(const Key('stylist-wear')));
    await tester.tap(find.byKey(const Key('stylist-wear')));
    await settle(tester);
    expect(find.text('O que vestiste hoje?'), findsOne);
    expect(find.text('3 peças escolhidas'), findsOne);
  });

  testWidgets('sem o Gemini ligado, não há botão', (tester) async {
    final app = await start(tester, null);
    await seed(tester, app.db);
    expect(
      find.byKey(const Key('stylist-ask'), skipOffstage: false),
      findsNothing,
    );
  });
}
