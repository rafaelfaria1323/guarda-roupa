import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/core/domain/result.dart';
import 'package:guarda_roupa/features/wardrobe/domain/availability.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_category.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_color.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_factory.dart';

import 'fakes.dart';

Garment ok(Result<Garment, List<DraftProblem>> result) => switch (result) {
  Ok(:final value) => value,
  Err(:final failure) => fail('Esperava sucesso, obteve $failure'),
};

void main() {
  late FixedClock clock;
  late GarmentFactory factory;

  setUp(() {
    clock = FixedClock(DateTime.utc(2026, 11, 3, 10));
    factory = GarmentFactory(clock: clock, newId: sequentialIds());
  });

  test('cria peça só com categoria; o resto fica desconhecido', () {
    final g = ok(
      factory.create(const GarmentDraft(category: GarmentCategory.tShirt)),
    );

    expect(g.id, const GarmentId('id-1'));
    expect(g.name, isNull);
    expect(g.brand, isNull);
    expect(g.colors, isEmpty);
    expect(g.availability, Availability.available);
    expect(g.isCandidate, isTrue);
    expect(g.createdAt, clock.now);
  });

  test('normaliza texto: apara espaços e vazio passa a desconhecido', () {
    final g = ok(
      factory.create(
        const GarmentDraft(
          category: GarmentCategory.jeans,
          name: '  Calças azuis  ',
          brand: '   ',
        ),
      ),
    );
    expect(g.name, 'Calças azuis');
    expect(g.brand, isNull);
  });

  test('rejeita nome demasiado longo e cores acima de 100%', () {
    final result = factory.create(
      GarmentDraft(
        category: GarmentCategory.shirt,
        name: 'x' * (GarmentRules.maxNameLength + 1),
        colors: [
          GarmentColor.create(rgb: 0xFFFFFF, proportion: 0.7)!,
          GarmentColor.create(rgb: 0x000000, proportion: 0.4)!,
        ],
      ),
    );
    expect(
      result,
      isA<Err<Garment, List<DraftProblem>>>().having(
        (e) => e.failure,
        'problems',
        [DraftProblem.nameTooLong, DraftProblem.colorsExceedWhole],
      ),
    );
  });

  test('duplicar cria nova identidade e disponibilidade inicial', () {
    final original = factory.withAvailability(
      ok(
        factory.create(
          const GarmentDraft(category: GarmentCategory.tShirt, name: 'Branca'),
        ),
      ),
      Availability.needsCleaning,
    );

    final copy = ok(factory.create(GarmentDraft.duplicateOf(original)));

    expect(copy.id, isNot(original.id));
    expect(copy.name, 'Branca');
    expect(copy.availability, Availability.available);
    expect(copy.isArchived, isFalse);
  });

  test('editar mantém ID, disponibilidade, arquivo e data de criação', () {
    final created = ok(
      factory.create(const GarmentDraft(category: GarmentCategory.sweater)),
    );
    final archived = factory.archive(
      factory.withAvailability(created, Availability.washing),
    );
    clock.now = clock.now.add(const Duration(hours: 1));

    final edited = ok(
      factory.edit(
        archived,
        const GarmentDraft(category: GarmentCategory.cardigan, name: 'Verde'),
      ),
    );

    expect(edited.id, created.id);
    expect(edited.category, GarmentCategory.cardigan);
    expect(edited.availability, Availability.washing);
    expect(edited.archivedAt, archived.archivedAt);
    expect(edited.createdAt, created.createdAt);
    expect(edited.updatedAt, clock.now);
  });

  test('arquivar é idempotente e a peça deixa de ser candidata', () {
    final g = ok(
      factory.create(const GarmentDraft(category: GarmentCategory.coat)),
    );
    final archived = factory.archive(g);
    clock.now = clock.now.add(const Duration(days: 1));

    expect(archived.isCandidate, isFalse);
    expect(factory.archive(archived).archivedAt, archived.archivedAt);
    expect(factory.unarchive(archived).isArchived, isFalse);
  });

  test('peça indisponível não é candidata', () {
    final g = factory.withAvailability(
      ok(factory.create(const GarmentDraft(category: GarmentCategory.jeans))),
      Availability.drying,
    );
    expect(g.isCandidate, isFalse);
  });
}
