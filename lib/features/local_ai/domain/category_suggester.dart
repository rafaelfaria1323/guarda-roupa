import 'dart:typed_data';

import '../../wardrobe/domain/garment_category.dart';

/// Categorias prováveis de uma foto, da mais provável para a menos; `null`
/// se não conseguir. Nunca escolhe pela pessoa.
abstract interface class CategorySuggester {
  Future<List<GarmentCategory>?> suggest(Uint8List bytes);

  Future<void> close();
}
