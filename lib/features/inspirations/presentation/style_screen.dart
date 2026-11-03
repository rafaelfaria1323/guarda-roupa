import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../l10n/app_localizations.dart';
import '../../wardrobe/domain/reference_color.dart';
import '../../wardrobe/presentation/colors_editor.dart';
import '../../wardrobe/presentation/garment_photo_view.dart';
import '../application/inspiration_providers.dart';
import '../domain/inspiration.dart';
import '../domain/style_preference.dart';
import 'inspiration_messages.dart';
import 'preference_messages.dart';

/// Separador Estilo: inspirações guardadas e preferências explícitas.
/// Nenhuma das duas é posse: não são peças.
class StyleScreen extends ConsumerStatefulWidget {
  const StyleScreen({super.key});

  @override
  ConsumerState<StyleScreen> createState() => _StyleScreenState();
}

enum _StyleView { inspirations, preferences }

class _StyleScreenState extends ConsumerState<StyleScreen> {
  _StyleView _view = _StyleView.inspirations;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final inspirations = _view == _StyleView.inspirations;
    final ready = inspirations
        ? ref.watch(inspirationRepositoryProvider) != null
        : ref.watch(preferenceRepositoryProvider) != null;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        // Os separadores ficam montados lado a lado: sem Hero partilhado.
        heroTag: null,
        key: Key(inspirations ? 'inspiration-add' : 'preference-add'),
        onPressed: ready
            ? () => context.push(
                inspirations
                    ? AppRoutes.newInspiration
                    : AppRoutes.newPreference,
              )
            : null,
        icon: const Icon(Icons.add),
        label: Text(inspirations ? l10n.inspirationAdd : l10n.preferenceAdd),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<_StyleView>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: _StyleView.inspirations,
                    label: Text(
                      l10n.styleInspirations,
                      key: const Key('style-segment-inspirations'),
                    ),
                  ),
                  ButtonSegment(
                    value: _StyleView.preferences,
                    label: Text(
                      l10n.stylePreferences,
                      key: const Key('style-segment-preferences'),
                    ),
                  ),
                ],
                selected: {_view},
                onSelectionChanged: (s) => setState(() => _view = s.single),
              ),
            ),
          ),
          Expanded(
            child: inspirations
                ? const _InspirationList()
                : const _PreferenceList(),
          ),
        ],
      ),
    );
  }
}

class _InspirationList extends ConsumerWidget {
  const _InspirationList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return switch (ref.watch(inspirationsProvider)) {
      AsyncData(value: final list) when list.isEmpty => EmptyState(
        icon: Icons.auto_awesome_outlined,
        message: l10n.styleEmpty,
        hint: l10n.styleEmptyHint,
      ),
      AsyncData(value: final list) => ListView(
        padding: const EdgeInsets.only(bottom: 88),
        children: [for (final i in list) _InspirationTile(inspiration: i)],
      ),
      AsyncError() => Center(child: Text(l10n.wardrobeLoadError)),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}

class _PreferenceList extends ConsumerWidget {
  const _PreferenceList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final origins = {
      for (final i in ref.watch(inspirationsProvider).value ?? <Inspiration>[])
        i.id: i,
    };
    return switch (ref.watch(preferencesProvider)) {
      AsyncData(value: final list) when list.isEmpty => EmptyState(
        icon: Icons.thumbs_up_down_outlined,
        message: l10n.preferencesEmpty,
        hint: l10n.preferencesEmptyHint,
      ),
      AsyncData(value: final list) => ListView(
        padding: const EdgeInsets.only(bottom: 88),
        children: [
          for (final p in list)
            _PreferenceTile(preference: p, origin: origins[p.inspirationId]),
        ],
      ),
      AsyncError() => Center(child: Text(l10n.wardrobeLoadError)),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}

class _PreferenceTile extends StatelessWidget {
  const _PreferenceTile({required this.preference, this.origin});

  final StylePreference preference;
  final Inspiration? origin;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = preference;
    final like = p.stance == PreferenceStance.like;
    final originName = origin == null
        ? null
        : origin!.title ?? origin!.sourceHost;
    return ListTile(
      key: Key('preference-${p.id}'),
      leading: SizedBox.square(
        dimension: 48,
        child: Center(
          child: p.subject == PreferenceSubject.color
              ? ColorDot(
                  rgb: int.parse(p.value),
                  label: preferenceValueLabel(l10n, p.subject, p.value),
                )
              : Icon(
                  like ? Icons.thumb_up_outlined : Icons.thumb_down_outlined,
                ),
        ),
      ),
      title: Text(preferenceTitle(l10n, p)),
      subtitle: Text(
        [
          preferenceContext(l10n, p),
          if (originName != null) l10n.preferenceFromInspiration(originName),
        ].join('\n'),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () => context.push(AppRoutes.preference(p.id)),
    );
  }
}

class _InspirationTile extends StatelessWidget {
  const _InspirationTile({required this.inspiration});

  final Inspiration inspiration;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final i = inspiration;
    final host = i.sourceHost;
    return ListTile(
      key: Key('inspiration-${i.id}'),
      leading: SizedBox.square(
        dimension: 48,
        child: i.image != null
            ? GarmentPhotoView(photo: i.image!, size: 48)
            : i.palette.isEmpty
            ? Icon(host == null ? Icons.lightbulb_outline : Icons.link)
            : Wrap(
                spacing: 2,
                runSpacing: 2,
                alignment: WrapAlignment.center,
                runAlignment: WrapAlignment.center,
                children: [
                  for (final rgb in i.palette.take(4))
                    ColorDot(
                      rgb: rgb,
                      label: l10n.colorLabel(
                        ReferenceColor.fromRgb(rgb)?.id ?? 'custom',
                      ),
                      size: 20,
                    ),
                ],
              ),
      ),
      title: Text(
        i.title ?? host ?? '',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        [
          if (i.title != null && host != null) host,
          inspirationTags(l10n, i),
        ].where((s) => s.isNotEmpty).join('\n'),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () => context.push(AppRoutes.inspiration(i.id)),
    );
  }
}
