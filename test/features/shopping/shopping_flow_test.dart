import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/core/domain/result.dart';
import 'package:guarda_roupa/features/photo_ai/domain/photo_reader.dart';
import 'package:guarda_roupa/features/shopping/application/shopping_providers.dart';
import 'package:guarda_roupa/features/shopping/domain/shopping_advice.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_category.dart';
import 'package:guarda_roupa/features/wardrobe/domain/reference_color.dart';
import 'package:guarda_roupa/features/wear/application/wear_providers.dart';

import '../../support/app_harness.dart';
import '../wardrobe/domain/fakes.dart';
import '../wardrobe/presentation/wardrobe_flow_test.dart' show openWardrobe;

final class FakeAdvisor implements ShoppingAdvisor {
  final briefs = <Map<String, Object?>>[];

  @override
  Future<Result<List<ShoppingIdea>, PhotoReadFailure>> advise(
    Map<String, Object?> brief,
  ) async {
    briefs.add(brief);
    return const Ok([
      ShoppingIdea(
        category: GarmentCategory.sneakers,
        color: ReferenceColor.black,
        title: 'Ténis pretos em pele',
        why: 'Vão com a tua ganga.',
        search: 'ténis pretos pele',
        brands: [
          ShoppingBrand('COS', BrandTier.same),
          ShoppingBrand('Primark', BrandTier.cheaper),
        ],
      ),
    ]);
  }
}

void main() {
  testWidgets('peças em falta: faltas no aparelho e ideias com marcas', (
    tester,
  ) async {
    final advisor = FakeAdvisor();
    final opened = <Uri>[];
    final app = await pumpApp(
      tester,
      overrides: [
        clockProvider.overrideWithValue(
          FixedClock(DateTime.utc(2026, 11, 6, 12)),
        ),
        activeShoppingAdvisorProvider.overrideWithValue(advisor),
        openLinkProvider.overrideWithValue((uri) async {
          opened.add(uri);
          return true;
        }),
      ],
    );
    for (final (id, category, color, brand) in [
      ('g1', 't_shirt', ReferenceColor.white.rgb, 'Uniqlo'),
      ('g2', 'jeans', ReferenceColor.denim.rgb, 'Levi’s'),
      ('g3', 'sneakers', ReferenceColor.white.rgb, null),
    ]) {
      await tester.runAsync(
        () => app.db.execute(
          'INSERT INTO garments (id, owner_id, category, brand, availability, '
          'colors, created_at, updated_at, version) '
          "VALUES (?, 'user-a', ?, ?, 'available', ?, ?, ?, 1)",
          [
            id,
            category,
            brand,
            '[{"rgb":$color,"proportion":1.0,"confirmed":true}]',
            '2026-01-01T10:00:00Z',
            '2026-01-01T10:00:00Z',
          ],
        ),
      );
    }

    await openWardrobe(tester);
    await settleUntil(tester, find.byKey(const Key('wardrobe-insights')));
    await tester.tap(find.byKey(const Key('wardrobe-insights')));
    await settleUntil(tester, find.text('Resumo do armário'));
    Future<void> scrollTo(Finder f) async {
      await tester.scrollUntilVisible(
        f,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
    }

    await scrollTo(find.byKey(const Key('shopping-ask')));
    expect(find.text('Ainda não tens casacos'), findsOne);
    expect(
      find.text('Só tons claros em calçado: faltava um escuro, como preto'),
      findsOne,
    );

    // "Não me interessa" fica guardado.
    await tester.tap(
      find.byKey(const Key('shopping-dismiss-missingGroup:outerwear:')),
    );
    await settle(tester);
    expect(find.text('Ainda não tens casacos'), findsNothing);

    await tester.enterText(find.byKey(const Key('shopping-budget')), '80');
    await tester.tap(find.byKey(const Key('shopping-ask')));
    await settleUntil(tester, find.text('Ténis pretos em pele'));
    final brief = advisor.briefs.single;
    expect(brief['budget_eur'], 80);
    expect((brief['gaps']! as List).length, 1);
    expect(
      [for (final g in brief['garments']! as List) (g as Map)['brand']],
      ['Uniqlo', 'Levi’s', null],
    );
    expect(find.text('Vão com a tua ganga.'), findsOne);

    await scrollTo(
      find.byKey(const Key('shopping-brand-idea:sneakers:black-COS')),
    );
    await tester.tap(
      find.byKey(const Key('shopping-brand-idea:sneakers:black-COS')),
    );
    await tester.pumpAndSettle();
    expect(opened.single.queryParameters['q'], 'COS ténis pretos pele');

    final rows = (await tester.runAsync(
      () => app.db.getAll(
        "SELECT key, value FROM local_settings WHERE key LIKE 'shopping_%' "
        'ORDER BY key',
      ),
    ))!;
    expect(
      [for (final r in rows) (r['key'], r['value'])],
      [
        ('shopping_budget', '80'),
        ('shopping_dismissed', '["missingGroup:outerwear:"]'),
      ],
    );
  });
}
