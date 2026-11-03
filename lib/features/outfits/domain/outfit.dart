import '../../wardrobe/domain/garment.dart';
import '../../wardrobe/domain/garment_attributes.dart';
import '../../wardrobe/domain/garment_category.dart';

/// Papel de uma peça num conjunto. Contextual: a mesma t-shirt pode ser o
/// top principal num conjunto e uma camada noutro.
enum OutfitRole {
  mainTop('main_top', single: true),
  midLayer('mid_layer'),
  outerLayer('outer_layer'),
  bottom('bottom', single: true),
  onePiece('one_piece', single: true),
  footwear('footwear', single: true),
  accessory('accessory');

  const OutfitRole(this.id, {this.single = false});
  final String id;

  /// Só pode haver uma peça com este papel num conjunto.
  final bool single;

  static OutfitRole? fromId(String? id) {
    for (final r in values) {
      if (r.id == id) return r;
    }
    return null;
  }

  /// Papel proposto para uma peça acabada de juntar; o utilizador corrige.
  static OutfitRole suggestFor(
    GarmentCategory category,
    Iterable<OutfitRole> taken,
  ) {
    final used = taken.toSet();
    final base = switch (category.group) {
      CategoryGroup.top =>
        used.contains(mainTop) || used.contains(onePiece) ? midLayer : mainTop,
      CategoryGroup.bottom => bottom,
      CategoryGroup.onePiece => onePiece,
      CategoryGroup.outerwear => outerLayer,
      CategoryGroup.footwear => footwear,
      CategoryGroup.accessory || CategoryGroup.other => accessory,
    };
    // Um papel único já ocupado nunca é proposto duas vezes.
    return base.single && used.contains(base) ? accessory : base;
  }
}

final class OutfitItem {
  const OutfitItem(this.garmentId, this.role);

  final GarmentId garmentId;
  final OutfitRole role;

  @override
  bool operator ==(Object other) =>
      other is OutfitItem && other.garmentId == garmentId && other.role == role;

  @override
  int get hashCode => Object.hash(garmentId, role);
}

/// Composição guardada e reutilizável. Não é um plano nem uma utilização.
final class Outfit {
  const Outfit({
    required this.id,
    required this.items,
    required this.createdAt,
    required this.updatedAt,
    this.name,
    this.occasions = const {},
  });

  final String id;
  final String? name;
  final Set<Occasion> occasions;

  /// Pela ordem das camadas.
  final List<OutfitItem> items;
  final DateTime createdAt;
  final DateTime updatedAt;

  OutfitDraft toDraft() =>
      OutfitDraft(name: name, occasions: occasions, items: items);
}

final class OutfitDraft {
  const OutfitDraft({
    required this.items,
    this.name,
    this.occasions = const {},
  });

  final String? name;
  final Set<Occasion> occasions;
  final List<OutfitItem> items;
}

enum OutfitProblem {
  noItems,
  tooManyItems,
  duplicateGarment,
  roleTaken,
  nameTooLong,
}

abstract final class OutfitRules {
  /// Iguais ao servidor (`outfit_items_valid`, `outfits.name`).
  static const maxItems = 20;
  static const maxName = 120;

  static OutfitProblem? validate(OutfitDraft draft) {
    if ((draft.name?.length ?? 0) > maxName) return OutfitProblem.nameTooLong;
    final items = draft.items;
    if (items.isEmpty) return OutfitProblem.noItems;
    if (items.length > maxItems) return OutfitProblem.tooManyItems;
    if (items.map((i) => i.garmentId).toSet().length != items.length) {
      return OutfitProblem.duplicateGarment;
    }
    for (final role in OutfitRole.values.where((r) => r.single)) {
      if (items.where((i) => i.role == role).length > 1) {
        return OutfitProblem.roleTaken;
      }
    }
    return null;
  }

  /// O que falta para um conjunto completo: top principal + parte de baixo
  /// + calçado, ou peça única + calçado. Camadas e acessórios nunca são
  /// obrigatórios. Informativo: um conjunto incompleto pode ser guardado.
  static Set<OutfitRole> missing(Iterable<OutfitItem> items) {
    final roles = {for (final i in items) i.role};
    return {
      if (!roles.contains(OutfitRole.onePiece)) ...{
        if (!roles.contains(OutfitRole.mainTop)) OutfitRole.mainTop,
        if (!roles.contains(OutfitRole.bottom)) OutfitRole.bottom,
      },
      if (!roles.contains(OutfitRole.footwear)) OutfitRole.footwear,
    };
  }
}
