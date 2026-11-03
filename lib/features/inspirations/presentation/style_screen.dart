import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../l10n/app_localizations.dart';
import '../../wardrobe/domain/reference_color.dart';
import '../../wardrobe/presentation/colors_editor.dart';
import '../application/inspiration_providers.dart';
import '../domain/inspiration.dart';
import 'inspiration_messages.dart';

/// Separador Estilo: inspirações guardadas. Não são peças.
class StyleScreen extends ConsumerWidget {
  const StyleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final inspirations = ref.watch(inspirationsProvider);
    final ready = ref.watch(inspirationRepositoryProvider) != null;

    final Widget body = switch (inspirations) {
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

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        // Os separadores ficam montados lado a lado: sem Hero partilhado.
        heroTag: null,
        key: const Key('inspiration-add'),
        onPressed: ready ? () => context.push(AppRoutes.newInspiration) : null,
        icon: const Icon(Icons.add),
        label: Text(l10n.inspirationAdd),
      ),
      body: body,
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
        child: i.palette.isEmpty
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
