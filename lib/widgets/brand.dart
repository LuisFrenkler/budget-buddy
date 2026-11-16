import 'package:flutter/material.dart';
import '../utils/theme.dart';

// The app mark: Ahead's copper coin with the "A" glyph, matching the icon
// and the landing page. [inverse]: a white coin with a copper "A", for
// copper grounds.
class BrandMark extends StatelessWidget {
  final double size;
  final bool inverse;
  const BrandMark({super.key, this.size = 56, this.inverse = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      // the copper sphere of the logo (white on copper grounds)
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: inverse ? Colors.white : null,
        gradient: inverse
            ? null
            : const RadialGradient(
                center: Alignment(-0.32, -0.44),
                radius: 0.95,
                colors: [Color(0xFFFFEBD9), Color(0xFFF4B98A), Color(0xFFC8682F), Color(0xFF7A3A16)],
                stops: [0, 0.28, 0.66, 1],
              ),
      ),
      child: CustomPaint(painter: MarkPainter(color: inverse ? AppColors.brand : Colors.white)),
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
  final Color color;
  MarkPainter({this.color = Colors.white});

  @override
  void paint(Canvas canvas, Size size) {
    // Ahead's "A", the Bricolage SemiBold capital, on a 1024 grid and centred
    // the same way as in assets/icon/icon.png, whatever box the parent gives
    final side = size.shortestSide;
    canvas.translate((size.width - side) / 2, (size.height - side) / 2);
    final s = side / 1024;
    final glyph = Path()
      ..moveTo(317.8 * s, 718.0 * s)
      ..lineTo(455.9 * s, 318.0 * s)
      ..lineTo(568.1 * s, 318.0 * s)
      ..lineTo(706.2 * s, 718.0 * s)
      ..lineTo(622.6 * s, 718.0 * s)
      ..lineTo(516.5 * s, 379.2 * s)
      ..lineTo(508.1 * s, 379.2 * s)
      ..lineTo(400.8 * s, 718.0 * s)
      ..close()
      ..moveTo(391.1 * s, 635.6 * s)
      ..lineTo(391.1 * s, 581.6 * s)
      ..lineTo(643.2 * s, 581.6 * s)
      ..lineTo(643.2 * s, 635.6 * s)
      ..close();
    canvas.drawPath(glyph, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant MarkPainter oldDelegate) => oldDelegate.color != color;
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
      style: TextStyle(fontFamily: AppFonts.display, fontSize: size, fontWeight: FontWeight.w600, letterSpacing: -0.9),
    );
  }
}

// Copper light, the landing page's atmosphere: dark at the top, glowing
// warm towards the bottom, with two soft lights. The guest's app bar uses
// [CopperLight.top] so bar and hero meet without a seam.
class CopperLight extends StatelessWidget {
  final Widget child;
  const CopperLight({super.key, required this.child});

  static const top = Color(0xFF2E160A);
  static const peach = Color(0xFFF4C7A1);
  static const card = Color(0xFF24130A);

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [top, Color(0xFF5E2C14), Color(0xFFA4542A), Color(0xFFD9813F)],
          stops: [0, .38, .78, 1],
        ),
      ),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-1.1, -0.7),
            radius: 1.1,
            colors: [Color(0x66C7703A), Color(0x00C7703A)],
          ),
        ),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(1.1, 1.2),
              radius: 0.9,
              colors: [Color(0x80FFD6B0), Color(0x00FFD6B0)],
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

// The soft light behind Buddy's screens: a peach glow on warm paper in
// Glow (light), copper glowing out of the dark in Night. [align] says where
// it sits; the child draws on top.
class AmbientGlow extends StatelessWidget {
  final Widget child;
  final Alignment align;
  final double size;
  const AmbientGlow({super.key, required this.child, this.align = const Alignment(-0.4, -1.25), this.size = 1.6});

  @override
  Widget build(BuildContext context) {
    final night = ThemeController.isDark.value;
    return Stack(children: [
      Positioned.fill(
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: align,
                radius: size * 0.62,
                colors: night
                    ? const [Color(0x8CD9813F), Color(0x408E4620), Color(0x000C0A09)]
                    : const [Color(0xD9F4B78A), Color(0x73F4C7A1), Color(0x00FBF7F3)],
                stops: const [0, 0.5, 1],
              ),
            ),
          ),
        ),
      ),
      child,
    ]);
  }
}
