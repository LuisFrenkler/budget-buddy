import 'package:flutter/material.dart';
import '../utils/theme.dart';

// The app mark, drawn like the app icon: a geometric "a" (coin ring with the
// stem on the right) in white on the brand colour. Buddy keeps his own "b"
// (MarkPainter), so the app and its coach read as a pair.
class BrandMark extends StatelessWidget {
  final double size;
  const BrandMark({super.key, this.size = 56});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.28),
        color: AppColors.brand,
      ),
      child: CustomPaint(painter: AheadMarkPainter()),
    );
  }
}

// Ahead's "a": the same ring and stem as Buddy's "b", the stem on the right
// and only as tall as the ring. 1024 grid, centred.
class AheadMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    canvas.translate((size.width - side) / 2, (size.height - side) / 2);
    final s = side / 1024;
    final paint = Paint()..color = Colors.white;
    const w = 118.0;
    const cx = 497.0, cy = 512.0, r = 218.0;
    final ring = Path()
      ..fillType = PathFillType.evenOdd
      ..addOval(Rect.fromCircle(center: Offset(cx * s, cy * s), radius: r * s))
      ..addOval(Rect.fromCircle(center: Offset(cx * s, cy * s), radius: 104 * s));
    canvas.drawPath(ring, paint);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH((cx + r - w) * s, (cy - r) * s, w * s, 2 * r * s), Radius.circular(w / 2 * s)),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class MarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // same geometry as assets/icon/icon.png, on a 1024 grid; the glyph's
    // extent (277..747) is centred on 512
    // drawn into the centred square, whatever box the parent gives
    final side = size.shortestSide;
    canvas.translate((size.width - side) / 2, (size.height - side) / 2);
    final s = side / 1024;
    final paint = Paint()..color = Colors.white;
    const w = 118.0;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(277 * s, 210 * s, w * s, 602 * s), Radius.circular(w / 2 * s)),
      paint,
    );
    final ring = Path()
      ..fillType = PathFillType.evenOdd
      ..addOval(Rect.fromCircle(center: Offset(529 * s, 594 * s), radius: 218 * s))
      ..addOval(Rect.fromCircle(center: Offset(529 * s, 594 * s), radius: 104 * s));
    canvas.drawPath(ring, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// "Ahead." with the full stop in the brand colour, the coin of the mark
class Wordmark extends StatelessWidget {
  final double size;
  const Wordmark({super.key, this.size = 22});

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: 'Ahead', style: TextStyle(color: AppColors.text)),
        TextSpan(text: '.', style: TextStyle(color: AppColors.brand)),
      ]),
      style: TextStyle(fontSize: size, fontWeight: FontWeight.w800, letterSpacing: -0.8),
    );
  }
}
