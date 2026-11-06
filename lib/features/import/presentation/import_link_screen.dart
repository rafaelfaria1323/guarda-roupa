import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/domain/result.dart';
import '../../../l10n/app_localizations.dart';
import '../domain/product_import.dart';
import 'shortcut_setup_screen.dart';

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

  /// O que estava copiado não veio do atalho do iPhone.
  bool _notShared = false;
  ProductPreview? _preview;
  ImportVariant? _variant;
  final _images = <String>{};

  /// Peças mandadas pelo atalho; `null` enquanto carrega ou se falhou.
  List<InboxItem>? _inbox;

  /// A peça da caixa que está na pré-visualização: sai da caixa ao usar.
  String? _inboxId;

  /// Ao voltar à app depois de mandar peças pelo atalho no Safari.
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: () => unawaited(_loadInbox()));
    unawaited(_loadInbox());
  }

  Future<void> _loadInbox() async {
    final result = await widget.importer.inbox();
    if (!mounted) return;
    setState(
      () => _inbox = result is Ok<List<InboxItem>, ImportFailure>
          ? result.value
          : null,
    );
  }

  void _open(InboxItem item) {
    final p = item.preview;
    _url.text = p.url;
    setState(() {
      _inboxId = item.id;
      _notShared = false;
      _failure = null;
      _preview = p;
      _variant = null;
      _images.clear();
      if (p.images.isNotEmpty && widget.maxImages > 0) {
        _images.add(p.images.first);
      }
    });
  }

  Future<void> _discard(InboxItem item) async {
    setState(() {
      _inbox = [...?_inbox]..remove(item);
      if (_inboxId == item.id) {
        _inboxId = null;
        _preview = null;
      }
    });
    await widget.importer.discardInbox(item.id);
  }

  /// Sai do ecrã com a peça; a da caixa já não fica à espera.
  void _finish(ImportedGarment garment) {
    if (_inboxId case final id?) unawaited(widget.importer.discardInbox(id));
    Navigator.of(context).pop(garment);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _url.dispose();
    super.dispose();
  }

  /// Lê o texto copiado pelo atalho "Importar para o fio".
  Future<void> _pasteShared() async {
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
    if (!mounted) return;
    final page = SharedPage.parse(text);
    if (page == null) {
      setState(() {
        _notShared = true;
        _failure = null;
        _preview = null;
      });
      return;
    }
    await _read(shared: page);
  }

  Future<void> _read({SharedPage? shared}) async {
    // Colar no campo o texto do atalho também serve.
    final page = shared ?? SharedPage.parse(_url.text);
    if (page != null) _url.text = page.url;
    final url = _url.text.trim();
    if (url.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _inboxId = null;
      _notShared = false;
      _failure = null;
      _preview = null;
      _variant = null;
      _images.clear();
    });
    final result = page != null
        ? await widget.importer.previewShared(page)
        : await widget.importer.preview(url);
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
    _finish(
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
      appBar: AppBar(
        title: Text(l10n.importTitle),
        actions: [
          IconButton(
            key: const Key('import-inbox-refresh'),
            tooltip: l10n.importInboxRefresh,
            icon: const Icon(Icons.refresh),
            onPressed: _busy ? null : () => unawaited(_loadInbox()),
          ),
          IconButton(
            key: const Key('import-shortcut-setup'),
            tooltip: l10n.shortcutSetupTitle,
            icon: const Icon(Icons.phone_iphone),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      ShortcutSetupScreen(importer: widget.importer),
                ),
              );
              await _loadInbox();
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_inbox case final inbox? when inbox.isNotEmpty) ...[
            Text(
              l10n.importInboxTitle(inbox.length),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            for (final item in inbox)
              ListTile(
                key: Key('import-inbox-${item.id}'),
                contentPadding: EdgeInsets.zero,
                selected: _inboxId == item.id,
                leading: const Icon(Icons.phone_iphone),
                title: Text(
                  item.preview.name ?? item.preview.storeName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(item.preview.storeName),
                onTap: _busy ? null : () => _open(item),
                trailing: IconButton(
                  key: Key('import-inbox-discard-${item.id}'),
                  tooltip: l10n.importInboxDiscard,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _busy ? null : () => _discard(item),
                ),
              ),
            const Divider(height: 24),
          ],
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
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                key: const Key('import-read'),
                onPressed: _busy ? null : _read,
                icon: const Icon(Icons.travel_explore),
                label: Text(l10n.importRead),
              ),
              OutlinedButton.icon(
                key: const Key('import-paste-shared'),
                onPressed: _busy ? null : _pasteShared,
                icon: const Icon(Icons.content_paste),
                label: Text(l10n.importPasteShared),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_busy)
            const Center(child: CircularProgressIndicator())
          else if (_notShared)
            Text(l10n.importSharedInvalid, key: const Key('import-not-shared'))
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
        if (kind == 'blocked') ...[
          const SizedBox(height: 8),
          Text(
            l10n.importBlockedShortcut,
            key: const Key('import-blocked-shortcut'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 12),
        OutlinedButton(
          key: const Key('import-manual'),
          onPressed: () => _finish(ImportedGarment.linkOnly(_url.text.trim())),
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
            label: Text(
              p.viaShortcut
                  ? l10n.importSiteShared(p.storeName)
                  : l10n.importSite(p.storeName, p.siteStatus.name),
            ),
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
            onPressed: () => _finish(ImportedGarment.linkOnly(p.url)),
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
