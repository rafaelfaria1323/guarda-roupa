import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/features/wardrobe/domain/category_from_text.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_category.dart';
import 'package:guarda_roupa/features/wardrobe/domain/reference_color.dart';

void main() {
  test('nome da loja: a categoria provável', () {
    const cases = {
      'CASACO EM PELE': GarmentCategory.coat,
      'Casaco de malha canelada': GarmentCategory.cardigan,
      'T-shirt básica': GarmentCategory.tShirt,
      'Camisa de linho': GarmentCategory.shirt,
      'Calças de ganga wide leg': GarmentCategory.jeans,
      'CALÇAS CHINO': GarmentCategory.trousers,
      'Calções de banho': GarmentCategory.shorts,
      'Vestido midi': GarmentCategory.dress,
      'Sweatshirt com capuz': GarmentCategory.sweatshirt,
      'Camisola de malha': GarmentCategory.sweater,
      'Blazer estruturado': GarmentCategory.blazer,
      'Gabardina clássica': GarmentCategory.raincoat,
      'Blusão bomber': GarmentCategory.jacket,
      'Sapatilhas de pele': GarmentCategory.sneakers,
      'Botins com salto': GarmentCategory.boots,
      'Cinto de pele': GarmentCategory.accessory,
      'Ultra Light Down Jacket': GarmentCategory.jacket,
      'Polo piqué': GarmentCategory.polo,
      'Camisa de ganga': GarmentCategory.shirt,
      'Denim shirt': GarmentCategory.shirt,
      'Casaco acolchoado com capuz': GarmentCategory.coat,
      'Camisola polo de malha': GarmentCategory.sweater,
      'Sobrecamisa de lã': GarmentCategory.jacket,
    };
    for (final MapEntry(:key, :value) in cases.entries) {
      expect(categoryFromText(key), value, reason: key);
    }
  });

  test('sem palavra conhecida: nada', () {
    expect(categoryFromText('Peça 123'), isNull);
    expect(categoryFromText(null), isNull);
    // Palavra inteira: "malas" não é "mala", "topo" não é "top".
    expect(categoryFromText('topo da gama'), isNull);
  });

  test('caminho da loja: o troço mais específico', () {
    expect(
      categoryFromTrail('Homem > Casacos > Blazers'),
      GarmentCategory.blazer,
    );
    expect(categoryFromTrail('Mulher > Novidades'), isNull);
  });

  test('nome da cor na loja', () {
    expect(colorsFromText('Azul marinho'), [ReferenceColor.navy]);
    expect(colorsFromText('BEGE'), [ReferenceColor.beige]);
    expect(colorsFromText('Cru'), [ReferenceColor.cream]);
    expect(colorsFromText('Preto / Branco'), [
      ReferenceColor.black,
      ReferenceColor.white,
    ]);
    expect(colorsFromText('Cinzento escuro'), [ReferenceColor.charcoal]);
    expect(colorsFromText('Estampado'), isEmpty);
    expect(colorsFromText('Aço / Verde menta'), [
      ReferenceColor.silver,
      ReferenceColor.mint,
    ]);
    expect(colorsFromText('Dourado'), [ReferenceColor.gold]);
    expect(colorsFromText('Terracota'), [ReferenceColor.terracotta]);
    expect(colorsFromText('Lilás'), [ReferenceColor.lilac]);
    expect(colorsFromText('Verde-água'), [ReferenceColor.turquoise]);
  });
}
