import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../outfits/domain/outfit.dart';
import '../../wardrobe/domain/garment.dart';
import '../../wardrobe/presentation/garment_cutout.dart';
import '../../wear/domain/calendar_day.dart';
import '../application/plan_providers.dart';

/// A semana como um fio com sete nós (visual fio v2). Cada nó tem a cor da
/// peça principal do dia; um nó tracejado é um dia ainda por decidir.
class WeekThread extends StatelessWidget {
  const WeekThread({
    required this.days,
    required this.today,
    required this.garments,
    super.key,
  });

  final List<WeekDayView> days;
  final CalendarDay today;
  final Map<GarmentId, Garment> garments;

  /// A cor do dia: o que foi vestido, senão o que está planeado, dando
  /// preferência à parte de cima ou à peça única.
  Color? _knotColor(WeekDayView d) {
    final ids = d.wear?.garmentIds ?? [];
    if (ids.isNotEmpty) {
      for (final id in ids) {
        if (garments[id] case final g?) {
          return GarmentCutout.mainColor(g) ?? AppColors.onSurfaceMuted;
        }
      }
    }
    final items = d.draft.items;
    if (items.isEmpty) return null;
    // Com camada, vê-se a de cima.
    final main =
        items.where((i) => i.role == OutfitRole.midLayer).firstOrNull ??
        items
            .where(
              (i) =>
                  i.role == OutfitRole.mainTop || i.role == OutfitRole.onePiece,
            )
            .firstOrNull ??
        items.first;
    final g = garments[main.garmentId];
    return (g == null ? null : GarmentCutout.mainColor(g)) ??
        AppColors.onSurfaceMuted;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final knots = [
      for (final d in days)
        (
          color: _knotColor(d),
          today: d.day == today,
          label: d.day == today
              ? l10n.weekToday.toLowerCase()
              : l10n.weekdayShort('${d.day.weekday}'),
        ),
    ];
    final planned = knots.where((k) => k.color != null).length;
    return Semantics(
      label: l10n.weekThreadLabel(planned),
      excludeSemantics: true,
      child: SizedBox(
        key: const Key('week-thread'),
        height: 68,
        width: double.infinity,
        child: CustomPaint(
          painter: _ThreadPainter(
            knots: knots,
            labelStyle: Theme.of(context).textTheme.labelSmall!,
          ),
        ),
      ),
    );
  }
}

typedef _Knot = ({Color? color, bool today, String label});

class _ThreadPainter extends CustomPainter {
  _ThreadPainter({required this.knots, required this.labelStyle});

  final List<_Knot> knots;
  final TextStyle labelStyle;

  @override
  void paint(Canvas canvas, Size size) {
    if (knots.isEmpty) return;
    const r = 7.0;
    final step = (size.width - 2 * (r + 6)) / math.max(knots.length - 1, 1);
    double x(int i) => r + 6 + i * step;
    // Os nós sobem e descem um pouco, como um fio pousado.
    const wobble = [-6.0, 0.0, -7.0, 5.0, -2.0, 0.0, 7.0];
    const mid = 26.0;
    double y(int i) => mid + wobble[i % wobble.length];

    final path = Path()..moveTo(0, mid);
    for (var i = 0; i < knots.length; i++) {
      final px = i == 0 ? 0.0 : x(i - 1);
      final py = i == 0 ? mid : y(i - 1);
      final cx = (px + x(i)) / 2;
      path.cubicTo(cx, py - 10, cx, y(i) + 10, x(i), y(i));
    }
    path.quadraticBezierTo(size.width - 4, mid + 6, size.width, mid);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..color = AppColors.accent.withValues(alpha: 0.55),
    );

    for (final (i, k) in knots.indexed) {
      final c = Offset(x(i), y(i));
      final radius = k.today ? r + 2 : r;
      if (k.color case final color?) {
        canvas.drawCircle(c, radius, Paint()..color = color);
        if (color.computeLuminance() > 0.8 || k.today) {
          canvas.drawCircle(
            c,
            radius,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = k.today ? 2 : 1.2
              ..color = k.today ? AppColors.onSurface : AppColors.outline,
          );
        }
      } else {
        canvas.drawCircle(c, radius, Paint()..color = AppColors.background);
        _dashedCircle(
          canvas,
          c,
          radius,
          k.today ? AppColors.onSurface : const Color(0xFF9C9A93),
        );
      }
      final tp = TextPainter(
        text: TextSpan(
          text: k.label,
          style: labelStyle.copyWith(
            fontSize: 11,
            fontWeight: k.today ? FontWeight.w700 : FontWeight.w500,
            color: k.today ? AppColors.onSurface : AppColors.onSurfaceMuted,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(c.dx - tp.width / 2, 48));
    }
  }

  void _dashedCircle(Canvas canvas, Offset c, double r, Color color) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = color;
    const dashes = 8;
    const sweep = math.pi / dashes;
    for (var i = 0; i < dashes; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        i * 2 * sweep,
        sweep,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_ThreadPainter old) =>
      old.knots.length != knots.length ||
      [
        for (final (i, k) in knots.indexed)
          k.color != old.knots[i].color ||
              k.today != old.knots[i].today ||
              k.label != old.knots[i].label,
      ].any((changed) => changed);
}
