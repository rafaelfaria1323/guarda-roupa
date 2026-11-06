import '../../shopping/domain/wardrobe_gaps.dart';
import 'inspiration.dart';

/// Uma inspiração em texto para o Gemini (docs/features/ia-gemini.md): só
/// as etiquetas confirmadas. Nunca a imagem, o link nem as notas.
Map<String, Object?> inspirationBrief(Inspiration i) => {
  'title': ?i.title,
  'palette': [for (final rgb in i.palette) nearestReference(rgb).id],
  'formality': ?i.formality?.id,
  'patterns': [for (final p in i.patterns) p.id],
  'textures': [for (final t in i.textures) t.id],
  'occasions': [for (final o in i.occasions) o.id],
  'proportions': [for (final p in i.proportions) p.id],
};
