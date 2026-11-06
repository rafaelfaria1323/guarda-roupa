import 'garment_category.dart';

/// Categoria provável pelo nome do produto na loja (português, inglês e
/// espanhol). É um ponto de partida para as peças que entram sozinhas pelo
/// atalho: o utilizador muda-a no cartão. `null` se nada bater.
GarmentCategory? categoryFromText(String? text) {
  if (text == null) return null;
  final words = _plain(text);
  for (final (category, keys) in _rules) {
    for (final key in keys) {
      if (RegExp('(^| )$key( |\$)').hasMatch(words)) return category;
    }
  }
  return null;
}

/// Minúsculas, sem acentos e só letras, separadas por um espaço.
String _plain(String s) {
  const from = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
  const to = 'aaaaaeeeeiiiiooooouuuucn';
  final out = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final i = from.indexOf(ch);
    out.write(i >= 0 ? to[i] : ch);
  }
  return out.toString().replaceAll(RegExp('[^a-z]+'), ' ').trim();
}

/// Por ordem: as expressões mais específicas primeiro ("casaco de malha"
/// antes de "casaco", "t shirt" antes de "shirt").
const _rules = <(GarmentCategory, List<String>)>[
  (
    GarmentCategory.cardigan,
    ['casaco de malha', 'cardigan', 'cardiga', 'chaqueta de punto'],
  ),
  (GarmentCategory.tShirt, ['t shirt', 'tshirt', 'camiseta', 'tee']),
  (
    GarmentCategory.sweatshirt,
    ['sweatshirt', 'sweat', 'hoodie', 'sudadera', 'camisola com capuz'],
  ),
  (GarmentCategory.polo, ['polo']),
  (
    GarmentCategory.jeans,
    [
      'calcas de ganga',
      'jeans',
      'jean',
      'ganga',
      'denim',
      'vaqueros',
      'vaquero',
    ],
  ),
  (GarmentCategory.jumpsuit, ['macacao', 'jumpsuit', 'jardineiras', 'mono']),
  (GarmentCategory.dress, ['vestido', 'dress']),
  (GarmentCategory.skirt, ['saia', 'skirt', 'falda']),
  (
    GarmentCategory.shorts,
    ['calcoes', 'bermuda', 'bermudas', 'shorts', 'short'],
  ),
  (
    GarmentCategory.trousers,
    [
      'calcas',
      'calca',
      'trousers',
      'pants',
      'chino',
      'chinos',
      'pantalon',
      'pantalones',
      'leggings',
    ],
  ),
  (GarmentCategory.blazer, ['blazer', 'americana']),
  (
    GarmentCategory.raincoat,
    ['gabardina', 'impermeavel', 'trench', 'raincoat', 'chubasquero'],
  ),
  (
    GarmentCategory.jacket,
    [
      'blusao',
      'bomber',
      'jacket',
      'jaqueta',
      'cazadora',
      'sobrecamisa',
      'overshirt',
      'colete',
      'chaleco',
    ],
  ),
  (
    GarmentCategory.coat,
    [
      'casaco',
      'sobretudo',
      'coat',
      'parka',
      'anorak',
      'abrigo',
      'puffer',
      'kispo',
    ],
  ),
  (
    GarmentCategory.sweater,
    ['camisola', 'malha', 'pullover', 'sweater', 'jumper', 'jersey', 'tricot'],
  ),
  (GarmentCategory.shirt, ['camisa', 'shirt', 'blusa', 'blouse']),
  (
    GarmentCategory.top,
    ['top', 'body', 'cai cai', 'corpete', 'bustier', 'regata', 'tank'],
  ),
  (
    GarmentCategory.sneakers,
    [
      'sapatilhas',
      'sapatilha',
      'tenis',
      'sneakers',
      'sneaker',
      'trainers',
      'zapatillas',
    ],
  ),
  (
    GarmentCategory.boots,
    ['botas', 'bota', 'botins', 'botim', 'boots', 'boot', 'botines'],
  ),
  (
    GarmentCategory.sandals,
    ['sandalias', 'sandalia', 'chinelos', 'sandals', 'sandal', 'slides'],
  ),
  (
    GarmentCategory.shoes,
    [
      'sapatos',
      'sapato',
      'mocassins',
      'mocassim',
      'shoes',
      'loafers',
      'zapatos',
      'bailarinas',
      'sabrinas',
    ],
  ),
  (
    GarmentCategory.accessory,
    [
      'cinto',
      'mala',
      'carteira',
      'bone',
      'chapeu',
      'gorro',
      'cachecol',
      'lenco',
      'oculos',
      'meias',
      'gravata',
      'luvas',
      'belt',
      'bag',
      'cap',
      'hat',
      'beanie',
      'scarf',
      'socks',
      'tie',
      'gloves',
      'bolso',
      'cinturon',
      'bufanda',
    ],
  ),
];
