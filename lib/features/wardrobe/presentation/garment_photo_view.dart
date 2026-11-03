import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../application/photo_providers.dart';
import '../domain/garment_photo.dart';

/// Mostra uma foto guardada. Enquanto não está disponível (a descarregar,
/// ou offline e nunca descarregada) mostra um marcador, nunca uma imagem
/// vazia.
class GarmentPhotoView extends ConsumerWidget {
  const GarmentPhotoView({
    required this.photo,
    this.variant = PhotoVariant.thumb,
    this.size = 72,
    super.key,
  });

  final GarmentPhoto photo;
  final PhotoVariant variant;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bytes = ref.watch(photoBytesProvider((photo, variant))).value;
    final colors = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox.square(
        dimension: size,
        child: bytes == null
            ? ColoredBox(
                color: colors.surfaceContainerHighest,
                child: Icon(
                  Icons.image_outlined,
                  color: colors.onSurfaceVariant,
                  semanticLabel: AppLocalizations.of(context).photoUnavailable,
                ),
              )
            : Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true),
      ),
    );
  }
}
