import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The app's signature header: green gradient, soft circles, optional little school drawing.
/// Used on the first screen, sign-in, home and every school page so the whole app feels like one.
class BrandHeader extends StatelessWidget {
  const BrandHeader({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(20, 20, 20, 26),
    this.illustration = false,
    this.radius = 30,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool illustration;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF084D31), AppTheme.green, AppTheme.greenLight],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(radius)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(radius)),
        child: Stack(children: [
          Positioned.fill(child: CustomPaint(painter: _HeaderArt(illustration))),
          Padding(padding: padding, child: child),
        ]),
      ),
    );
  }
}

class _HeaderArt extends CustomPainter {
  _HeaderArt(this.illustration);

  final bool illustration;

  @override
  void paint(Canvas canvas, Size size) {
    final soft = Paint()..color = Colors.white.withValues(alpha: 0.06);
    canvas.drawCircle(Offset(size.width * 0.92, size.height * 0.05), size.width * 0.34, soft);
    canvas.drawCircle(Offset(size.width * 0.02, size.height * 1.0), size.width * 0.24, soft);

    final ring = Paint()
      ..color = AppTheme.gold.withValues(alpha: 0.28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(Offset(size.width * 0.78, size.height * 0.86), 44, ring);
    canvas.drawCircle(Offset(size.width * 0.78, size.height * 0.86), 62, ring..color = AppTheme.gold.withValues(alpha: 0.14));

    final dot = Paint()..color = Colors.white.withValues(alpha: 0.12);
    for (var r = 0; r < 4; r++) {
      for (var c = 0; c < 5; c++) {
        canvas.drawCircle(Offset(size.width * 0.58 + c * 14, size.height * 0.55 + r * 14), 1.6, dot);
      }
    }

    if (illustration) _school(canvas, Offset(size.width - 148, 22));
  }

  /// A simple school building: roof, windows, door and a flag.
  void _school(Canvas canvas, Offset o) {
    Paint fill(Color c, double a) => Paint()..color = c.withValues(alpha: a);
    final white = fill(Colors.white, 0.20);
    final gold = fill(AppTheme.gold, 0.85);
    // building
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(o.dx + 18, o.dy + 48, 104, 52), const Radius.circular(4)), white);
    // roof
    final roof = Path()
      ..moveTo(o.dx + 8, o.dy + 50)
      ..lineTo(o.dx + 70, o.dy + 14)
      ..lineTo(o.dx + 132, o.dy + 50)
      ..close();
    canvas.drawPath(roof, gold);
    // door
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(o.dx + 61, o.dy + 72, 18, 28), const Radius.circular(3)), gold);
    // windows
    final win = fill(Colors.white, 0.45);
    for (final x in [30.0, 44.0, 86.0, 100.0]) {
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(o.dx + x, o.dy + 62, 10, 12), const Radius.circular(2)), win);
    }
    // flag
    final pole = Paint()
      ..color = Colors.white.withValues(alpha: 0.7)
      ..strokeWidth = 2;
    canvas.drawLine(Offset(o.dx + 70, o.dy + 14), Offset(o.dx + 70, o.dy - 8), pole);
    final flag = Path()
      ..moveTo(o.dx + 70, o.dy - 8)
      ..lineTo(o.dx + 88, o.dy - 2)
      ..lineTo(o.dx + 70, o.dy + 4)
      ..close();
    canvas.drawPath(flag, gold);
  }

  @override
  bool shouldRepaint(covariant _HeaderArt old) => old.illustration != illustration;
}
