import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../domain/garment.dart';
import '../domain/garment_photo.dart';
import 'garment_photo_view.dart';

/// A peça "pousada" no papel (visual fio v2): a foto com cantos suaves e
/// uma sombra leve; sem foto, um cartão na cor principal da peça.
class GarmentCutout extends StatelessWidget {
  const GarmentCutout({
    required this.garment,
    this.size = 96,
    this.angle = 0,
    this.variant,
    super.key,
  });

  final Garment garment;
  final double size;

  /// Rotação em radianos, para o flat-lay não parecer uma grelha.
  final double angle;

  /// A versão da foto; por omissão, a principal só acima de 120 px.
  final PhotoVariant? variant;

  /// A cor que ocupa mais da peça, ou `null` se não houver cores.
  static Color? mainColor(Garment garment) {
    if (garment.colors.isEmpty) return null;
    final main = garment.colors.reduce(
      (a, b) => b.proportion > a.proportion ? b : a,
    );
    return Color(0xFF000000 | main.rgb);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final photos = garment.photos;
    final radius = BorderRadius.circular(size * 0.14);
    final Widget body;
    if (photos.isNotEmpty) {
      body = GarmentPhotoView(
        photo: photos.first,
        size: size,
        variant:
            variant ?? (size > 120 ? PhotoVariant.main : PhotoVariant.thumb),
      );
    } else {
      final color = mainColor(garment) ?? colors.surfaceMuted;
      final light = color.computeLuminance() > 0.6;
      body = ColoredBox(
        color: color,
        child: SizedBox.square(
          dimension: size,
          child: Icon(
            Icons.checkroom,
            size: size * 0.42,
            // Sobre a cor da peça: o cinzento escuro do tema claro.
            color: light
                ? AppColors.light.onSurfaceMuted
                : Colors.white.withValues(alpha: 0.85),
          ),
        ),
      );
    }
    return Transform.rotate(
      angle: angle,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(color: colors.surface, width: 3),
          boxShadow: [
            BoxShadow(
              color: colors.shadow,
              blurRadius: 16,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(borderRadius: radius, child: body),
      ),
    );
  }
}
