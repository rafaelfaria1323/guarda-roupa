import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/core/domain/result.dart';
import 'package:guarda_roupa/features/wardrobe/domain/availability.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_category.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_factory.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_filter.dart';

import 'fakes.dart';

void main() {
  final factory = GarmentFactory(
    clock: FixedClock(DateTime.utc(2026, 11, 3)),
    newId: sequentialIds(),
  );
  Garment make(GarmentDraft draft) => switch (factory.create(draft)) {
    Ok(:final value) => value,
    Err() => throw StateError('rascunho inválido'),
  };

  final tShirt = make(
    const GarmentDraft(category: GarmentCategory.tShirt, name: 'Básica'),
  );
  final jeans = factory.withAvailability(
    make(
      const GarmentDraft(
        category: GarmentCategory.jeans,
        name: 'Calças de ganga',
        brand: 'Levi’s',
      ),
    ),
    Availability.needsCleaning,
  );
  final coat = factory.archive(
    make(
      const GarmentDraft(
        category: GarmentCategory.coat,
        notes: 'Botões de pressão',
      ),
    ),
  );
  final all = [tShirt, jeans, coat];

  List<Garment> apply(GarmentFilter f) => all.where(f.matches).toList();

  test('por defeito exclui arquivadas', () {
    expect(apply(const GarmentFilter()), [tShirt, jeans]);
    expect(apply(const GarmentFilter(includeArchived: true)), all);
  });

  test('filtra por categoria, grupo e disponibilidade', () {
    expect(apply(const GarmentFilter(categories: {GarmentCategory.jeans})), [
      jeans,
    ]);
    expect(apply(const GarmentFilter(groups: {CategoryGroup.top})), [tShirt]);
    expect(apply(const GarmentFilter(availability: {Availability.available})), [
      tShirt,
    ]);
  });

  test('pesquisa texto sem distinguir maiúsculas nem acentos', () {
    expect(apply(const GarmentFilter(text: 'CALCAS')), [jeans]);
    expect(apply(const GarmentFilter(text: 'levi')), [jeans]);
    expect(apply(const GarmentFilter(text: 'pressao', includeArchived: true)), [
      coat,
    ]);
    expect(apply(const GarmentFilter(text: '   ')), [tShirt, jeans]);
    expect(apply(const GarmentFilter(text: 'inexistente')), isEmpty);
  });

  test('igualdade por valor (o ecrã só recria a consulta se mudar)', () {
    const a = GarmentFilter(
      groups: {CategoryGroup.top, CategoryGroup.footwear},
      text: 'x',
    );
    final b = const GarmentFilter(text: 'x')
        .copyWith(groups: {CategoryGroup.footwear, CategoryGroup.top});
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a == a.copyWith(includeArchived: true), isFalse);
    expect(const GarmentFilter(), const GarmentFilter(text: ''));
  });

  test('isActive', () {
    expect(const GarmentFilter().isActive, isFalse);
    expect(const GarmentFilter(text: '  ').isActive, isFalse);
    expect(
      const GarmentFilter(availability: {Availability.washing}).isActive,
      isTrue,
    );
    expect(const GarmentFilter(includeArchived: true).isActive, isTrue);
  });
}
