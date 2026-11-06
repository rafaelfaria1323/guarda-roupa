import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/domain/result.dart';
import '../../../l10n/app_localizations.dart';
import '../../care/application/care_providers.dart';
import '../../inspirations/application/inspiration_providers.dart';
import '../../photo_ai/presentation/photo_read_messages.dart';
import '../application/shopping_providers.dart';
import '../domain/shopping_advice.dart';
import '../domain/wardrobe_gaps.dart';

/// "Peças que faziam falta" no Resumo do armário
/// (docs/features/pecas-em-falta.md). As faltas calculam-se no aparelho;
/// com o Gemini ligado, "Sugerir peças e marcas" pede ideias concretas com
/// marcas, que abrem uma pesquisa. Nada se compra nem se adiciona sozinho.
class ShoppingSection extends ConsumerStatefulWidget {
  const ShoppingSection({super.key});

  @override
  ConsumerState<ShoppingSection> createState() => _ShoppingSectionState();
}

class _ShoppingSectionState extends ConsumerState<ShoppingSection> {
  final _budget = TextEditingController();
  var _budgetLoaded = false;
  var _loading = false;
  List<ShoppingIdea>? _ideas;
  String? _error;

  @override
  void dispose() {
    _budget.dispose();
    super.dispose();
  }

  int? get _budgetValue {
    final v = int.tryParse(_budget.text.trim());
    return v == null || v <= 0 ? null : v;
  }

  Future<void> _ask(List<WardrobeGap> gaps) async {
    final advisor = ref.read(activeShoppingAdvisorProvider);
    final garments = ref.read(allGarmentsProvider).value;
    if (advisor == null || garments == null) return;
    final l10n = AppLocalizations.of(context);
    final settings = ref.read(shoppingSettingsProvider).value;
    final budget = _budgetValue;
    await ref.read(shoppingSettingsProvider.notifier).setBudget(budget);
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await advisor.advise(
      shoppingBrief(
        garments,
        ref.read(inspirationsProvider).value ?? const [],
        gaps,
        budgetEur: budget,
        dismissed: settings?.dismissed ?? const {},
      ),
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      switch (result) {
        case Ok(:final value) when value.isNotEmpty:
          _ideas = value;
        case Ok():
          _error = l10n.geminiFailed;
        case Err(:final failure):
          _error = photoReadMessage(l10n, failure);
      }
    });
  }

  Future<void> _search(ShoppingIdea idea, ShoppingBrand brand) async {
    final uri = idea.searchUri(brand);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    if (await ref.read(openLinkProvider)(uri)) return;
    await Clipboard.setData(
      ClipboardData(text: '${brand.name} ${idea.search}'),
    );
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.shoppingCopied)));
  }

  void _dismiss(String key) {
    ref.read(shoppingSettingsProvider.notifier).dismiss(key);
    setState(() => _ideas = _ideas?.where((i) => i.key != key).toList());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final garments = ref.watch(allGarmentsProvider).value;
    final settings = ref.watch(shoppingSettingsProvider).value;
    if (garments == null || settings == null) return const SizedBox.shrink();
    if (!_budgetLoaded) {
      _budgetLoaded = true;
      _budget.text = settings.budgetEur?.toString() ?? '';
    }
    final gaps = findWardrobeGaps(
      garments,
      ref.watch(inspirationsProvider).value ?? const [],
      dismissed: settings.dismissed,
    );
    final advisor = ref.watch(activeShoppingAdvisorProvider);
    final small = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final ideas = _ideas;

    return Padding(
      key: const Key('shopping'),
      padding: const EdgeInsets.only(top: 16),
      child: Card.outlined(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.shoppingTitle, style: theme.textTheme.titleMedium),
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 4),
                child: Text(l10n.shoppingHint, style: small),
              ),
              if (gaps.isEmpty && ideas == null)
                Text(
                  l10n.shoppingNone,
                  key: const Key('shopping-none'),
                  style: theme.textTheme.bodyMedium,
                ),
              if (ideas == null)
                for (final gap in gaps)
                  ListTile(
                    key: Key('shopping-gap-${gap.key}'),
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.add_circle_outline),
                    title: Text(_gapTitle(l10n, gap)),
                    subtitle: gap.inspirations.isEmpty
                        ? null
                        : Text(
                            l10n.shoppingFromInspirations(
                              gap.inspirations.take(3).join(', '),
                            ),
                          ),
                    trailing: IconButton(
                      key: Key('shopping-dismiss-${gap.key}'),
                      tooltip: l10n.shoppingDismiss,
                      icon: const Icon(Icons.close),
                      onPressed: () => _dismiss(gap.key),
                    ),
                  ),
              if (ideas != null)
                for (final idea in ideas) ...[
                  const Divider(height: 24),
                  _IdeaTile(
                    idea: idea,
                    onSearch: (b) => _search(idea, b),
                    onDismiss: () => _dismiss(idea.key),
                    onHave: () => context.push(AppRoutes.newGarment),
                  ),
                ],
              if (advisor != null) ...[
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 140,
                      child: TextField(
                        key: const Key('shopping-budget'),
                        controller: _budget,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(4),
                        ],
                        decoration: InputDecoration(
                          labelText: l10n.shoppingBudget,
                          suffixText: '€',
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        key: const Key('shopping-ask'),
                        onPressed: _loading ? null : () => _ask(gaps),
                        icon: _loading
                            ? const SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.auto_awesome_outlined),
                        label: Text(
                          ideas == null
                              ? l10n.shoppingAsk
                              : l10n.shoppingAskAgain,
                        ),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(l10n.shoppingBudgetHint, style: small),
                ),
              ],
              if (_error case final error?)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    error,
                    key: const Key('shopping-error'),
                    style: small?.copyWith(color: theme.colorScheme.error),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _gapTitle(AppLocalizations l10n, WardrobeGap gap) {
    final group = gap.group == null ? '' : l10n.shoppingGroup(gap.group!.name);
    final color = gap.color == null
        ? ''
        : l10n.colorLabel(gap.color!.id).toLowerCase();
    return switch (gap.reason) {
      GapReason.missingGroup => l10n.shoppingMissingGroup(group),
      GapReason.onlyLight => l10n.shoppingOnlyLight(group, color),
      GapReason.onlyDark => l10n.shoppingOnlyDark(group, color),
      GapReason.inspirationColor => l10n.shoppingInspirationColor(color),
      GapReason.inspirationDressy => l10n.shoppingDressy(group),
      GapReason.fewBottoms => l10n.shoppingFewBottoms,
    };
  }
}

class _IdeaTile extends StatelessWidget {
  const _IdeaTile({
    required this.idea,
    required this.onSearch,
    required this.onDismiss,
    required this.onHave,
  });

  final ShoppingIdea idea;
  final void Function(ShoppingBrand) onSearch;
  final VoidCallback onDismiss;
  final VoidCallback onHave;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      key: Key('shopping-idea-${idea.key}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          idea.title,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        if (idea.why case final why?)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              why,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final b in idea.brands)
              ActionChip(
                key: Key('shopping-brand-${idea.key}-${b.name}'),
                avatar: const Icon(Icons.search, size: 18),
                label: Text('${b.name} · ${l10n.shoppingTier(b.tier.name)}'),
                onPressed: () => onSearch(b),
              ),
          ],
        ),
        Wrap(
          children: [
            TextButton(
              key: Key('shopping-have-${idea.key}'),
              onPressed: onHave,
              child: Text(l10n.shoppingHave),
            ),
            TextButton(
              key: Key('shopping-dismiss-${idea.key}'),
              onPressed: onDismiss,
              child: Text(l10n.shoppingDismiss),
            ),
          ],
        ),
      ],
    );
  }
}
