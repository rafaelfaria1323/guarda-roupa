import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../l10n/app_localizations.dart';
import '../../account_sync/application/providers.dart';
import '../domain/garment.dart';
import '../domain/garment_filter.dart';
import '../domain/wardrobe_repository.dart';
import 'labels.dart';

class WardrobeScreen extends ConsumerStatefulWidget {
  const WardrobeScreen({super.key});

  @override
  ConsumerState<WardrobeScreen> createState() => _WardrobeScreenState();
}

class _WardrobeScreenState extends ConsumerState<WardrobeScreen> {
  String _text = '';
  bool _showArchived = false;

  WardrobeRepository? _repo;
  GarmentFilter? _filter;
  Stream<List<Garment>>? _garments;

  /// Recria o stream só quando o repositório ou o filtro mudam, para não
  /// reiniciar a subscrição a cada rebuild.
  Stream<List<Garment>>? _streamFor(WardrobeRepository? repo) {
    final filter = GarmentFilter(text: _text, includeArchived: _showArchived);
    if (repo != _repo ||
        _filter?.text != filter.text ||
        _filter?.includeArchived != filter.includeArchived) {
      _repo = repo;
      _filter = filter;
      _garments = repo?.watchGarments(filter);
    }
    return _garments;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final stream = _streamFor(ref.watch(wardrobeRepositoryProvider));
    final searching = _text.trim().isNotEmpty || _showArchived;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
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
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: l10n.wardrobeSearch,
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (value) => setState(() => _text = value),
                  ),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: Text(l10n.wardrobeShowArchived),
                  selected: _showArchived,
                  onSelected: (value) => setState(() => _showArchived = value),
                ),
              ],
            ),
          ),
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

class _GarmentTile extends StatelessWidget {
  const _GarmentTile({required this.garment});

  final Garment garment;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final category = l10n.categoryLabel(garment.category.id);
    final subtitle = [
      if (garment.name != null) category,
      ?garment.brand,
      if (garment.isArchived) l10n.garmentArchived,
    ].join(' · ');
    return ListTile(
      leading: const Icon(Icons.checkroom_outlined),
      title: Text(garment.name ?? category),
      subtitle: subtitle.isEmpty ? null : Text(subtitle),
      trailing: AvailabilityChip(availability: garment.availability),
      onTap: () => context.push(AppRoutes.garment(garment.id)),
    );
  }
}
