import 'package:flutter/material.dart';

import 'theme.dart';

/// Logótipo "fio": um fio que desenha um "f", com um ponto.
/// Os traços seguem o ícone da app (viewBox 76×76).
class FioMark extends StatelessWidget {
  const FioMark({this.size = 32, this.color, super.key});

  final double size;

  /// `null` = o destaque do tema.
  final Color? color;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'fio',
    child: CustomPaint(
      size: Size.square(size),
      painter: _FioMarkPainter(color ?? AppColors.of(context).accent),
    ),
  );
}

class _FioMarkPainter extends CustomPainter {
  _FioMarkPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 76);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.5
      ..strokeCap = StrokeCap.round;
    final thread = Path()
      ..moveTo(14, 58)
      ..cubicTo(24, 58, 28, 50, 28, 38)
      ..cubicTo(28, 26, 32, 14, 44, 14)
      ..cubicTo(52, 14, 54, 20, 54, 24)
      ..cubicTo(54, 30, 48, 32, 44, 32);
    canvas
      ..drawPath(thread, stroke)
      ..drawLine(const Offset(20, 36), const Offset(42, 36), stroke)
      ..drawCircle(const Offset(58, 58), 4.2, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_FioMarkPainter old) => old.color != color;
}

/// Logótipo com o nome, para o ecrã de entrada e cabeçalhos.
class FioWordmark extends StatelessWidget {
  const FioWordmark({this.size = 28, super.key});

  final double size;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      FioMark(size: size),
      SizedBox(width: size * 0.2),
      ExcludeSemantics(
        child: Text(
          'fio',
          style: TextStyle(
            fontFamily: displayFont,
            fontWeight: FontWeight.w600,
            fontSize: size * 0.85,
            color: AppColors.of(context).onSurface,
            height: 1,
          ),
        ),
      ),
    ],
  );
}
