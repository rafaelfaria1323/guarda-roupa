import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/domain/result.dart';
import '../../../l10n/app_localizations.dart';
import '../domain/product_import.dart';

/// Colar um link de produto, ver o que se leu e escolher o que segue para a
/// peça nova. Devolve um [ImportedGarment] (ou `null` se o utilizador sair).
/// Nada é gravado aqui: a peça só se cria no formulário.
class ImportLinkScreen extends StatefulWidget {
  const ImportLinkScreen({
    required this.importer,
    required this.maxImages,
    super.key,
  });

  final ProductImporter importer;

  /// Quantas fotos a peça ainda aceita.
  final int maxImages;

  @override
  State<ImportLinkScreen> createState() => _ImportLinkScreenState();
}

class _ImportLinkScreenState extends State<ImportLinkScreen> {
  final _url = TextEditingController();
  bool _busy = false;
  ImportFailure? _failure;
  ProductPreview? _preview;
  ImportVariant? _variant;
  final _images = <String>{};

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _read() async {
    final url = _url.text.trim();
    if (url.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _failure = null;
      _preview = null;
      _variant = null;
      _images.clear();
    });
    final result = await widget.importer.preview(url);
    if (!mounted) return;
    setState(() {
      _busy = false;
      switch (result) {
        case Ok(value: final p):
          _preview = p;
          // Uma imagem por omissão: cada cópia conta para a quota.
          if (p.images.isNotEmpty && widget.maxImages > 0) {
            _images.add(p.images.first);
          }
        case Err(failure: final f):
          _failure = f;
      }
    });
  }

  void _choose(ImportVariant? variant) {
    setState(() {
      _variant = variant;
      final image = variant?.image;
      final p = _preview!;
      if (image != null && p.images.contains(image) && widget.maxImages > 0) {
        _images
          ..clear()
          ..add(image);
      }
    });
  }

  Future<void> _use() async {
    final p = _preview!;
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    final bytes = <Uint8List>[];
    var failed = 0;
    // Pela ordem da página: a primeira fica como capa.
    for (final url in p.images.where(_images.contains)) {
      switch (await widget.importer.image(url)) {
        case Ok(value: final b):
          bytes.add(b);
        case Err():
          failed++;
      }
    }
    if (!mounted) return;
    Navigator.of(context).pop(
      ImportedGarment.from(
        p,
        variant: _variant,
        images: bytes,
        failedImages: failed,
        storeColor: l10n.importStoreColor,
        size: l10n.importSize,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final preview = _preview;
    final failure = _failure;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.importTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            key: const Key('import-url'),
            controller: _url,
            enabled: !_busy,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: l10n.importUrl,
              helperText: l10n.importUrlHelp,
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => _read(),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              key: const Key('import-read'),
              onPressed: _busy ? null : _read,
              icon: const Icon(Icons.travel_explore),
              label: Text(l10n.importRead),
            ),
          ),
          const SizedBox(height: 16),
          if (_busy)
            const Center(child: CircularProgressIndicator())
          else if (failure != null)
            _failureView(l10n, failure)
          else if (preview != null)
            ..._previewView(context, l10n, preview),
        ],
      ),
    );
  }

  Widget _failureView(AppLocalizations l10n, ImportFailure failure) {
    final kind = switch (failure) {
      NotPublic() => 'notPublic',
      InvalidLink() => 'invalid',
      FetchFailed(reason: 'blocked') => 'blocked',
      FetchFailed(reason: 'not_found') => 'notFound',
      FetchFailed() => 'failed',
      NoMetadata() => 'noMetadata',
      RateLimited() => 'rateLimited',
      NotAllowed() => 'notAllowed',
      ImportUnavailable() => 'unavailable',
    };
    return Column(
      key: const Key('import-failure'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.importFailure(kind)),
        const SizedBox(height: 12),
        OutlinedButton(
          key: const Key('import-manual'),
          onPressed: () =>
              Navigator.of(context)
                  .pop(ImportedGarment.linkOnly(_url.text.trim())),
          child: Text(l10n.importManual),
        ),
      ],
    );
  }

  List<Widget> _previewView(
    BuildContext context,
    AppLocalizations l10n,
    ProductPreview p,
  ) {
    final theme = Theme.of(context);
    Widget field(String key, String label, String? value) => value == null
        ? const SizedBox.shrink()
        : ListTile(
            key: Key('import-field-$key'),
            contentPadding: EdgeInsets.zero,
            title: Text(value),
            subtitle: Text(
              p.sources[key] == null
                  ? label
                  : '$label · ${l10n.importSource(p.sources[key]!.name)}',
            ),
          );
    final variants = p.variants.length > 1 || p.confirm.contains('variant');
    return [
      Wrap(
        spacing: 8,
        children: [
          Chip(
            avatar: const Icon(Icons.storefront_outlined),
            label: Text(l10n.importSite(p.storeName, p.siteStatus.name)),
          ),
        ],
      ),
      field('name', l10n.garmentName, p.name),
      field('brand', l10n.garmentBrand, p.brand),
      field('material', l10n.garmentMaterial, p.material),
      field('color', l10n.importColor, p.color),
      if (p.description case final d?)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            d,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
        ),
      if (variants && p.variants.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text(l10n.importVariant, style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (i, v) in p.variants.indexed)
              ChoiceChip(
                key: Key('import-variant-$i'),
                label: Text(
                  [v.color, v.size].nonNulls.join(' · ').ifEmpty(v.sku ?? '—'),
                ),
                selected: identical(_variant, v),
                onSelected: (on) => _choose(on ? v : null),
              ),
          ],
        ),
      ],
      if (p.images.isNotEmpty && widget.maxImages > 0) ...[
        const SizedBox(height: 16),
        Text(l10n.importImages, style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (i, url) in p.images.indexed)
              _ImageChoice(
                key: Key('import-image-$i'),
                url: url,
                index: i,
                selected: _images.contains(url),
                onTap: () => setState(() {
                  if (!_images.remove(url) &&
                      _images.length < widget.maxImages) {
                    _images.add(url);
                  }
                }),
              ),
          ],
        ),
      ],
      const SizedBox(height: 16),
      Text(l10n.importConfirmLater, style: theme.textTheme.bodySmall),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton(
            key: const Key('import-use'),
            onPressed: _use,
            child: Text(l10n.importUse),
          ),
          OutlinedButton(
            key: const Key('import-manual'),
            onPressed: () =>
                Navigator.of(context).pop(ImportedGarment.linkOnly(p.url)),
            child: Text(l10n.importManual),
          ),
        ],
      ),
    ];
  }
}

/// Miniatura de uma imagem da loja que se pode escolher para copiar.
class _ImageChoice extends StatelessWidget {
  const _ImageChoice({
    required this.url,
    required this.index,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String url;
  final int index;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: l10n.photoOf(index + 1),
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 3 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    const Center(child: Icon(Icons.image_outlined)),
              ),
              if (selected)
                Align(
                  alignment: Alignment.topRight,
                  child: Icon(Icons.check_circle, color: scheme.primary),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}
