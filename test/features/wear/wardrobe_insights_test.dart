import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/features/wardrobe/domain/availability.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_category.dart';
import 'package:guarda_roupa/features/wear/application/wear_providers.dart';
import 'package:guarda_roupa/features/wear/domain/calendar_day.dart';
import 'package:guarda_roupa/features/wear/domain/wardrobe_insights.dart';
import 'package:guarda_roupa/features/wear/domain/wear_event.dart';

import '../../support/app_harness.dart';
import '../wardrobe/domain/fakes.dart';
import '../wardrobe/presentation/wardrobe_flow_test.dart' show openWardrobe;

Garment g(String id, {DateTime? created, bool archived = false}) => Garment(
  id: GarmentId(id),
  category: GarmentCategory.tShirt,
  availability: Availability.available,
  createdAt: created ?? DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
  archivedAt: archived ? DateTime.utc(2026, 2, 1) : null,
);

WearEvent wore(CalendarDay d, List<String> ids) => WearEvent(
  id: '${d.iso}${ids.join()}',
  wornOn: d,
  garmentIds: [for (final i in ids) GarmentId(i)],
  createdAt: DateTime.utc(2026),
);

void main() {
  final today = CalendarDay(2026, 11, 6);
  CalendarDay ago(int n) => today.addDays(-n);

  group('WardrobeInsights', () {
    test('mais usadas, paradas, nunca usadas e novas', () {
      final i = WardrobeInsights.of(
        [
          g('a'),
          g('b'),
          g('c'),
          g('d'),
          g('e', created: DateTime.utc(2026, 11, 1)),
          g('x', archived: true),
        ],
        [
          wore(ago(0), ['a', 'b']),
          wore(ago(3), ['a']),
          wore(ago(29), ['b']),
          wore(ago(30), ['a']), // fora da janela de 30 dias
          wore(ago(60), ['c']),
          wore(ago(90), ['c', 'x']),
          wore(today.addDays(1), ['d']), // futuro não conta
        ],
        today,
      );
      expect(i.active, 5);
      expect(i.wornRecently, 2);
      expect(
        [for (final u in i.mostWorn) '${u.garment.id.value}${u.recentUses}'],
        ['a2', 'b2'],
      );
      expect([for (final u in i.idle) u.garment.id.value], ['c']);
      expect(i.idle.single.lastWornOn, ago(60));
      expect([for (final u in i.neverWorn) u.garment.id.value], ['d']);
      expect(i.fresh, 1);
      expect(i.hasHistory, isTrue);
    });

    test('sem histórico', () {
      final i = WardrobeInsights.of([g('a')], const [], today);
      expect(i.hasHistory, isFalse);
      expect(i.neverWorn.single.garment.id.value, 'a');
      expect(i.mostWorn, isEmpty);
    });

    test('no máximo cinco mais usadas', () {
      final ids = [for (var n = 0; n < 7; n++) 'p$n'];
      final i = WardrobeInsights.of(
        [for (final id in ids) g(id)],
        [wore(today, ids)],
        today,
      );
      expect(i.mostWorn, hasLength(WardrobeInsights.topCount));
    });
  });

  testWidgets('resumo do armário: abre pelo Armário e mostra cada secção', (
    tester,
  ) async {
    final app = await pumpApp(
      tester,
      overrides: [
        clockProvider.overrideWithValue(
          FixedClock(DateTime.utc(2026, 11, 6, 12)),
        ),
      ],
    );
    Future<void> insert(String id, String name, String created) =>
        tester.runAsync(
          () => app.db.execute(
            'INSERT INTO garments (id, owner_id, category, name, availability, '
            'colors, created_at, updated_at, version) '
            "VALUES (?, 'user-a', 't_shirt', ?, 'available', '[]', ?, ?, 1)",
            [id, name, created, created],
          ),
        );
    Future<void> wear(String day, List<String> ids) => tester.runAsync(
      () => app.db.execute(
        'INSERT INTO wear_events (id, owner_id, worn_on, garment_ids, '
        'created_at, updated_at) VALUES (uuid(), ?, ?, ?, ?, ?)',
        [
          'user-a',
          day,
          '[${ids.map((i) => '"$i"').join(',')}]',
          '${day}T12:00:00Z',
          '${day}T12:00:00Z',
        ],
      ),
    );
    await insert('g1', 'Favorita', '2026-01-01T10:00:00Z');
    await insert('g2', 'Esquecida', '2026-01-01T10:00:00Z');
    await insert('g3', 'Por estrear', '2026-01-01T10:00:00Z');
    await insert('g4', 'Nova', '2026-11-05T10:00:00Z');
    await wear('2026-11-05', ['g1']);
    await wear('2026-11-02', ['g1']);
    await wear('2026-07-01', ['g2']);

    await openWardrobe(tester);
    await settleUntil(tester, find.byKey(const Key('wardrobe-insights')));
    await tester.tap(find.byKey(const Key('wardrobe-insights')));
    await settleUntil(tester, find.text('Resumo do armário'));

    expect(find.text('Usaste 1 de 4 peças nos últimos 30 dias.'), findsOne);
    expect(find.byKey(const Key('insights-most-g1')), findsOne);
    expect(find.text('2 vezes'), findsOne);
    expect(find.byKey(const Key('insights-idle-g2')), findsOne);
    expect(find.text('há 128 dias'), findsOne);
    await tester.scrollUntilVisible(
      find.byKey(const Key('insights-fresh')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('insights-never-g3')), findsOne);
    expect(find.text('1 peça nova ainda por estrear.'), findsOne);

    await tester.tap(find.byKey(const Key('insights-never-g3')));
    await settle(tester);
    expect(find.text('Por estrear'), findsWidgets);
  });
}
