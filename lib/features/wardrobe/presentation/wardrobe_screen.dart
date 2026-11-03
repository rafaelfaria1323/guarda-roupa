import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../l10n/app_localizations.dart';
import '../../care/application/care_providers.dart';
import '../../account_sync/application/providers.dart';
import '../domain/availability.dart';
import '../domain/garment.dart';
import '../domain/garment_category.dart';
import '../domain/garment_attributes.dart';
import '../domain/garment_filter.dart';
import '../domain/wardrobe_repository.dart';
import 'garment_photo_view.dart';
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

  @override
  void dispose() {
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
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
        const SizedBox(height: 32, child: VerticalDivider()),
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
        const SizedBox(height: 32, child: VerticalDivider()),
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
    final stream = _streamFor(ref.watch(wardrobeRepositoryProvider));
    final searching = _filter.isActive;

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
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _search,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: l10n.wardrobeSearch,
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (value) =>
                        setState(() => _filter = _filter.copyWith(text: value)),
                  ),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: Text(l10n.wardrobeShowArchived),
                  selected: _filter.includeArchived,
                  onSelected: (value) => setState(
                    () => _filter = _filter.copyWith(includeArchived: value),
                  ),
                ),
              ],
            ),
          ),
          _filters(l10n),
          Expanded(
            child: stream == null
                ? const Center(child: CircularProgressIndicator())
                : StreamBuilder<List<Garment>>(
                    stream: stream,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return EmptyState(
                          icon: Icons.error_outline,
                          message: l10n.wardrobeLoadError,
                          hint: '${snapshot.error}',
                        );
                      }
                      final garments = snapshot.data;
                      if (garments == null) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (garments.isEmpty) {
                        return searching
                            ? Center(child: Text(l10n.wardrobeNoResults))
                            : EmptyState(
                                icon: Icons.checkroom_outlined,
                                message: l10n.wardrobeEmpty,
                                hint: l10n.wardrobeEmptyHint,
                              );
                      }
                      return ListView.separated(
                        padding: const EdgeInsets.only(bottom: 96),
                        itemCount: garments.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, i) =>
                            _GarmentTile(garment: garments[i]),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _GarmentTile extends ConsumerWidget {
  const _GarmentTile({required this.garment});

  final Garment garment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final washRecommended =
        ref.watch(laundryStatesProvider)?[garment.id]?.washRecommended ?? false;
    final category = l10n.categoryLabel(garment.category.id);
    final subtitle = [
      if (garment.name != null) category,
      ?garment.brand,
      if (garment.isArchived) l10n.garmentArchived,
      if (washRecommended) l10n.laundryRecommendedShort,
    ].join(' · ');
    return ListTile(
      leading: garment.photos.isEmpty
          ? const SizedBox.square(
              dimension: 48,
              child: Icon(Icons.checkroom_outlined),
            )
          : GarmentPhotoView(photo: garment.photos.first, size: 48),
      title: Text(garment.name ?? category),
      subtitle: subtitle.isEmpty ? null : Text(subtitle),
      trailing: AvailabilityChip(availability: garment.availability),
      onTap: () => context.push(AppRoutes.garment(garment.id)),
    );
  }
}
