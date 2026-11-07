import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../core/domain/result.dart';
import '../../../l10n/app_localizations.dart';
import '../../account_sync/application/providers.dart';
import '../../care/application/care_providers.dart';
import '../../wear/application/wear_providers.dart';
import '../../wear/domain/wear_event.dart';
import '../../wear/presentation/today_wear_card.dart';
import '../domain/availability.dart';
import '../domain/garment.dart';
import '../domain/wardrobe_repository.dart';
import 'garment_cutout.dart';
import 'wardrobe_screen.dart' show garmentStatus;

/// A ficha da peça em modo de ver (visual fio v2): a peça, uma frase sobre
/// como tem sido usada, onde está, as últimas vezes e "Vou vestir hoje".
/// Mudar os dados é em "Editar".
class GarmentDetailScreen extends ConsumerStatefulWidget {
  const GarmentDetailScreen({required this.id, super.key});

  final GarmentId id;

  @override
  ConsumerState<GarmentDetailScreen> createState() =>
      _GarmentDetailScreenState();
}

class _GarmentDetailScreenState extends ConsumerState<GarmentDetailScreen> {
  WardrobeRepository? _repo;
  Stream<Garment?>? _garment;

  Stream<Garment?>? _streamFor(WardrobeRepository? repo) {
    if (repo != _repo) {
      _repo = repo;
      _garment = repo?.watchGarment(widget.id);
    }
    return _garment;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final repo = ref.watch(wardrobeRepositoryProvider);
    final stream = _streamFor(repo);
    if (repo == null || stream == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return StreamBuilder<Garment?>(
      stream: stream,
      builder: (context, snapshot) {
        if (!snapshot.hasData &&
            !snapshot.hasError &&
            snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final garment = snapshot.data;
        if (garment == null) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(child: Text(l10n.garmentNotFound)),
          );
        }
        return _Body(garment: garment, repo: repo);
      },
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.garment, required this.repo});

  final Garment garment;
  final WardrobeRepository repo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final category = l10n.categoryLabel(garment.category.id);
    final overline = [
      if (garment.name != null) category,
      ?garment.brand,
      if (garment.isArchived) l10n.garmentArchived,
    ].join(' · ');
    final material = garment.attributes.material;

    return Scaffold(
      appBar: AppBar(
        actions: [
          TextButton(
            key: const Key('garment-edit'),
            onPressed: () => context.push(AppRoutes.editGarment(garment.id)),
            child: Text(l10n.garmentEditAction),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          _Hero(garment: garment),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (overline.isNotEmpty)
                    Text(
                      overline.toUpperCase(),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colors.onSurfaceMuted,
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  const SizedBox(height: 2),
                  Text(
                    garment.name ?? category,
                    key: const Key('garment-detail-name'),
                    style: theme.textTheme.headlineMedium,
                  ),
                  if (garment.colors.isNotEmpty || material != null) ...[
                    const SizedBox(height: 12),
                    DecoratedBox(
                      // Só com material é que a faixa ganha fundo; com cores
                      // apenas, ficam os círculos soltos.
                      decoration: BoxDecoration(
                        color: material == null ? null : colors.surfaceMuted,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: material == null
                            ? EdgeInsets.zero
                            : const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                        child: Row(
                          children: [
                            for (final c in garment.colors.take(4))
                              Padding(
                                padding: const EdgeInsets.only(right: 4),
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: Color(0xFF000000 | c.rgb),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: colors.outline),
                                  ),
                                  child: const SizedBox.square(dimension: 18),
                                ),
                              ),
                            if (material != null) ...[
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  material,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _UseStats(garment: garment),
          const SizedBox(height: 22),
          Text(
            l10n.garmentWhere,
            style: theme.textTheme.titleLarge?.copyWith(fontSize: 18),
          ),
          const SizedBox(height: 8),
          Semantics(
            label: l10n.garmentWhere,
            container: true,
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final value in Availability.values)
                  ChoiceChip(
                    key: Key('garment-availability-${value.id}'),
                    showCheckmark: false,
                    label: Text(l10n.availabilityLabel(value.id)),
                    selected: garment.availability == value,
                    onSelected: (_) async {
                      final result = await repo.setAvailability(
                        garment.id,
                        value,
                      );
                      if (result is Err && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(l10n.garmentSaveFailed)),
                        );
                      }
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _LastTimes(garment: garment),
          const SizedBox(height: 28),
          if (!garment.isArchived)
            FilledButton.icon(
              key: const Key('garment-wear-today'),
              onPressed: () =>
                  context.push(AppRoutes.wearWith([garment.id.value])),
              icon: const Icon(Icons.done_all),
              label: Text(l10n.garmentWearToday),
            ),
        ],
      ),
    );
  }
}

/// A peça em grande num fundo de linho, com onde está por cima.
class _Hero extends ConsumerWidget {
  const _Hero({required this.garment});

  final Garment garment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final laundry = ref.watch(laundryStatesProvider)?[garment.id];
    final (label, dot) =
        garmentStatus(l10n, colors, garment, laundry) ??
        (l10n.availabilityLabel(garment.availability.id), colors.accent);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: AspectRatio(
          aspectRatio: 1,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surfaceMuted,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: LayoutBuilder(
                    builder: (context, box) => Center(
                      child: GarmentCutout(
                        garment: garment,
                        size: box.biggest.shortestSide * 0.66,
                        angle: -0.03,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 12,
                  top: 12,
                  child: DecoratedBox(
                    key: const Key('garment-detail-status'),
                    decoration: BoxDecoration(
                      color: colors.surface.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: dot,
                              shape: BoxShape.circle,
                            ),
                            child: const SizedBox.square(dimension: 7),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            label,
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Três números: quantas vezes foi usada, a última vez e quantos usos
/// faltam até pedir lavagem.
class _UseStats extends ConsumerWidget {
  const _UseStats({required this.garment});

  final Garment garment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final repo = ref.watch(wearRepositoryProvider);
    final laundry = ref.watch(laundryStatesProvider)?[garment.id];
    final today = todayFrom(ref.watch(clockProvider));
    if (repo == null) return const SizedBox.shrink();
    return StreamBuilder<List<WearEvent>>(
      stream: repo.watchGarmentHistory(garment.id),
      builder: (context, snapshot) {
        final events = snapshot.data;
        if (events == null) return const SizedBox.shrink();
        final (String care, bool due) = switch (laundry) {
          final s? when s.washRecommended => (l10n.garmentStatCareNow, true),
          final s? when s.threshold > 0 => (
            l10n.garmentStatCareUses(s.threshold - s.usesSinceCleaning),
            false,
          ),
          _ => ('—', false),
        };
        return IntrinsicHeight(
          key: const Key('garment-use-stats'),
          child: Row(
            spacing: 8,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Stat(
                key: const Key('garment-stat-worn'),
                label: l10n.garmentStatWorn,
                value: '${events.length}',
              ),
              _Stat(
                key: const Key('garment-stat-last'),
                label: l10n.garmentStatLast,
                value: events.isEmpty
                    ? l10n.garmentStatNever
                    : l10n.relativeDay(events.first.wornOn.daysUntil(today)),
              ),
              _Stat(
                key: const Key('garment-stat-care'),
                label: l10n.garmentStatCare,
                value: care,
                warn: due,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    this.warn = false,
    super.key,
  });

  final String label;
  final String value;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.onSurfaceMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontSize: 19,
                  color: warn ? colors.onCareSoft : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// As últimas utilizações como um fio: a data e com que peças foi.
class _LastTimes extends ConsumerWidget {
  const _LastTimes({required this.garment});

  static const _shown = 5;

  final Garment garment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final repo = ref.watch(wearRepositoryProvider);
    final names = {
      for (final g in ref.watch(allGarmentsProvider).value ?? <Garment>[])
        g.id: g,
    };
    if (repo == null) return const SizedBox.shrink();
    final date = DateFormat(
      'd MMM',
      Localizations.localeOf(context).toLanguageTag(),
    );
    return StreamBuilder<List<WearEvent>>(
      stream: repo.watchGarmentHistory(garment.id),
      builder: (context, snapshot) {
        final events = snapshot.data ?? const <WearEvent>[];
        if (events.isEmpty) return const SizedBox.shrink();
        return Column(
          key: const Key('garment-last-times'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.garmentLastTimes,
              style: theme.textTheme.titleLarge?.copyWith(fontSize: 18),
            ),
            const SizedBox(height: 8),
            Container(
              margin: const EdgeInsets.only(left: 6),
              padding: const EdgeInsets.only(left: 16),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: AppColors.of(context).accent,
                    width: 2,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final e in events.take(_shown))
                    _TimeRow(
                      when: date
                          .format(e.wornOn.toLocalDateTime())
                          .replaceAll('.', ''),
                      what: [
                        for (final id in e.garmentIds)
                          if (id != garment.id) garmentLabel(l10n, names[id]),
                      ],
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TimeRow extends StatelessWidget {
  const _TimeRow({required this.when, required this.what});

  final String when;
  final List<String> what;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: -23,
            top: 4,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: AppColors.of(context).background,
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.of(context).accent,
                  width: 2,
                ),
              ),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 64,
                child: Text(
                  when,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  what.isEmpty
                      ? l10n.garmentWornAlone
                      : l10n.garmentWornWith(what.join(', ')),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
