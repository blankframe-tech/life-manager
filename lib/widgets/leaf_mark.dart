import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The V2 logo: a leaf drawn as a rounded square with two sharp corners and a
/// stem. Drawn in code so it's crisp at any size and follows the theme.
class LeafMark extends StatelessWidget {
  const LeafMark({super.key, this.size = 96, this.color});
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Life Manager logo',
    image: true,
    child: CustomPaint(
      size: Size.square(size),
      painter: _LeafPainter(color ?? context.colors.primary),
    ),
  );
}

class _LeafPainter extends CustomPainter {
  _LeafPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 100;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final leaf = RRect.fromLTRBAndCorners(
      14 * s,
      14 * s,
      86 * s,
      86 * s,
      topLeft: Radius.circular(40 * s),
      bottomRight: Radius.circular(40 * s),
      topRight: Radius.circular(6 * s),
      bottomLeft: Radius.circular(6 * s),
    );
    canvas.drawRRect(leaf, paint);
    final stem = Path()
      ..moveTo(30 * s, 70 * s)
      ..quadraticBezierTo(44 * s, 52 * s, 62 * s, 38 * s);
    canvas.drawPath(stem, paint);
    final vein = Path()
      ..moveTo(46 * s, 54 * s)
      ..lineTo(46 * s, 40 * s)
      ..moveTo(46 * s, 54 * s)
      ..lineTo(60 * s, 54 * s);
    canvas.drawPath(vein, paint..strokeWidth = 5 * s);
  }

  @override
  bool shouldRepaint(_LeafPainter old) => old.color != color;
}
