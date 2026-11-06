import 'dart:typed_data';

import '../../../core/domain/result.dart';
import '../../wardrobe/data/photo_processor.dart';
import '../../wardrobe/domain/category_from_text.dart';
import '../../wardrobe/domain/garment.dart';
import '../../wardrobe/domain/garment_attributes.dart';
import '../../wardrobe/domain/garment_category.dart';
import '../../wardrobe/domain/garment_color.dart';
import '../../wardrobe/domain/garment_photo.dart';
import '../../wardrobe/domain/photo_colors.dart';
import '../../wardrobe/domain/reference_color.dart';
import '../../wardrobe/domain/wardrobe_repository.dart';
import '../domain/product_import.dart';

/// Passa as peças que o atalho mandou para o Armário, como se tivessem sido
/// introduzidas à mão: o que a loja diz entra, o resto fica por omissão e o
/// utilizador muda depois no cartão.
///
/// - **Categoria:** pelo nome do produto, depois pela categoria ou caminho
///   da loja e pelo link; sem palavra conhecida, "Outro".
/// - **Cores:** pelo nome da cor na loja, quando há uma só; senão da foto
///   de capa. Sempre por confirmar (`confirmed: false`).
/// - **Foto:** só a primeira imagem (cada cópia conta para a quota).
/// - **Notas:** descrição, cor e tamanho da loja (se houver só um) e o link.
///
/// Cada peça sai da caixa depois de criada; se algo falhar, fica lá para a
/// próxima vez. Devolve quantas se criaram.
Future<int> addInboxToWardrobe({
  required List<InboxItem> items,
  required ProductImporter importer,
  required WardrobeRepository repo,
  required Future<PhotoProcessing> Function(Uint8List) processPhoto,
  required String Function(String) storeColor,
  required String Function(String) size,
}) async {
  var created = 0;
  // Da mais antiga para a mais recente: o Armário fica pela ordem de envio.
  for (final item in items.reversed) {
    final p = item.preview;
    final imported = ImportedGarment.from(
      p,
      variant: _onlyVariant(p),
      storeColor: storeColor,
      size: size,
    );
    ProcessedPhoto? photo;
    if (p.images.isNotEmpty) {
      if (await importer.image(p.images.first) case Ok(value: final bytes)) {
        if (await processPhoto(bytes) case Ok(value: final processed)) {
          photo = processed;
        }
      }
    }
    final storeColors = colorsFromText(_onlyColor(p));
    final colors = storeColors.isNotEmpty
        ? _split(storeColors)
        : photo == null
        ? const <GarmentColor>[]
        : _colors(photo.thumb);
    final draft = GarmentDraft(
      category:
          categoryFromText(p.name) ??
          categoryFromTrail(p.category) ??
          categoryFromText(Uri.tryParse(p.url)?.path) ??
          GarmentCategory.other,
      name: imported.name,
      brand: imported.brand,
      notes: imported.notes,
      colors: colors,
      attributes: GarmentAttributes(material: imported.material),
    );
    final result = await repo.addGarment(draft);
    if (result case Ok(value: final garment)) {
      if (photo != null) await repo.addPhoto(garment.id, photo);
      await importer.discardInbox(item.id);
      created++;
    }
  }
  return created;
}

/// A variante só se escolhe sozinha quando há uma única cor (sem tamanho:
/// esse é o utilizador que sabe).
ImportVariant? _onlyVariant(ProductPreview p) {
  final colors = {for (final v in p.variants) ?v.color};
  return colors.length == 1 ? ImportVariant(color: colors.first) : null;
}

/// O nome da cor, se a página só tiver uma.
String? _onlyColor(ProductPreview p) {
  final colors = {?p.color, for (final v in p.variants) ?v.color};
  return colors.length == 1 ? colors.first : null;
}

/// "Preto / Branco": a primeira cor pesa mais.
List<GarmentColor> _split(List<ReferenceColor> colors) {
  const shares = [
    [1.0],
    [0.6, 0.4],
    [0.5, 0.3, 0.2],
  ];
  final chosen = colors.take(3).toList();
  final split = shares[chosen.length - 1];
  return [
    for (final (i, c) in chosen.indexed)
      GarmentColor.create(rgb: c.rgb, proportion: split[i])!,
  ];
}

List<GarmentColor> _colors(Uint8List thumb) {
  try {
    return PhotoColors.suggest(thumb);
  } on Object {
    return const [];
  }
}
