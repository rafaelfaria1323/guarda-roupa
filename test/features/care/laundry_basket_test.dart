import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/features/care/domain/laundry_basket.dart';
import 'package:guarda_roupa/features/wardrobe/domain/availability.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_attributes.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_category.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_color.dart';

final _t0 = DateTime.utc(2026, 11, 6);

Garment g(
  String id, {
  Availability availability = Availability.needsCleaning,
  WashCare? wash,
  String? care,
  int? rgb,
  bool archived = false,
}) => Garment(
  id: GarmentId(id),
  category: GarmentCategory.tShirt,
  availability: availability,
  createdAt: _t0,
  updatedAt: _t0,
  archivedAt: archived ? _t0 : null,
  colors: [if (rgb != null) GarmentColor.create(rgb: rgb, proportion: 1)!],
  attributes: GarmentAttributes(wash: wash, care: care),
);

List<String> ids(List<Garment> list) => [for (final x in list) x.id.value];

void main() {
  test('tom pela cor principal', () {
    expect(Shade.of(g('a', rgb: 0xFFFFFF)), Shade.light);
    expect(Shade.of(g('a', rgb: 0xF5F0E1)), Shade.light);
    expect(Shade.of(g('a', rgb: 0x000000)), Shade.dark);
    expect(Shade.of(g('a', rgb: 0x1F2A44)), Shade.dark);
    expect(Shade.of(g('a', rgb: 0xC0392B)), Shade.colored);
    expect(Shade.of(g('a')), Shade.unknown);
  });

  test('programa pela lavagem marcada ou pelo texto da etiqueta', () {
    expect(
      WashProgram.of(const GarmentAttributes(wash: WashCare.machine40)),
      WashProgram.machine40,
    );
    expect(
      WashProgram.of(const GarmentAttributes(care: 'Limpeza a seco')),
      WashProgram.professional,
    );
    // A lavagem marcada ganha ao texto.
    expect(
      WashProgram.of(
        const GarmentAttributes(wash: WashCare.hand, care: 'Limpeza a seco'),
      ),
      WashProgram.hand,
    );
    expect(WashProgram.of(const GarmentAttributes()), WashProgram.unknown);
  });

  test('junta por máquina e tom; separa a lavar e na lavandaria', () {
    final basket = LaundryBasket.of([
      g('branca', wash: WashCare.machine40, rgb: 0xFFFFFF),
      g('preta', wash: WashCare.machine40, rgb: 0x000000),
      g('cinza-escura', wash: WashCare.machine40, rgb: 0x333333),
      g('fato', care: 'Limpeza a seco', rgb: 0x000000),
      g('lã', wash: WashCare.hand, rgb: 0xFFFFFF),
      g('sem-etiqueta'),
      g('limpa', availability: Availability.available),
      g('arquivada', archived: true),
      g('a-secar', availability: Availability.drying),
      g('fora', availability: Availability.atCleaners),
    ]);
    expect(
      [
        for (final l in basket.loads)
          '${l.program.id}/${l.shade?.id}: ${ids(l.garments).join(',')}',
      ],
      [
        'professional/null: fato',
        'hand/null: lã',
        'machine_40/light: branca',
        'machine_40/dark: preta,cinza-escura',
        'unknown/unknown: sem-etiqueta',
      ],
    );
    expect(ids(basket.inProgress), ['a-secar']);
    expect(ids(basket.atCleaners), ['fora']);
    expect(basket.dirtyCount, 6);
    expect(basket.count, 8);
  });

  test('cesto vazio', () {
    final basket = LaundryBasket.of([
      g('x', availability: Availability.available),
    ]);
    expect(basket.isEmpty, isTrue);
  });
}
