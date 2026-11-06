import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/features/wear/application/wear_providers.dart';

import '../../support/app_harness.dart';
import '../wardrobe/domain/fakes.dart';
import '../wardrobe/presentation/wardrobe_flow_test.dart' show openWardrobe;

void main() {
  testWidgets('cesto: junta por máquina e tom, "Lavei estas" devolve-as e '
      'desfaz; profissional vai à lavandaria', (tester) async {
    final app = await pumpApp(
      tester,
      overrides: [
        clockProvider.overrideWithValue(
          FixedClock(DateTime.utc(2026, 11, 6, 12)),
        ),
      ],
    );
    Future<void> insert(
      String id,
      String name, {
      String? wash,
      String? care,
      int? rgb,
    }) => tester.runAsync(
      () => app.db.execute(
        'INSERT INTO garments (id, owner_id, category, name, availability, '
        'wash, care, colors, created_at, updated_at, version) '
        "VALUES (?, 'user-a', 't_shirt', ?, 'needs_cleaning', ?, ?, ?, "
        "'2026-11-03T10:00:00Z', '2026-11-03T10:00:00Z', 1)",
        [
          id,
          name,
          wash,
          care,
          if (rgb == null)
            null
          else
            '[{"rgb":$rgb,"proportion":1.0,"confirmed":true}]',
        ],
      ),
    );
    await insert('g1', 'Branca', wash: 'machine_40', rgb: 0xFFFFFF);
    await insert('g2', 'Creme', wash: 'machine_40', rgb: 0xF5F0E1);
    await insert('g3', 'Preta', wash: 'machine_40', rgb: 0x000000);
    await insert('g4', 'Blazer', care: 'Limpeza a seco');
    Future<Map<String, String>> availability() async {
      final rows = (await tester.runAsync(
        () => app.db.getAll('SELECT id, availability FROM garments'),
      ))!;
      return {
        for (final r in rows) r['id'] as String: r['availability'] as String,
      };
    }

    await openWardrobe(tester);
    await settleUntil(tester, find.byKey(const Key('wardrobe-basket')));
    expect(find.text('Cesto · 4'), findsOne);
    await tester.tap(find.byKey(const Key('wardrobe-basket')));
    await settle(tester);

    expect(find.text('Máquina 40° · Claras · 2'), findsOne);
    expect(find.text('Máquina 40° · Escuras · 1'), findsOne);
    expect(find.text('Limpeza profissional · 1'), findsOne);

    const light = Key('basket-load-machine_40-light-action');
    await tester.tap(find.byKey(light));
    await settleUntil(tester, find.text('2 peças disponíveis de novo'));
    expect(await availability(), {
      'g1': 'available',
      'g2': 'available',
      'g3': 'needs_cleaning',
      'g4': 'needs_cleaning',
    });
    final cleanings = await tester.runAsync(
      () => app.db.getAll(
        'SELECT garment_id, cleaned_on FROM cleaning_events '
        'WHERE voided_at IS NULL ORDER BY garment_id',
      ),
    );
    expect(cleanings!.map((r) => (r['garment_id'], r['cleaned_on'])), [
      ('g1', '2026-11-06'),
      ('g2', '2026-11-06'),
    ]);

    await tester.tap(find.text('Desfazer'));
    await settleUntil(tester, find.byKey(light));
    expect((await availability())['g1'], 'needs_cleaning');
    final left = await tester.runAsync(
      () => app.db.getAll(
        'SELECT id FROM cleaning_events WHERE voided_at IS NULL',
      ),
    );
    expect(left, isEmpty);

    await tester.tap(find.byKey(const Key('basket-load-professional-action')));
    await settleUntil(tester, find.byKey(const Key('basket-at-cleaners')));
    expect((await availability())['g4'], 'at_cleaners');
    expect(find.text('Na lavandaria · 1'), findsOne);

    // O aviso com "Desfazer" tapava o botão.
    ScaffoldMessenger.of(tester.element(find.byKey(const Key('basket-list'))))
        .hideCurrentSnackBar();
    await tester.ensureVisible(
      find.byKey(const Key('basket-at-cleaners-action')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('basket-at-cleaners-action')));
    await settleUntil(
      tester,
      find.byKey(const Key('basket-at-cleaners')),
      gone: true,
    );
    expect((await availability())['g4'], 'available');
  });
}
