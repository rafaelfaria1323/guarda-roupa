import '../../wardrobe/domain/garment.dart';
import '../../wardrobe/domain/garment_category.dart';

/// Âmbito de um valor escolhido pelo utilizador.
enum PolicyScope {
  category('category'),
  garment('garment');

  const PolicyScope(this.id);
  final String id;

  static PolicyScope? fromId(String? id) => switch (id) {
    'category' => category,
    'garment' => garment,
    _ => null,
  };
}

/// Valores escolhidos pelo utilizador que substituem os predefinidos.
/// `0` = sem aviso / sem intervalo; ausência = usar o predefinido.
final class CarePolicies {
  const CarePolicies({
    this.laundryByCategory = const {},
    this.laundryByGarment = const {},
    this.rotationByCategory = const {},
    this.rotationByGarment = const {},
  });

  final Map<GarmentCategory, int> laundryByCategory;
  final Map<GarmentId, int> laundryByGarment;
  final Map<GarmentCategory, int> rotationByCategory;
  final Map<GarmentId, int> rotationByGarment;
}

/// Limites de um valor escolhido (iguais aos do servidor).
abstract final class CareLimits {
  static const maxLaundryAfter = 30;
  static const maxRotationDays = 60;
}
