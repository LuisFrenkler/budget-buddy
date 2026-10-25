import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../utils/theme.dart';

// Buddy's face: a softly glowing orb of brand colors that slowly turns and
// breathes. While Buddy thinks ([active]) it turns faster and glows brighter.
class BuddyOrb extends StatefulWidget {
  final double size;
  final bool active;
  const BuddyOrb({super.key, this.size = 40, this.active = false});

  @override
  State<BuddyOrb> createState() => _BuddyOrbState();
}

class _BuddyOrbState extends State<BuddyOrb> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          final t = _c.value * (widget.active ? 3 : 1);
          final breathe = 1 + 0.04 * math.sin(_c.value * 2 * math.pi * (widget.active ? 6 : 2));
          return Transform.scale(
            scale: breathe,
            child: CustomPaint(
              size: Size.square(widget.size),
              painter: _OrbPainter(t, widget.active),
            ),
          );
        },
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  final double t;
  final bool active;
  _OrbPainter(this.t, this.active);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;

    // outer glow
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = AppColors.primary.withValues(alpha: active ? 0.55 : 0.35)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.35),
    );

    // turning colors
    final rect = Rect.fromCircle(center: c, radius: r * 0.9);
    canvas.drawCircle(
      c,
      r * 0.9,
      Paint()
        ..shader = SweepGradient(
          transform: GradientRotation(t * 2 * math.pi),
          colors: const [
            Color(0xFF7C5CFF),
            Color(0xFF38BDF8),
            Color(0xFFF472B6),
            Color(0xFFA48BFF),
            Color(0xFF7C5CFF),
          ],
        ).createShader(rect),
    );

    // soft light from the top left gives it depth
    canvas.drawCircle(
      c,
      r * 0.9,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.45),
          radius: 0.9,
          colors: [Colors.white.withValues(alpha: 0.75), Colors.white.withValues(alpha: 0.0)],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _OrbPainter old) => old.t != t || old.active != active;
}
