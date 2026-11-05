import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/domain/result.dart';
import '../../../l10n/app_localizations.dart';
import '../domain/product_import.dart';

/// Ligar o atalho do iPhone que manda a página do Safari logo para o fio
/// (docs/guias/09-atalho-importar-iphone.md). A chave só aparece quando é
/// criada: a base guarda apenas o hash.
class ShortcutSetupScreen extends StatefulWidget {
  const ShortcutSetupScreen({required this.importer, super.key});

  final ProductImporter importer;

  @override
  State<ShortcutSetupScreen> createState() => _ShortcutSetupScreenState();
}

class _ShortcutSetupScreenState extends State<ShortcutSetupScreen> {
  ShortcutKeyStatus? _status;
  bool _failed = false;
  bool _busy = false;

  /// A chave acabada de criar; desaparece ao sair do ecrã.
  String? _key;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final result = await widget.importer.shortcutKeyStatus();
    if (!mounted) return;
    setState(() {
      switch (result) {
        case Ok(value: final s):
          _status = s;
          _failed = false;
        case Err():
          _failed = true;
      }
    });
  }

  Future<void> _create() async {
    final l10n = AppLocalizations.of(context);
    if (_status?.active ?? false) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.shortcutReplaceTitle),
          content: Text(l10n.shortcutReplaceBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              key: const Key('shortcut-replace-confirm'),
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.shortcutNewKey),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    setState(() => _busy = true);
    final result = await widget.importer.createShortcutKey();
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result case Ok(value: final key)) {
        _key = key;
        _status = ShortcutKeyStatus(active: true, createdAt: DateTime.now());
      } else {
        _failed = true;
      }
    });
  }

  Future<void> _revoke() async {
    setState(() => _busy = true);
    final result = await widget.importer.revokeShortcutKey();
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result is Ok) {
        _key = null;
        _status = const ShortcutKeyStatus(active: false);
      } else {
        _failed = true;
      }
    });
  }

  Future<void> _copy(String text) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    await Clipboard.setData(ClipboardData(text: text));
    messenger.showSnackBar(SnackBar(content: Text(l10n.shortcutCopied)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final status = _status;
    final key = _key;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.shortcutSetupTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(l10n.shortcutSetupIntro),
          const SizedBox(height: 16),
          if (_failed)
            Text(l10n.shortcutUnavailable, key: const Key('shortcut-failed'))
          else if (status == null || _busy)
            const Center(child: CircularProgressIndicator())
          else ...[
            Text(
              status.active
                  ? [
                      l10n.shortcutActive,
                      if (status.lastUsedAt case final d?)
                        l10n.shortcutLastUsed(d.toLocal())
                      else
                        l10n.shortcutNeverUsed,
                    ].join(' ')
                  : l10n.shortcutInactive,
              key: const Key('shortcut-status'),
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 12),
            if (key != null) ...[
              _Copyable(
                fieldKey: const Key('shortcut-key'),
                label: l10n.shortcutKeyLabel,
                value: key,
                onCopy: () => _copy(key),
              ),
              Text(l10n.shortcutKeyOnce, style: theme.textTheme.bodySmall),
              const SizedBox(height: 12),
              _Copyable(
                fieldKey: const Key('shortcut-endpoint'),
                label: l10n.shortcutEndpointLabel,
                value: widget.importer.shortcutEndpoint,
                onCopy: () => _copy(widget.importer.shortcutEndpoint),
              ),
              Text(l10n.shortcutHowTo, style: theme.textTheme.bodySmall),
              const SizedBox(height: 12),
            ],
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  key: const Key('shortcut-create'),
                  onPressed: _create,
                  icon: const Icon(Icons.key),
                  label: Text(
                    status.active ? l10n.shortcutNewKey : l10n.shortcutCreate,
                  ),
                ),
                if (status.active)
                  OutlinedButton.icon(
                    key: const Key('shortcut-revoke'),
                    onPressed: _revoke,
                    icon: const Icon(Icons.link_off),
                    label: Text(l10n.shortcutRevoke),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Um valor para copiar para o atalho.
class _Copyable extends StatelessWidget {
  const _Copyable({
    required this.fieldKey,
    required this.label,
    required this.value,
    required this.onCopy,
  });

  final Key fieldKey;
  final String label;
  final String value;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: SelectableText(value, key: fieldKey),
      trailing: IconButton(
        tooltip: l10n.shortcutCopy,
        icon: const Icon(Icons.copy),
        onPressed: onCopy,
      ),
    );
  }
}
