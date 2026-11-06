import 'garment_category.dart';
import 'reference_color.dart';

/// Categoria provável pelo nome do produto na loja (português, inglês e
/// espanhol). É um ponto de partida para as peças que entram sozinhas pelo
/// atalho: o utilizador muda-a no cartão. `null` se nada bater.
///
/// Ganha a palavra de peça que aparece primeiro ("camisa de ganga" é uma
/// camisa). Palavras que também descrevem o tecido ou o estilo ("ganga",
/// "malha", "polo") só contam se não houver outra.
GarmentCategory? categoryFromText(String? text) {
  if (text == null) return null;
  final words = ' ${plainText(text)} ';
  GarmentCategory? weak;
  var weakAt = -1;
  GarmentCategory? strong;
  var strongAt = -1;
  for (final (category, keys, isWeak) in _rules) {
    for (final key in keys) {
      final at = words.indexOf(' $key ');
      if (at < 0) continue;
      if (isWeak) {
        if (weakAt < 0 || at < weakAt) (weak, weakAt) = (category, at);
      } else if (strongAt < 0 || at < strongAt) {
        (strong, strongAt) = (category, at);
      }
    }
  }
  return strong ?? weak;
}

/// Categoria a partir do caminho da loja ("Homem > Casacos > Blazers"): o
/// troço mais específico (o último) que se reconheça.
GarmentCategory? categoryFromTrail(String? trail) {
  if (trail == null) return null;
  for (final part in trail.split('>').reversed) {
    if (categoryFromText(part) case final c?) return c;
  }
  return null;
}

/// Cores de referência pelo nome da cor na loja ("Azul marinho", "Cru",
/// "Preto / Branco"), pela ordem em que aparecem. Vazio se nada bater.
List<ReferenceColor> colorsFromText(String? text) {
  if (text == null) return const [];
  var words = ' ${plainText(text)} ';
  final found = <(int, ReferenceColor)>[];
  // As expressões mais compridas primeiro: "azul marinho" antes de "azul".
  final keys = [
    for (final MapEntry(:key, :value) in _colorWords.entries) (key, value),
  ]..sort((a, b) => b.$1.length.compareTo(a.$1.length));
  for (final (key, color) in keys) {
    final at = words.indexOf(' $key ');
    if (at < 0) continue;
    found.add((at, color));
    words = words.replaceFirst(' $key ', ' ${'#' * key.length} ');
  }
  found.sort((a, b) => a.$1.compareTo(b.$1));
  return {for (final (_, c) in found) c}.toList();
}

/// Minúsculas, sem acentos e só letras, separadas por um espaço.
String plainText(String s) {
  const from = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
  const to = 'aaaaaeeeeiiiiooooouuuucn';
  final out = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final i = from.indexOf(ch);
    out.write(i >= 0 ? to[i] : ch);
  }
  return out.toString().replaceAll(RegExp('[^a-z]+'), ' ').trim();
}

const _rules = <(GarmentCategory, List<String>, bool)>[
  (
    GarmentCategory.cardigan,
    ['casaco de malha', 'cardigan', 'cardigans', 'chaqueta de punto'],
    false,
  ),
  (
    GarmentCategory.tShirt,
    [
      't shirt',
      't shirts',
      'tshirt',
      'tshirts',
      'camiseta',
      'camisetas',
      'tee',
    ],
    false,
  ),
  (
    GarmentCategory.sweatshirt,
    ['sweatshirt', 'sweatshirts', 'hoodie', 'hoodies', 'sudadera', 'sudaderas'],
    false,
  ),
  (GarmentCategory.sweatshirt, ['sweat'], true),
  (GarmentCategory.polo, ['polos'], false),
  (GarmentCategory.polo, ['polo'], true),
  (
    GarmentCategory.jeans,
    ['calcas de ganga', 'jeans', 'vaqueros', 'vaquero'],
    false,
  ),
  (GarmentCategory.jeans, ['ganga', 'denim', 'jean'], true),
  (
    GarmentCategory.jumpsuit,
    ['macacao', 'macacoes', 'jumpsuit', 'jardineiras', 'mono'],
    false,
  ),
  (GarmentCategory.dress, ['vestido', 'vestidos', 'dress', 'dresses'], false),
  (
    GarmentCategory.skirt,
    ['saia', 'saias', 'skirt', 'skirts', 'falda', 'faldas'],
    false,
  ),
  (
    GarmentCategory.shorts,
    ['calcoes', 'bermuda', 'bermudas', 'shorts', 'short'],
    false,
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
    false,
  ),
  (
    GarmentCategory.blazer,
    ['blazer', 'blazers', 'americana', 'americanas', 'fato', 'fatos', 'suit'],
    false,
  ),
  (
    GarmentCategory.raincoat,
    [
      'gabardina',
      'gabardinas',
      'impermeavel',
      'trench',
      'raincoat',
      'chubasquero',
    ],
    false,
  ),
  (
    GarmentCategory.jacket,
    [
      'blusao',
      'blusoes',
      'bomber',
      'jacket',
      'jackets',
      'jaqueta',
      'cazadora',
      'cazadoras',
      'sobrecamisa',
      'sobrecamisas',
      'overshirt',
      'colete',
      'coletes',
      'chaleco',
      'gilet',
    ],
    false,
  ),
  (
    GarmentCategory.coat,
    [
      'casaco',
      'casacos',
      'sobretudo',
      'sobretudos',
      'coat',
      'coats',
      'parka',
      'parkas',
      'anorak',
      'abrigo',
      'abrigos',
      'puffer',
      'kispo',
      'acolchoado',
    ],
    false,
  ),
  (
    GarmentCategory.sweater,
    [
      'camisola',
      'camisolas',
      'pullover',
      'sweater',
      'sweaters',
      'jumper',
      'jersey',
      'jerseis',
    ],
    false,
  ),
  (
    GarmentCategory.sweater,
    ['malha', 'malhas', 'tricot', 'knit', 'knitwear', 'punto'],
    true,
  ),
  (
    GarmentCategory.shirt,
    ['camisa', 'camisas', 'shirt', 'shirts', 'blusa', 'blusas', 'blouse'],
    false,
  ),
  (
    GarmentCategory.top,
    ['top', 'tops', 'body', 'corpete', 'bustier', 'regata', 'tank'],
    false,
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
      'deportivas',
    ],
    false,
  ),
  (
    GarmentCategory.boots,
    ['botas', 'bota', 'botins', 'botim', 'boots', 'boot', 'botines'],
    false,
  ),
  (
    GarmentCategory.sandals,
    ['sandalias', 'sandalia', 'chinelos', 'sandals', 'sandal', 'slides'],
    false,
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
      'calcado',
    ],
    false,
  ),
  (
    GarmentCategory.accessory,
    [
      'cinto',
      'cintos',
      'mala',
      'malas',
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
      'bags',
      'cap',
      'hat',
      'beanie',
      'scarf',
      'socks',
      'tie',
      'gloves',
      'bolso',
      'bolsos',
      'cinturon',
      'bufanda',
      'acessorios',
      'accessories',
      'complementos',
    ],
    false,
  ),
];

const _colorWords = <String, ReferenceColor>{
  'branco': ReferenceColor.white,
  'white': ReferenceColor.white,
  'blanco': ReferenceColor.white,
  'branca': ReferenceColor.white,
  'cru': ReferenceColor.cream,
  'crudo': ReferenceColor.cream,
  'creme': ReferenceColor.cream,
  'cream': ReferenceColor.cream,
  'marfim': ReferenceColor.cream,
  'ivory': ReferenceColor.cream,
  'off white': ReferenceColor.cream,
  'ecru': ReferenceColor.cream,
  'crema': ReferenceColor.cream,
  'bege': ReferenceColor.beige,
  'beige': ReferenceColor.beige,
  'areia': ReferenceColor.beige,
  'arena': ReferenceColor.beige,
  'sand': ReferenceColor.beige,
  'pedra': ReferenceColor.beige,
  'stone': ReferenceColor.beige,
  'nude': ReferenceColor.beige,
  'tostado': ReferenceColor.beige,
  'caqui': ReferenceColor.khaki,
  'kaki': ReferenceColor.khaki,
  'khaki': ReferenceColor.khaki,
  'camel': ReferenceColor.khaki,
  'camelo': ReferenceColor.khaki,
  'castanho': ReferenceColor.brown,
  'castanha': ReferenceColor.brown,
  'brown': ReferenceColor.brown,
  'marron': ReferenceColor.brown,
  'chocolate': ReferenceColor.brown,
  'tabaco': ReferenceColor.brown,
  'cognac': ReferenceColor.brown,
  'conhaque': ReferenceColor.brown,
  'cuero': ReferenceColor.brown,
  'couro': ReferenceColor.brown,
  'vison': ReferenceColor.brown,
  'topo': ReferenceColor.brown,
  'taupe': ReferenceColor.brown,
  'cinzento': ReferenceColor.grey,
  'cinzenta': ReferenceColor.grey,
  'cinza': ReferenceColor.grey,
  'grey': ReferenceColor.grey,
  'gray': ReferenceColor.grey,
  'gris': ReferenceColor.grey,
  'mescla': ReferenceColor.grey,
  'vigore': ReferenceColor.grey,
  'antracite': ReferenceColor.charcoal,
  'antracita': ReferenceColor.charcoal,
  'charcoal': ReferenceColor.charcoal,
  'cinzento escuro': ReferenceColor.charcoal,
  'gris oscuro': ReferenceColor.charcoal,
  'dark grey': ReferenceColor.charcoal,
  'preto': ReferenceColor.black,
  'preta': ReferenceColor.black,
  'black': ReferenceColor.black,
  'negro': ReferenceColor.black,
  'negra': ReferenceColor.black,
  'azul marinho': ReferenceColor.navy,
  'marinho': ReferenceColor.navy,
  'navy': ReferenceColor.navy,
  'marino': ReferenceColor.navy,
  'azul marino': ReferenceColor.navy,
  'azul escuro': ReferenceColor.navy,
  'dark blue': ReferenceColor.navy,
  'azul': ReferenceColor.blue,
  'blue': ReferenceColor.blue,
  'azulon': ReferenceColor.blue,
  'indigo': ReferenceColor.blue,
  'azul claro': ReferenceColor.lightBlue,
  'azul celeste': ReferenceColor.lightBlue,
  'celeste': ReferenceColor.lightBlue,
  'light blue': ReferenceColor.lightBlue,
  'sky blue': ReferenceColor.lightBlue,
  'azul bebe': ReferenceColor.lightBlue,
  'ganga': ReferenceColor.denim,
  'denim': ReferenceColor.denim,
  'azul ganga': ReferenceColor.denim,
  'vaquero': ReferenceColor.denim,
  'verde': ReferenceColor.green,
  'green': ReferenceColor.green,
  'oliva': ReferenceColor.olive,
  'olive': ReferenceColor.olive,
  'verde oliva': ReferenceColor.olive,
  'verde tropa': ReferenceColor.olive,
  'militar': ReferenceColor.olive,
  'verde militar': ReferenceColor.olive,
  'amarelo': ReferenceColor.yellow,
  'amarela': ReferenceColor.yellow,
  'yellow': ReferenceColor.yellow,
  'amarillo': ReferenceColor.yellow,
  'mostarda': ReferenceColor.yellow,
  'mostaza': ReferenceColor.yellow,
  'mustard': ReferenceColor.yellow,
  'laranja': ReferenceColor.orange,
  'orange': ReferenceColor.orange,
  'naranja': ReferenceColor.orange,
  'teja': ReferenceColor.terracotta,
  'terracota': ReferenceColor.terracotta,
  'tijolo': ReferenceColor.terracotta,
  'vermelho': ReferenceColor.red,
  'vermelha': ReferenceColor.red,
  'red': ReferenceColor.red,
  'rojo': ReferenceColor.red,
  'encarnado': ReferenceColor.red,
  'bordeaux': ReferenceColor.burgundy,
  'bordo': ReferenceColor.burgundy,
  'burgundy': ReferenceColor.burgundy,
  'grena': ReferenceColor.burgundy,
  'vinho': ReferenceColor.burgundy,
  'granate': ReferenceColor.burgundy,
  'burdeos': ReferenceColor.burgundy,
  'wine': ReferenceColor.burgundy,
  'rosa': ReferenceColor.pink,
  'pink': ReferenceColor.pink,
  'fucsia': ReferenceColor.pink,
  'fuchsia': ReferenceColor.pink,
  'roxo': ReferenceColor.purple,
  'roxa': ReferenceColor.purple,
  'purple': ReferenceColor.purple,
  'lilas': ReferenceColor.lilac,
  'lilac': ReferenceColor.lilac,
  'malva': ReferenceColor.lilac,
  'morado': ReferenceColor.purple,
  'violeta': ReferenceColor.purple,
  'lila': ReferenceColor.lilac,
  'terracotta': ReferenceColor.terracotta,
  'ferrugem': ReferenceColor.terracotta,
  'rust': ReferenceColor.terracotta,
  'oxido': ReferenceColor.terracotta,
  'ladrillo': ReferenceColor.terracotta,
  'brick': ReferenceColor.terracotta,
  'lavanda': ReferenceColor.lilac,
  'lavender': ReferenceColor.lilac,
  'mauve': ReferenceColor.lilac,
  'menta': ReferenceColor.mint,
  'mint': ReferenceColor.mint,
  'verde menta': ReferenceColor.mint,
  'verde claro': ReferenceColor.mint,
  'light green': ReferenceColor.mint,
  'verde pastel': ReferenceColor.mint,
  'pistacho': ReferenceColor.mint,
  'pistachio': ReferenceColor.mint,
  'pistacio': ReferenceColor.mint,
  'turquesa': ReferenceColor.turquoise,
  'turquoise': ReferenceColor.turquoise,
  'verde agua': ReferenceColor.turquoise,
  'aqua': ReferenceColor.turquoise,
  'aguamarinha': ReferenceColor.turquoise,
  'aguamarina': ReferenceColor.turquoise,
  'aquamarine': ReferenceColor.turquoise,
  'teal': ReferenceColor.turquoise,
  'verde azulado': ReferenceColor.turquoise,
  'prateado': ReferenceColor.silver,
  'prateada': ReferenceColor.silver,
  'prata': ReferenceColor.silver,
  'silver': ReferenceColor.silver,
  'plateado': ReferenceColor.silver,
  'plateada': ReferenceColor.silver,
  'plata': ReferenceColor.silver,
  'aco': ReferenceColor.silver,
  'aco inoxidavel': ReferenceColor.silver,
  'steel': ReferenceColor.silver,
  'stainless steel': ReferenceColor.silver,
  'acero': ReferenceColor.silver,
  'inox': ReferenceColor.silver,
  'metalizado': ReferenceColor.silver,
  'metalico': ReferenceColor.silver,
  'dourado': ReferenceColor.gold,
  'dourada': ReferenceColor.gold,
  'ouro': ReferenceColor.gold,
  'gold': ReferenceColor.gold,
  'dorado': ReferenceColor.gold,
  'dorada': ReferenceColor.gold,
  'oro': ReferenceColor.gold,
  'ouro rosa': ReferenceColor.gold,
  'rose gold': ReferenceColor.gold,
  'oro rosa': ReferenceColor.gold,
};
