import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../engine/domain/comfort.dart';
import '../../outfits/domain/outfit.dart';
import '../../wardrobe/domain/garment.dart';
import '../../wardrobe/presentation/garment_cutout.dart';
import '../../wear/domain/calendar_day.dart';
import '../application/plan_providers.dart';

/// Os sete dias numa faixa (design v3): dia da semana, número, o tempo
/// previsto e um nó com a cor da peça principal (tracejado se por decidir).
/// Tocar num dia leva ao seu cartão.
class WeekStrip extends StatelessWidget {
  const WeekStrip({
    required this.days,
    required this.today,
    required this.garments,
    required this.weather,
    required this.onSelect,
    super.key,
  });

  final List<WeekDayView> days;
  final CalendarDay today;
  final Map<GarmentId, Garment> garments;
  final Map<CalendarDay, WeatherConditions> weather;
  final ValueChanged<int> onSelect;

  /// A cor do dia: o que foi vestido, senão o que está planeado, dando
  /// preferência à camada do meio, à parte de cima ou à peça única.
  static Color? dayColor(
    WeekDayView d,
    Map<GarmentId, Garment> garments,
    AppColors colors,
  ) {
    for (final id in d.wear?.garmentIds ?? const <GarmentId>[]) {
      if (garments[id] case final g?) {
        return GarmentCutout.mainColor(g) ?? colors.onSurfaceMuted;
      }
    }
    final items = d.draft.items;
    if (items.isEmpty) return null;
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
        colors.onSurfaceMuted;
  }

  static IconData weatherIcon(WeatherConditions w) => w.rain
      ? Icons.water_drop_outlined
      : w.sunny
      ? Icons.wb_sunny_outlined
      : Icons.cloud_outlined;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final planned = days
        .where((d) => dayColor(d, garments, colors) != null)
        .length;
    return Semantics(
      label: l10n.weekThreadLabel(planned),
      container: true,
      child: Row(
        key: const Key('week-strip'),
        spacing: 6,
        children: [
          for (final (i, d) in days.indexed)
            Expanded(
              child: _DayCell(
                key: Key('week-strip-$i'),
                label: d.day == today
                    ? l10n.weekToday
                    : l10n.weekdayShort('${d.day.weekday}'),
                number: d.day.toLocalDateTime().day,
                isToday: d.day == today,
                color: dayColor(d, garments, colors),
                weather: weather[d.day],
                onTap: () => onSelect(i),
              ),
            ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.label,
    required this.number,
    required this.isToday,
    required this.color,
    required this.weather,
    required this.onTap,
    super.key,
  });

  final String label;
  final int number;
  final bool isToday;
  final Color? color;
  final WeatherConditions? weather;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final fg = isToday ? theme.colorScheme.onPrimary : colors.onSurface;
    final muted = isToday
        ? theme.colorScheme.onPrimary.withValues(alpha: 0.8)
        : colors.onSurfaceMuted;
    return Material(
      color: isToday ? theme.colorScheme.primary : theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: isToday ? BorderSide.none : BorderSide(color: colors.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FittedBox(
                child: Text(
                  label,
                  maxLines: 1,
                  style: theme.textTheme.labelSmall?.copyWith(color: muted),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$number',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              if (weather case final w?)
                FittedBox(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(WeekStrip.weatherIcon(w), size: 12, color: muted),
                      const SizedBox(width: 2),
                      Text(
                        '${w.feelsLikeC.round()}°',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: muted,
                        ),
                      ),
                    ],
                  ),
                )
              else
                const SizedBox(height: 14),
              const SizedBox(height: 6),
              SizedBox.square(
                dimension: 12,
                child: CustomPaint(
                  painter: _KnotPainter(
                    color: color,
                    ring: isToday ? theme.colorScheme.onPrimary : colors.faint,
                    outline: colors.outline,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Um nó do fio: cheio com a cor do dia, ou tracejado se por decidir.
class _KnotPainter extends CustomPainter {
  _KnotPainter({
    required this.color,
    required this.ring,
    required this.outline,
  });

  final Color? color;
  final Color ring;
  final Color outline;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 1;
    if (color case final fill?) {
      canvas.drawCircle(c, r, Paint()..color = fill);
      if (fill.computeLuminance() > 0.8) {
        canvas.drawCircle(
          c,
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = outline,
        );
      }
      return;
    }
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = ring;
    const dashes = 6;
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
  bool shouldRepaint(_KnotPainter old) =>
      old.color != color || old.ring != ring || old.outline != outline;
}
