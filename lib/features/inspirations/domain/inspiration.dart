import '../../wardrobe/domain/garment_attributes.dart';

/// Formalidade de uma referência (docs/features/inspiracoes-e-estilo.md).
enum Formality {
  relaxed('relaxed'),
  smartCasual('smart_casual'),
  dressy('dressy');

  const Formality(this.id);
  final String id;

  static Formality? fromId(String? id) {
    for (final f in values) {
      if (f.id == id) return f;
    }
    return null;
  }
}

/// Uma referência de estilo: título e/ou link, com etiquetas confirmadas
/// pelo utilizador. Não é posse: não aparece no guarda-roupa nem é
/// sugerida como peça. A app não abre nem analisa o link.
final class Inspiration {
  const Inspiration({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    this.title,
    this.sourceUrl,
    this.notes,
    this.palette = const [],
    this.formality,
    this.patterns = const {},
    this.textures = const {},
    this.occasions = const {},
  });

  final String id;
  final String? title;
  final String? sourceUrl;
  final String? notes;

  /// RGB `0xRRGGBB`, pela ordem escolhida.
  final List<int> palette;
  final Formality? formality;
  final Set<GarmentPattern> patterns;
  final Set<SurfaceTexture> textures;
  final Set<Occasion> occasions;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Domínio do link (ex.: `pinterest.com`), para mostrar.
  String? get sourceHost {
    final host = Uri.tryParse(sourceUrl ?? '')?.host;
    if (host == null || host.isEmpty) return null;
    return host.startsWith('www.') ? host.substring(4) : host;
  }

  bool get hasTags =>
      palette.isNotEmpty ||
      formality != null ||
      patterns.isNotEmpty ||
      textures.isNotEmpty ||
      occasions.isNotEmpty;

  InspirationDraft toDraft() => InspirationDraft(
    title: title,
    sourceUrl: sourceUrl,
    notes: notes,
    palette: palette,
    formality: formality,
    patterns: patterns,
    textures: textures,
    occasions: occasions,
  );
}

final class InspirationDraft {
  const InspirationDraft({
    this.title,
    this.sourceUrl,
    this.notes,
    this.palette = const [],
    this.formality,
    this.patterns = const {},
    this.textures = const {},
    this.occasions = const {},
  });

  final String? title;
  final String? sourceUrl;
  final String? notes;
  final List<int> palette;
  final Formality? formality;
  final Set<GarmentPattern> patterns;
  final Set<SurfaceTexture> textures;
  final Set<Occasion> occasions;

  /// Texto aparado; vazio passa a `null`. O link ganha `https://` se vier
  /// sem esquema (ex.: `pinterest.com/pin/1`).
  InspirationDraft normalized() => InspirationDraft(
    title: _clean(title),
    sourceUrl: InspirationRules.normalizeUrl(sourceUrl),
    notes: _clean(notes),
    palette: palette,
    formality: formality,
    patterns: patterns,
    textures: textures,
    occasions: occasions,
  );

  static String? _clean(String? s) {
    final t = s?.trim();
    return t == null || t.isEmpty ? null : t;
  }
}

enum InspirationProblem {
  /// Sem título nem link.
  empty,
  titleTooLong,
  invalidUrl,
  notesTooLong,
  tooManyColors,
}

abstract final class InspirationRules {
  static const maxTitle = 120;
  static const maxUrl = 2048;
  static const maxNotes = 1000;
  static const maxColors = 8;

  static String? normalizeUrl(String? raw) {
    final t = raw?.trim();
    if (t == null || t.isEmpty) return null;
    return RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:').hasMatch(t) ? t : 'https://$t';
  }

  /// Só `http(s)` com domínio e sem espaços (o mesmo que o servidor).
  static bool validUrl(String url) =>
      url.length <= maxUrl &&
      RegExp(r'^https?://[^\s/?#]+\S*$').hasMatch(url) &&
      (Uri.tryParse(url)?.host.isNotEmpty ?? false);

  /// Valida um rascunho já [InspirationDraft.normalized].
  static InspirationProblem? validate(InspirationDraft d) {
    if (d.title == null && d.sourceUrl == null) {
      return InspirationProblem.empty;
    }
    if ((d.title?.length ?? 0) > maxTitle) {
      return InspirationProblem.titleTooLong;
    }
    if (d.sourceUrl case final url? when !validUrl(url)) {
      return InspirationProblem.invalidUrl;
    }
    if ((d.notes?.length ?? 0) > maxNotes) {
      return InspirationProblem.notesTooLong;
    }
    if (d.palette.length > maxColors ||
        d.palette.toSet().length != d.palette.length) {
      return InspirationProblem.tooManyColors;
    }
    return null;
  }
}
