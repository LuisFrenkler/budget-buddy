import 'package:flutter/material.dart';
import '../utils/theme.dart';

// The app mark, drawn like the app icon: a geometric "b" (stem and coin
// ring) in white on the violet brand gradient.
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
        gradient: const LinearGradient(
          colors: AppColors.heroBrand,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(color: AppColors.primary.withValues(alpha: 0.35), blurRadius: size * 0.4, offset: Offset(0, size * 0.12)),
        ],
      ),
      child: CustomPaint(painter: _MarkPainter()),
    );
  }
}

class _MarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // same geometry as assets/icon/icon.png, on a 1024 grid; the glyph's
    // extent (277..747) is centred on 512
    final s = size.width / 1024;
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

// "BudgetBuddy" in the brand's two tones
class Wordmark extends StatelessWidget {
  final double size;
  const Wordmark({super.key, this.size = 22});

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: 'Budget', style: TextStyle(color: AppColors.text)),
        const TextSpan(text: 'Buddy', style: TextStyle(color: AppColors.primary)),
      ]),
      style: TextStyle(fontSize: size, fontWeight: FontWeight.w800, letterSpacing: -0.5),
    );
  }
}
