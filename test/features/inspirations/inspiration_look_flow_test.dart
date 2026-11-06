import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/features/wardrobe/data/powersync_wardrobe_repository.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_category.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_filter.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_color.dart';
import 'package:guarda_roupa/features/wardrobe/domain/reference_color.dart';

import '../../support/app_harness.dart';
import 'inspiration_flow_test.dart'
    show dismissSnackBar, openStyle, saveInspiration, tapTag;

void main() {
  testWidgets('montar com o que tenho: a peça com a cor da inspiração vem '
      'primeiro e diz porquê; a inspiração não muda nada', (tester) async {
    final app = await pumpApp(tester);
    final repo = PowerSyncWardrobeRepository(db: app.db, ownerId: 'user-a');
    await tester.runAsync(() async {
      for (final (c, name, rgb) in [
        (GarmentCategory.tShirt, 'Branca', ReferenceColor.white.rgb),
        (GarmentCategory.tShirt, 'Marinho', ReferenceColor.navy.rgb),
        (GarmentCategory.jeans, 'Calças', ReferenceColor.denim.rgb),
        (GarmentCategory.sneakers, 'Ténis', ReferenceColor.white.rgb),
      ]) {
        await repo.addGarment(
          GarmentDraft(
            category: c,
            name: name,
            colors: [GarmentColor.create(rgb: rgb, proportion: 1)!],
          ),
        );
      }
    });
    await settle(tester);

    await openStyle(tester);
    await tester.tap(find.byKey(const Key('inspiration-add')));
    await settle(tester);
    // Sem guardar ainda não há botão.
    expect(find.byKey(const Key('inspiration-look')), findsNothing);
    await tester.enterText(
      find.byKey(const Key('inspiration-title')),
      'Azul-marinho',
    );
    await tapTag(tester, 'inspiration-color-navy');
    await saveInspiration(tester);
    await dismissSnackBar(tester);

    await tester.tap(find.text('Azul-marinho'));
    await settle(tester);
    final open = find.byKey(const Key('inspiration-look'));
    await tester.scrollUntilVisible(
      open,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await Scrollable.ensureVisible(tester.element(open), alignment: 0.5);
    await tester.pump();
    await tester.tap(open);
    await settle(tester);

    expect(find.text('Montar com o que tenho'), findsOne);
    expect(find.text('Procuro nas tuas peças: cor'), findsOne);
    expect(find.text('Marinho, Calças, Ténis'), findsOne);
    await tester.tap(find.byKey(const Key('suggestion-0-why')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Como na inspiração: cor'),
      findsOne,
      reason: 'só a t-shirt é azul-marinho',
    );

    // Guardar: passa a ser um conjunto com o nome da inspiração.
    final save = find.byKey(const Key('look-0-save'));
    await Scrollable.ensureVisible(tester.element(save), alignment: 0.5);
    await tester.pump();
    await tester.tap(save);
    await settleUntil(
      tester,
      find.text('Um dos teus conjuntos: Azul-marinho', skipOffstage: false),
    );
    expect(
      find.text('Um dos teus conjuntos: Azul-marinho', skipOffstage: false),
      findsOne,
    );
    expect(
      find.byKey(const Key('look-0-save'), skipOffstage: false),
      findsNothing,
    );

    final garments = (await tester.runAsync(
      () => repo.watchGarments(const GarmentFilter()).first,
    ))!;
    expect(garments, hasLength(4), reason: 'a inspiração não cria peças');
  });
}
