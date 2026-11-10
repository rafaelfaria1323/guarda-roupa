import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../account_sync/application/providers.dart';
import '../../shopping/application/shopping_providers.dart';
import '../application/photo_providers.dart';
import '../domain/garment_photo.dart';

/// O endereço do Google Lens para uma imagem pública.
Uri lensSearchUri(Uri image) =>
    Uri.https('lens.google.com', '/uploadbyurl', {'url': image.toString()});

/// "Procurar no Google Lens": abre o Lens (no navegador, sem app) com a
/// imagem, para encontrar a peça ou parecidas em lojas. As fotos são
/// privadas: cria-se um link temporário só para esta pesquisa, depois de
/// o utilizador confirmar que a imagem vai para a Google.
///
/// Só aparece com cloud e sessão (sem isso não há link para dar à Google).
class LensSearchButton extends ConsumerWidget {
  const LensSearchButton({required this.photo, super.key});

  final GarmentPhoto photo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storage = ref.watch(photoStorageProvider);
    final userId = ref.watch(currentUserProvider).value?.id;
    if (storage == null || userId == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    return TextButton.icon(
      key: const Key('lens-search'),
      onPressed: () => showDialog<void>(
        context: context,
        builder: (_) => _LensDialog(
          link: storage.temporaryLink(
            PhotoRules.storagePath(userId, photo.id, PhotoVariant.main),
          ),
        ),
      ),
      icon: const Icon(Icons.travel_explore),
      label: Text(l10n.lensSearch),
    );
  }
}

/// Avisa e prepara o link; "Abrir" só fica ativo com o link pronto, para o
/// toque abrir o Lens diretamente (o navegador bloqueia janelas abertas
/// depois de uma espera).
class _LensDialog extends ConsumerWidget {
  const _LensDialog({required this.link});

  final Future<Uri> link;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return FutureBuilder<Uri>(
      future: link,
      builder: (context, snapshot) {
        final uri = snapshot.data;
        return AlertDialog(
          title: Text(l10n.lensSearch),
          content: Text(
            snapshot.hasError
                ? l10n.lensSearchUnavailable
                : l10n.lensSearchBody,
            key: Key(snapshot.hasError ? 'lens-error' : 'lens-body'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.cancel),
            ),
            if (!snapshot.hasError)
              FilledButton(
                key: const Key('lens-open'),
                onPressed: uri == null
                    ? null
                    : () {
                        ref.read(openLinkProvider)(lensSearchUri(uri));
                        Navigator.pop(context);
                      },
                child: Text(l10n.lensSearchOpen),
              ),
          ],
        );
      },
    );
  }
}
