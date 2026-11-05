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
    final muted = theme.textTheme.bodyLarge?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final category = l10n.categoryLabel(garment.category.id);
    final subtitle = [
      if (garment.name != null) category,
      ?garment.brand,
      if (garment.isArchived) l10n.garmentArchived,
    ].join(' · ');

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
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        children: [
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: GarmentCutout(garment: garment, size: 210, angle: -0.05),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            garment.name ?? category,
            key: const Key('garment-detail-name'),
            style: theme.textTheme.headlineLarge,
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(subtitle, style: muted),
          ],
          const SizedBox(height: 14),
          _UseSentence(garment: garment),
          const SizedBox(height: 18),
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
            FilledButton(
              key: const Key('garment-wear-today'),
              onPressed: () =>
                  context.push(AppRoutes.wearWith([garment.id.value])),
              child: Text(l10n.garmentWearToday),
            ),
        ],
      ),
    );
  }
}

/// "Usada 12 vezes, a última há 6 dias. Mais 3 usos e pede lavagem."
class _UseSentence extends ConsumerWidget {
  const _UseSentence({required this.garment});

  final Garment garment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final repo = ref.watch(wearRepositoryProvider);
    final laundry = ref.watch(laundryStatesProvider)?[garment.id];
    final today = todayFrom(ref.watch(clockProvider));
    if (repo == null) return const SizedBox.shrink();
    return StreamBuilder<List<WearEvent>>(
      stream: repo.watchGarmentHistory(garment.id),
      builder: (context, snapshot) {
        final events = snapshot.data;
        if (events == null) return const SizedBox.shrink();
        final last = events.isEmpty
            ? ''
            : l10n.relativeDay(events.first.wornOn.daysUntil(today));
        final String? care = switch (laundry) {
          null => null,
          final s when s.washRecommended => l10n.laundryDueNow,
          final s when s.threshold > 0 => l10n.laundryUsesLeft(
            s.threshold - s.usesSinceCleaning,
          ),
          _ => null,
        };
        return Text.rich(
          TextSpan(
            children: [
              TextSpan(text: l10n.garmentUseSentence(events.length, last)),
              if (care != null)
                TextSpan(
                  text: ' $care',
                  style: laundry!.washRecommended
                      ? const TextStyle(
                          color: AppColors.onCareSoft,
                          fontWeight: FontWeight.w600,
                        )
                      : null,
                ),
            ],
          ),
          key: const Key('garment-use-sentence'),
          style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
        );
      },
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
              decoration: const BoxDecoration(
                border: Border(
                  left: BorderSide(color: AppColors.accent, width: 2),
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
                color: AppColors.background,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.accent, width: 2),
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
