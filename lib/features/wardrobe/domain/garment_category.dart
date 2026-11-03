/// Grupo de uma categoria, usado para filtros e organização.
///
/// Não determina o papel da peça num conjunto: uma t-shirt (`top`) pode ser
/// o top principal ou uma camada base, consoante a composição.
enum CategoryGroup {
  top,
  bottom,
  onePiece,
  outerwear,
  footwear,
  accessory,
  other,
}

/// Categorias de peça com identificadores estáveis (persistidos e
/// sincronizados). A tradução é feita apenas na apresentação.
enum GarmentCategory {
  tShirt('t_shirt', CategoryGroup.top),
  shirt('shirt', CategoryGroup.top),
  polo('polo', CategoryGroup.top),
  top('top', CategoryGroup.top),
  sweater('sweater', CategoryGroup.top),
  sweatshirt('sweatshirt', CategoryGroup.top),
  cardigan('cardigan', CategoryGroup.top),
  trousers('trousers', CategoryGroup.bottom),
  jeans('jeans', CategoryGroup.bottom),
  shorts('shorts', CategoryGroup.bottom),
  skirt('skirt', CategoryGroup.bottom),
  dress('dress', CategoryGroup.onePiece),
  jumpsuit('jumpsuit', CategoryGroup.onePiece),
  jacket('jacket', CategoryGroup.outerwear),
  blazer('blazer', CategoryGroup.outerwear),
  coat('coat', CategoryGroup.outerwear),
  raincoat('raincoat', CategoryGroup.outerwear),
  sneakers('sneakers', CategoryGroup.footwear),
  shoes('shoes', CategoryGroup.footwear),
  boots('boots', CategoryGroup.footwear),
  sandals('sandals', CategoryGroup.footwear),
  accessory('accessory', CategoryGroup.accessory),
  other('other', CategoryGroup.other);

  const GarmentCategory(this.id, this.group);

  /// Identificador estável; nunca alterar um valor existente.
  final String id;
  final CategoryGroup group;

  static GarmentCategory? fromId(String id) {
    for (final category in values) {
      if (category.id == id) return category;
    }
    return null;
  }
}
