import 'dart:typed_data';

import '../../../core/domain/result.dart';
import '../../wardrobe/domain/garment.dart';

/// De onde veio um campo da pré-visualização.
enum ImportSource {
  /// Dados estruturados da página (JSON-LD).
  jsonLd,

  /// Pré-visualização para redes sociais (Open Graph): menos fiável.
  openGraph;

  static ImportSource? parse(Object? value) => switch (value) {
    'json-ld' => jsonLd,
    'open-graph' => openGraph,
    _ => null,
  };
}

final class ImportVariant {
  const ImportVariant({this.color, this.size, this.sku, this.image});

  final String? color;
  final String? size;
  final String? sku;
  final String? image;

  factory ImportVariant.fromJson(Map<String, Object?> json) => ImportVariant(
    color: _string(json['color']),
    size: _string(json['size']),
    sku: _string(json['sku']),
    image: _string(json['image']),
  );
}

/// O que a função `import-product` leu da página. Nada disto é gravado sem
/// o utilizador confirmar (docs/features/importacao-de-links.md).
final class ProductPreview {
  const ProductPreview({
    required this.storeName,
    required this.storeInTesting,
    required this.url,
    this.name,
    this.brand,
    this.description,
    this.color,
    this.material,
    this.images = const [],
    this.otherImages = 0,
    this.variants = const [],
    this.sources = const {},
    this.confirm = const {},
  });

  final String storeName;

  /// Loja ainda sem smoke com links reais: avisa que pode falhar.
  final bool storeInTesting;
  final String url;
  final String? name;
  final String? brand;
  final String? description;
  final String? color;
  final String? material;

  /// Só as que a função consegue copiar.
  final List<String> images;

  /// Imagens da página que não se podem copiar (outro domínio).
  final int otherImages;
  final List<ImportVariant> variants;
  final Map<String, ImportSource> sources;

  /// Campos que o utilizador tem de confirmar (`category`, `colors`,
  /// `variant`, `material`, `owned`).
  final Set<String> confirm;

  /// `null` se a resposta não tiver a forma esperada.
  static ProductPreview? fromJson(Map<String, Object?> json) {
    final store = json['store'];
    final product = json['product'];
    final url = _string(json['url']);
    if (store is! Map || product is! Map || url == null) return null;
    final p = product.cast<String, Object?>();
    return ProductPreview(
      storeName: _string(store['name']) ?? '',
      storeInTesting: store['status'] != 'supported',
      url: url,
      name: _string(p['name']),
      brand: _string(p['brand']),
      description: _string(p['description']),
      color: _string(p['color']),
      material: _string(p['material']),
      images: [for (final i in _list(p['images'])) ?_string(i)],
      otherImages: p['otherImages'] is int ? p['otherImages']! as int : 0,
      variants: [
        for (final v in _list(p['variants']))
          if (v is Map) ImportVariant.fromJson(v.cast<String, Object?>()),
      ],
      sources: {
        if (p['sources'] case final Map<Object?, Object?> s)
          for (final MapEntry(:key, :value) in s.entries)
            if (key is String) key: ?ImportSource.parse(value),
      },
      confirm: {
        for (final c in _list(p['confirm']))
          if (c is String) c,
      },
    );
  }
}

sealed class ImportFailure {
  const ImportFailure();
}

/// Link que não é de uma loja da lista.
final class UnsupportedStore extends ImportFailure {
  const UnsupportedStore();
}

final class InvalidLink extends ImportFailure {
  const InvalidLink();
}

/// A loja não respondeu como esperado (bloqueio, página inexistente, ...).
final class FetchFailed extends ImportFailure {
  const FetchFailed(this.reason);

  /// `blocked`, `not_found`, `timeout`, `too_large`, ... (da função).
  final String? reason;
}

/// A página não tem dados de produto legíveis.
final class NoMetadata extends ImportFailure {
  const NoMetadata();
}

final class RateLimited extends ImportFailure {
  const RateLimited();
}

/// Sem sessão ou conta fora da allowlist.
final class NotAllowed extends ImportFailure {
  const NotAllowed();
}

/// Sem rede, função não publicada ou resposta inesperada.
final class ImportUnavailable extends ImportFailure {
  const ImportUnavailable();
}

abstract interface class ProductImporter {
  Future<Result<ProductPreview, ImportFailure>> preview(String url);

  /// Copia uma imagem de [ProductPreview.images].
  Future<Result<Uint8List, ImportFailure>> image(String url);
}

/// O que segue para o formulário da peça, já escolhido pelo utilizador.
/// A categoria e as cores ficam sempre por confirmar no formulário.
final class ImportedGarment {
  const ImportedGarment({
    this.name,
    this.brand,
    this.notes,
    this.material,
    this.images = const [],
    this.failedImages = 0,
  });

  /// Escolhas da pré-visualização, cortadas aos limites da peça.
  factory ImportedGarment.from(
    ProductPreview p, {
    ImportVariant? variant,
    List<Uint8List> images = const [],
    int failedImages = 0,
    required String Function(String) storeColor,
    required String Function(String) size,
  }) {
    final color = variant?.color ?? p.color;
    final notes = [
      ?p.description,
      [
        if (color != null) storeColor(color),
        if (variant?.size case final s?) size(s),
        p.url,
      ].join('\n'),
    ].join('\n\n');
    return ImportedGarment(
      name: _cut(p.name, GarmentRules.maxNameLength),
      brand: _cut(p.brand ?? p.storeName, GarmentRules.maxBrandLength),
      notes: _cutEnd(notes, GarmentRules.maxNotesLength),
      material: p.material,
      images: images,
      failedImages: failedImages,
    );
  }

  /// Preencher à mão, mantendo o link.
  factory ImportedGarment.linkOnly(String url) =>
      ImportedGarment(notes: _cut(url, GarmentRules.maxNotesLength));

  final String? name;
  final String? brand;
  final String? notes;
  final String? material;
  final List<Uint8List> images;

  /// Imagens escolhidas que não se conseguiram copiar.
  final int failedImages;
}

String? _string(Object? x) => x is String && x.trim().isNotEmpty ? x : null;

List<Object?> _list(Object? x) => x is List ? x : const [];

String? _cut(String? s, int max) =>
    s == null || s.length <= max ? s : '${s.substring(0, max - 1)}…';

/// Corta a descrição, nunca o fim (cor, tamanho e link).
String _cutEnd(String s, int max) {
  if (s.length <= max) return s;
  final tail = s.substring(s.lastIndexOf('\n\n') + 2);
  final head = max - tail.length - 3;
  if (head <= 0) return _cut(tail, max)!;
  return '${s.substring(0, head)}…\n\n$tail';
}
