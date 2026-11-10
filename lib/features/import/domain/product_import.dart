import 'dart:convert';
import 'dart:typed_data';

import '../../../core/domain/result.dart';
import '../../wardrobe/domain/category_from_text.dart';
import '../../wardrobe/domain/garment.dart';
import '../../wardrobe/domain/garment_category.dart';

/// De onde veio um campo da pré-visualização.
enum ImportSource {
  /// Dados estruturados da página (JSON-LD).
  jsonLd,

  /// Microdata schema.org na página.
  microdata,

  /// Pré-visualização para redes sociais (Open Graph, Twitter): menos fiável.
  openGraph,

  /// Só o HTML simples (título da página): confirmar.
  html;

  static ImportSource? parse(Object? value) => switch (value) {
    'json-ld' => jsonLd,
    'microdata' => microdata,
    'open-graph' => openGraph,
    'html' => html,
    _ => null,
  };
}

/// O que se sabe do site, pelo perfil que a função atualiza sozinha a cada
/// importação (docs/features/importacao-de-links.md).
enum SiteStatus {
  /// Ainda sem nenhuma importação bem-sucedida.
  newSite,

  /// Já funcionou, mas poucas vezes.
  testing,

  /// Três ou mais sucessos e o último correu bem.
  works,

  /// Três falhas seguidas.
  failing;

  static SiteStatus parse(Object? value) => switch (value) {
    'testing' => testing,
    'works' => works,
    'failing' => failing,
    _ => newSite,
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
    required this.url,
    this.siteStatus = SiteStatus.newSite,
    this.viaShortcut = false,
    this.name,
    this.brand,
    this.description,
    this.color,
    this.material,
    this.category,
    this.images = const [],
    this.variants = const [],
    this.sources = const {},
    this.confirm = const {},
  });

  /// O nome da loja, ou o domínio sem `www.`.
  final String storeName;
  final SiteStatus siteStatus;

  /// Veio do atalho do iPhone (a página aberta no Safari), não do link.
  final bool viaShortcut;
  final String url;
  final String? name;
  final String? brand;
  final String? description;
  final String? color;
  final String? material;

  /// A categoria da loja ("Homem > Casacos"), só uma pista.
  final String? category;

  final List<String> images;
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
      siteStatus: SiteStatus.parse(store['status']),
      viaShortcut: json['via'] == 'shared',
      url: url,
      name: _string(p['name']),
      brand: _string(p['brand']),
      description: _string(p['description']),
      color: _string(p['color']),
      material: _string(p['material']),
      category: _string(p['category']),
      images: [for (final i in _list(p['images'])) ?_string(i)],
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

/// Link para um endereço interno ou local, que a função não abre.
final class NotPublic extends ImportFailure {
  const NotPublic();
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

/// Um link do Pinterest ou do Instagram: é uma inspiração, que só entra
/// pelo atalho (a função não lê estes sites).
final class InspirationSiteLink extends ImportFailure {
  const InspirationSiteLink(this.site);

  final String? site;
}

/// Sem sessão ou conta fora da allowlist.
final class NotAllowed extends ImportFailure {
  const NotAllowed();
}

/// Sem rede, função não publicada ou resposta inesperada.
final class ImportUnavailable extends ImportFailure {
  const ImportUnavailable();
}

/// O que o atalho do iPhone "Importar para o fio" copia da página aberta
/// no Safari (docs/guias/09-atalho-importar-iphone.md): o link, o título,
/// os blocos JSON-LD e as meta tags. Serve as lojas que bloqueiam pedidos
/// automáticos: quem abriu a página foi o utilizador, no browser dele.
final class SharedPage {
  const SharedPage({
    required this.url,
    this.title,
    this.ld = const [],
    this.meta = const [],
  });

  final String url;
  final String? title;
  final List<String> ld;
  final List<(String, String)> meta;

  /// O texto copiado pelo atalho, ou `null` se não for dele.
  static SharedPage? parse(String text) {
    final t = text.trim();
    if (!t.startsWith('{')) return null;
    Object? data;
    try {
      data = jsonDecode(t);
    } on FormatException {
      return null;
    }
    if (data is! Map || data['fio'] != 1) return null;
    final url = data['url'];
    if (url is! String || url.isEmpty) return null;
    final title = data['title'];
    return SharedPage(
      url: url,
      title: title is String ? title : null,
      ld: [
        for (final b in _list(data['ld']))
          if (b is String) b,
      ],
      meta: [
        for (final m in _list(data['meta']))
          if (m case [final String k, final String v]) (k, v),
      ],
    );
  }

  /// O `page` do pedido à função.
  Map<String, Object?> toJson() => {
    'title': ?title,
    'ld': ld,
    'meta': [
      for (final (k, v) in meta) [k, v],
    ],
  };
}

abstract interface class ProductImporter {
  Future<Result<ProductPreview, ImportFailure>> preview(String url);

  /// Pré-visualização de uma página partilhada pelo atalho do iPhone. A
  /// função não pede nada à loja.
  Future<Result<ProductPreview, ImportFailure>> previewShared(SharedPage page);

  /// Copia uma imagem de [ProductPreview.images].
  Future<Result<Uint8List, ImportFailure>> image(String url);

  /// As peças que o atalho do iPhone mandou e esperam na caixa "Por
  /// importar", da mais recente para a mais antiga.
  Future<Result<List<InboxItem>, ImportFailure>> inbox();

  /// As inspirações (Pins, publicações do Instagram) que o atalho mandou,
  /// na mesma caixa, da mais recente para a mais antiga.
  Future<Result<List<InspirationInboxItem>, ImportFailure>> inspirationInbox();

  /// Tira uma peça ou inspiração da caixa (usada ou descartada).
  Future<Result<void, ImportFailure>> discardInbox(String id);

  /// Há uma chave do atalho ativa?
  Future<Result<ShortcutKeyStatus, ImportFailure>> shortcutKeyStatus();

  /// Nova chave do atalho (a anterior deixa de servir). Só se vê agora.
  Future<Result<String, ImportFailure>> createShortcutKey();

  /// Desliga o atalho: a chave deixa de servir.
  Future<Result<void, ImportFailure>> revokeShortcutKey();

  /// O endereço para onde o atalho manda a página.
  String get shortcutEndpoint;
}

/// Uma peça mandada pelo atalho, já lida, à espera na caixa.
final class InboxItem {
  const InboxItem({
    required this.id,
    required this.preview,
    required this.createdAt,
  });

  final String id;
  final ProductPreview preview;
  final DateTime createdAt;

  /// `null` se a linha não tiver a forma esperada.
  static InboxItem? fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final preview = json['preview'];
    final created = DateTime.tryParse('${json['created_at']}');
    if (id is! String || preview is! Map || created == null) return null;
    final p = ProductPreview.fromJson(preview.cast<String, Object?>());
    if (p == null) return null;
    return InboxItem(id: id, preview: p, createdAt: created);
  }
}

/// Uma inspiração mandada pelo atalho a partir de um Pin (ou publicação do
/// Instagram) aberto no Safari: só o link, o título e a descrição da
/// página. Sem imagem: o fio não a pede ao site.
final class InspirationInboxItem {
  const InspirationInboxItem({
    required this.id,
    required this.site,
    required this.url,
    required this.createdAt,
    this.title,
    this.description,
  });

  final String id;

  /// "Pinterest" ou "Instagram".
  final String site;
  final String url;
  final String? title;
  final String? description;
  final DateTime createdAt;

  /// `null` se a linha não for uma inspiração com a forma esperada.
  static InspirationInboxItem? fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final preview = json['preview'];
    final created = DateTime.tryParse('${json['created_at']}');
    if (id is! String || preview is! Map || created == null) return null;
    if (preview['kind'] != 'inspiration') return null;
    final url = preview['url'];
    if (url is! String || url.isEmpty) return null;
    final site = preview['site'];
    final found = preview['inspiration'];
    String? text(Object? v) => v is String && v.trim().isNotEmpty ? v : null;
    return InspirationInboxItem(
      id: id,
      site: site is String ? site : '',
      url: url,
      title: found is Map ? text(found['title']) : null,
      description: found is Map ? text(found['description']) : null,
      createdAt: created,
    );
  }
}

/// O estado da chave do atalho, sem a chave (só o hash fica guardado).
final class ShortcutKeyStatus {
  const ShortcutKeyStatus({
    required this.active,
    this.createdAt,
    this.lastUsedAt,
  });

  final bool active;
  final DateTime? createdAt;
  final DateTime? lastUsedAt;

  static ShortcutKeyStatus fromJson(Map<String, Object?> json) =>
      ShortcutKeyStatus(
        active: json['active'] == true,
        createdAt: DateTime.tryParse('${json['created_at']}'),
        lastUsedAt: DateTime.tryParse('${json['last_used_at']}'),
      );
}

/// O que segue para o formulário da peça, já escolhido pelo utilizador.
/// A categoria e as cores ficam sempre por confirmar no formulário.
final class ImportedGarment {
  const ImportedGarment({
    this.name,
    this.brand,
    this.notes,
    this.material,
    this.category,
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
      category:
          categoryFromText(p.name) ??
          categoryFromTrail(p.category) ??
          categoryFromText(Uri.tryParse(p.url)?.path),
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

  /// Pelo nome do produto, pela categoria da loja ou pelo link; uma
  /// sugestão que o utilizador confirma no formulário.
  final GarmentCategory? category;
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
