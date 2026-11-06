import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../core/domain/result.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../l10n/app_localizations.dart';
import '../../care/application/care_providers.dart';
import '../../care/domain/laundry_basket.dart';
import '../../care/domain/laundry_policy.dart';
import '../../account_sync/application/providers.dart';
import '../../import/application/import_providers.dart';
import '../../import/application/shortcut_inbox.dart';
import '../../import/domain/product_import.dart';
import '../application/garment_copies.dart';
import '../application/photo_providers.dart';
import '../domain/availability.dart';
import '../domain/garment.dart';
import '../domain/garment_category.dart';
import '../domain/garment_attributes.dart';
import '../domain/garment_filter.dart';
import '../domain/garment_twins.dart';
import '../domain/wardrobe_repository.dart';
import 'garment_cutout.dart';
import 'labels.dart';

class WardrobeScreen extends ConsumerStatefulWidget {
  const WardrobeScreen({super.key});

  @override
  ConsumerState<WardrobeScreen> createState() => _WardrobeScreenState();
}

class _WardrobeScreenState extends ConsumerState<WardrobeScreen> {
  final _search = TextEditingController();
  var _filter = const GarmentFilter();

  WardrobeRepository? _repo;
  GarmentFilter? _streamFilter;
  Stream<List<Garment>>? _garments;

  /// Peças que o atalho do iPhone mandou e esperam na caixa.
  int _inbox = 0;

  /// Ao voltar à app (depois de mandar peças pelo atalho no Safari).
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: () => unawaited(_loadInbox()));
    unawaited(_loadInbox());
  }

  /// A passar as peças do atalho para o Armário (uma vez de cada vez).
  bool _addingInbox = false;

  /// As peças que o atalho mandou entram sozinhas no Armário, com o que a
  /// loja diz; o resto muda-se depois no cartão.
  Future<void> _loadInbox() async {
    final importer = ref.read(productImporterProvider);
    final repo = ref.read(wardrobeRepositoryProvider);
    if (importer == null || repo == null || _addingInbox) return;
    final process = ref.read(photoProcessorProvider);
    _addingInbox = true;
    try {
      final result = await importer.inbox();
      if (!mounted) return;
      final items = result is Ok<List<InboxItem>, ImportFailure>
          ? result.value
          : const <InboxItem>[];
      if (items.isEmpty) return;
      // Só depois do primeiro await: o initState já acabou.
      final l10n = AppLocalizations.of(context);
      final messenger = ScaffoldMessenger.of(context);
      setState(() => _inbox = items.length);
      final created = await addInboxToWardrobe(
        items: items,
        importer: importer,
        repo: repo,
        processPhoto: process,
        storeColor: l10n.importStoreColor,
        size: l10n.importSize,
      );
      if (created > 0) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.wardrobeInboxAdded(created))),
        );
      }
    } finally {
      _addingInbox = false;
      if (mounted) setState(() => _inbox = 0);
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _search.dispose();
    super.dispose();
  }

  /// Recria o stream só quando o repositório ou o filtro mudam, para não
  /// reiniciar a subscrição a cada rebuild.
  Stream<List<Garment>>? _streamFor(WardrobeRepository? repo) {
    if (repo != _repo || _streamFilter != _filter) {
      _repo = repo;
      _streamFilter = _filter;
      _garments = repo?.watchGarments(_filter);
    }
    return _garments;
  }

  static Set<T> _toggled<T>(Set<T> set, T value, bool on) =>
      on ? {...set, value} : ({...set}..remove(value));

  Widget _filters(AppLocalizations l10n) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
    child: Row(
      spacing: 8,
      children: [
        for (final group in CategoryGroup.values)
          FilterChip(
            key: Key('filter-group-${group.name}'),
            label: Text(l10n.categoryGroupLabel(group.name)),
            selected: _filter.groups.contains(group),
            onSelected: (on) => setState(
              () => _filter = _filter.copyWith(
                groups: _toggled(_filter.groups, group, on),
              ),
            ),
          ),
        const SizedBox(height: 32, child: VerticalDivider(width: 8)),
        for (final value in Availability.values)
          FilterChip(
            key: Key('filter-availability-${value.id}'),
            avatar: Icon(availabilityIcon(value), size: 18),
            label: Text(l10n.availabilityLabel(value.id)),
            selected: _filter.availability.contains(value),
            onSelected: (on) => setState(
              () => _filter = _filter.copyWith(
                availability: _toggled(_filter.availability, value, on),
              ),
            ),
          ),
        const SizedBox(height: 32, child: VerticalDivider(width: 8)),
        for (final value in Occasion.values)
          FilterChip(
            key: Key('filter-occasion-${value.id}'),
            label: Text(l10n.occasionLabel(value.id)),
            selected: _filter.occasions.contains(value),
            onSelected: (on) => setState(
              () => _filter = _filter.copyWith(
                occasions: _toggled(_filter.occasions, value, on),
              ),
            ),
          ),
        const SizedBox(height: 32, child: VerticalDivider(width: 8)),
        FilterChip(
          key: const Key('filter-archived'),
          label: Text(l10n.wardrobeShowArchived),
          selected: _filter.includeArchived,
          onSelected: (value) => setState(
            () => _filter = _filter.copyWith(includeArchived: value),
          ),
        ),
        if (_filter.isActive)
          TextButton.icon(
            onPressed: () => setState(() {
              _search.clear();
              _filter = const GarmentFilter();
            }),
            icon: const Icon(Icons.filter_alt_off_outlined),
            label: Text(l10n.wardrobeClearFilters),
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final stream = _streamFor(ref.watch(wardrobeRepositoryProvider));
    final searching = _filter.isActive;
    // A sessão pode chegar depois do primeiro ecrã.
    ref.listen(currentUserProvider, (_, _) => unawaited(_loadInbox()));

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        // Os separadores ficam montados lado a lado: sem Hero partilhado.
        heroTag: null,
        onPressed: stream == null
            ? null
            : () => context.push(AppRoutes.newGarment),
        icon: const Icon(Icons.add),
        label: Text(l10n.wardrobeAdd),
      ),
      body: stream == null
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<List<Garment>>(
              stream: stream,
              builder: (context, snapshot) {
                final garments = snapshot.data;
                final Widget content;
                if (snapshot.hasError) {
                  content = EmptyState(
                    icon: Icons.error_outline,
                    message: l10n.wardrobeLoadError,
                    hint: '${snapshot.error}',
                  );
                } else if (garments == null) {
                  content = const Center(child: CircularProgressIndicator());
                } else if (garments.isEmpty) {
                  content = searching
                      ? Center(child: Text(l10n.wardrobeNoResults))
                      : EmptyState(
                          icon: Icons.checkroom_outlined,
                          message: l10n.wardrobeEmpty,
                          hint: l10n.wardrobeEmptyHint,
                        );
                } else if (searching) {
                  content = _Grid(garments: garments);
                } else {
                  content = _Shelves(
                    garments: garments,
                    onSeeAll: (group) => setState(
                      () => _filter = _filter.copyWith(groups: {group}),
                    ),
                  );
                }
                final inCare = (garments ?? const <Garment>[])
                    .where(
                      (g) =>
                          g.availability == Availability.washing ||
                          g.availability == Availability.drying,
                    )
                    .length;
                // O cesto conta todas as peças, não só as do filtro.
                final basket = LaundryBasket.of(
                  ref.watch(allGarmentsProvider).value ?? const [],
                ).count;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Sempre no mesmo lugar da árvore, para o campo de
                    // pesquisa não perder o foco ao começar a escrever.
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                      child: Visibility(
                        visible: garments != null && !searching,
                        maintainSize: true,
                        maintainAnimation: true,
                        maintainState: true,
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                [
                                  l10n.wardrobeCount(garments?.length ?? 0),
                                  if (inCare > 0) l10n.wardrobeInCare(inCare),
                                ].join(' · '),
                                key: const Key('wardrobe-summary'),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            if ((garments ?? const []).isNotEmpty)
                              IconButton(
                                key: const Key('wardrobe-insights'),
                                tooltip: l10n.insightsTitle,
                                icon: const Icon(Icons.insights_outlined),
                                onPressed: () =>
                                    context.push(AppRoutes.wardrobeInsights),
                              ),
                            if (basket > 0)
                              ActionChip(
                                key: const Key('wardrobe-basket'),
                                avatar: const Icon(
                                  Icons.local_laundry_service_outlined,
                                ),
                                label: Text(l10n.wardrobeBasket(basket)),
                                onPressed: () =>
                                    context.push(AppRoutes.laundryBasket),
                              ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
                      child: TextField(
                        controller: _search,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search),
                          hintText: l10n.wardrobeSearch,
                          isDense: true,
                          border: const OutlineInputBorder(
                            borderRadius: BorderRadius.all(
                              Radius.circular(999),
                            ),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onChanged: (value) => setState(
                          () => _filter = _filter.copyWith(text: value),
                        ),
                      ),
                    ),
                    if (_inbox > 0)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 4, 24, 4),
                        child: Card.outlined(
                          margin: EdgeInsets.zero,
                          child: ListTile(
                            key: const Key('wardrobe-inbox'),
                            leading: const SizedBox.square(
                              dimension: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            title: Text(l10n.wardrobeInbox(_inbox)),
                          ),
                        ),
                      ),
                    _filters(l10n),
                    Expanded(child: content),
                  ],
                );
              },
            ),
    );
  }
}

/// Prateleiras por tipo (visual fio v2): o título, quantas há e as peças
/// numa linha que desliza.
class _Shelves extends StatelessWidget {
  const _Shelves({required this.garments, required this.onSeeAll});

  final List<Garment> garments;
  final ValueChanged<CategoryGroup> onSeeAll;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final byGroup = <CategoryGroup, List<Garment>>{};
    for (final g in garments) {
      (byGroup[g.category.group] ??= []).add(g);
    }
    final groups = [
      for (final group in CategoryGroup.values)
        if (byGroup[group] case final list?) (group, list),
    ];
    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 96),
      children: [
        for (final (group, list) in groups)
          Padding(
            key: Key('shelf-${group.name}'),
            padding: const EdgeInsets.only(bottom: 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 12, 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        l10n.categoryGroupLabel(group.name),
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontSize: 19,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${list.length}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const Spacer(),
                      if (list.length > 3)
                        TextButton(
                          key: Key('shelf-${group.name}-all'),
                          onPressed: () => onSeeAll(group),
                          child: Text(
                            l10n.wardrobeSeeAll,
                            semanticsLabel: l10n.wardrobeSeeAllGroup(
                              l10n.categoryGroupLabel(group.name),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                // Não preguiçoso: um armário pessoal tem dezenas de peças
                // por tipo, não milhares.
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  clipBehavior: Clip.none,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final units in GarmentTwins.group(list))
                        _GarmentTile(units: units),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Resultados de uma pesquisa ou filtro: as mesmas peças, em grelha.
class _Grid extends StatelessWidget {
  const _Grid({required this.garments});

  final List<Garment> garments;

  @override
  Widget build(BuildContext context) {
    final groups = GarmentTwins.group(garments);
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 96),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 124,
        mainAxisExtent: 172,
      ),
      itemCount: groups.length,
      itemBuilder: (context, i) => _GarmentTile(units: groups[i]),
    );
  }
}

/// Uma peça, ou várias iguais juntas ("×3"): o estado diz quantas estão
/// disponíveis e tocar mostra cada unidade.
class _GarmentTile extends ConsumerWidget {
  const _GarmentTile({required this.units});

  final List<Garment> units;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final garment = units.first;
    final laundry = ref.watch(laundryStatesProvider);
    final category = l10n.categoryLabel(garment.category.id);
    final twins = units.length > 1;
    final (String, Color)? status;
    if (twins) {
      final available = units.where((g) => g.isCandidate).length;
      status = garment.isArchived
          ? (l10n.garmentArchived, AppColors.onSurfaceMuted)
          : available < units.length
          ? (
              l10n.wardrobeTwinsAvailable(available, units.length),
              AppColors.care,
            )
          : null;
    } else {
      status = garmentStatus(l10n, garment, laundry?[garment.id]);
    }
    return SizedBox(
      key: twins
          ? Key('garment-twins-${garment.id.value}')
          : Key('garment-tile-${garment.id.value}'),
      width: 112,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => twins
            ? showModalBottomSheet<void>(
                context: context,
                useRootNavigator: true,
                showDragHandle: true,
                isScrollControlled: true,
                builder: (_) => _TwinsSheet(ids: [for (final g in units) g.id]),
              )
            : context.push(AppRoutes.garment(garment.id)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
          child: Column(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  GarmentCutout(garment: garment, size: 88),
                  if (twins)
                    Positioned(
                      right: -4,
                      top: -4,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          child: Text(
                            '×${units.length}',
                            key: const Key('garment-twins-count'),
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                garment.name ?? category,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontSize: 13,
                  height: 1.2,
                ),
              ),
              if (status case (final label, final color)) ...[
                const SizedBox(height: 2),
                _StatusLine(label: label, color: color),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Só o que foge ao normal: "disponível" não se escreve.
(String, Color)? garmentStatus(
  AppLocalizations l10n,
  Garment garment,
  LaundryState? laundry,
) {
  final availability = garment.availability;
  final inCare = !availability.isAvailable;
  return garment.isArchived
      ? (l10n.garmentArchived, AppColors.onSurfaceMuted)
      : availability != Availability.available
      ? (
          l10n.availabilityLabel(availability.id),
          inCare ? AppColors.care : AppColors.onSurfaceMuted,
        )
      : (laundry?.washRecommended ?? false)
      ? (l10n.laundryRecommendedShort, AppColors.care)
      : null;
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: const SizedBox.square(dimension: 6),
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color == AppColors.care
                  ? AppColors.onCareSoft
                  : AppColors.onSurfaceMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

/// As unidades de um grupo de peças iguais, cada uma com o seu estado e
/// a última vez que foi vestida. Daqui abre-se cada uma ou junta-se mais
/// uma igual (com as mesmas fotos).
class _TwinsSheet extends ConsumerStatefulWidget {
  const _TwinsSheet({required this.ids});

  final List<GarmentId> ids;

  @override
  ConsumerState<_TwinsSheet> createState() => _TwinsSheetState();
}

class _TwinsSheetState extends ConsumerState<_TwinsSheet> {
  bool _adding = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final repo = ref.watch(wardrobeRepositoryProvider);
    final all = ref.watch(allGarmentsProvider).value ?? const <Garment>[];
    final laundry = ref.watch(laundryStatesProvider);
    final lastWorn = ref.watch(lastWornProvider);
    final byId = {for (final g in all) g.id: g};
    // Inclui as que se juntaram entretanto (mesmo grupo).
    final first = byId[widget.ids.first];
    final key = first == null ? null : GarmentTwins.key(first);
    final units = [
      for (final g in all)
        if (widget.ids.contains(g.id) ||
            (key != null && GarmentTwins.key(g) == key))
          g,
    ];
    if (units.isEmpty) return const SizedBox(height: 120);
    final label =
        units.first.name ?? l10n.categoryLabel(units.first.category.id);
    return SafeArea(
      child: ListView(
        key: const Key('garment-twins-sheet'),
        shrinkWrap: true,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
            child: Text(
              l10n.wardrobeTwinsTitle(label, units.length),
              style: theme.textTheme.titleLarge,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              l10n.wardrobeTwinsHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          for (final (i, g) in units.indexed)
            ListTile(
              key: Key('garment-twin-${g.id.value}'),
              leading: GarmentCutout(garment: g, size: 40),
              title: Text(l10n.wardrobeTwinUnit(i + 1)),
              subtitle: Text(
                [
                  garmentStatus(l10n, g, laundry?[g.id])?.$1 ??
                      l10n.availabilityLabel(Availability.available.id),
                  switch (lastWorn[g.id]) {
                    final day? => l10n.wardrobeTwinLastWorn(
                      day.toLocalDateTime(),
                    ),
                    null => l10n.wardrobeTwinNeverWorn,
                  },
                ].join(' · '),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.pop(context);
                unawaited(context.push(AppRoutes.garment(g.id)));
              },
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: OutlinedButton.icon(
              key: const Key('garment-twins-add'),
              onPressed: repo == null || _adding
                  ? null
                  : () async {
                      setState(() => _adding = true);
                      await duplicateWithPhotos(ref, repo, units.last);
                      if (mounted) setState(() => _adding = false);
                    },
              icon: const Icon(Icons.add),
              label: Text(l10n.wardrobeTwinsAdd),
            ),
          ),
        ],
      ),
    );
  }
}
