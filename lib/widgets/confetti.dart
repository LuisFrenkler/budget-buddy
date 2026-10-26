import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../utils/theme.dart';

// A short burst of confetti from the top, for moments worth celebrating.
// Purely decorative: it ignores touches and ends by itself.
class ConfettiBurst extends StatefulWidget {
  const ConfettiBurst({super.key});

  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _Piece {
  final double x, speed, drift, spin, size, delay;
  final Color color;
  final bool round;
  _Piece(math.Random r)
      : x = r.nextDouble(),
        speed = 0.55 + r.nextDouble() * 0.6,
        drift = (r.nextDouble() - 0.5) * 0.5,
        spin = (r.nextDouble() - 0.5) * 14,
        size = 6 + r.nextDouble() * 6,
        delay = r.nextDouble() * 0.25,
        color = AppColors.chart[r.nextInt(AppColors.chart.length)],
        round = r.nextBool();
}

class _ConfettiBurstState extends State<ConfettiBurst> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..forward();
  final _pieces = List.generate(110, (_) => _Piece(math.Random()));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) => CustomPaint(size: Size.infinite, painter: _ConfettiPainter(_pieces, _c.value)),
        ),
      );
}

class _ConfettiPainter extends CustomPainter {
  final List<_Piece> pieces;
  final double t;
  _ConfettiPainter(this.pieces, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (final p in pieces) {
      final local = ((t - p.delay) / (1 - p.delay)).clamp(0.0, 1.0);
      if (local <= 0) continue;
      // falls with a little gravity, sways sideways, fades out at the end
      final y = -20 + (size.height + 40) * (local * p.speed + local * local * 0.5);
      final x = size.width * p.x + math.sin(local * 6 + p.x * 10) * 18 + p.drift * size.width * local;
      paint.color = p.color.withValues(alpha: local > 0.8 ? (1 - local) / 0.2 : 1);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(local * p.spin);
      if (p.round) {
        canvas.drawCircle(Offset.zero, p.size / 2.4, paint);
      } else {
        canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.45), paint);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter old) => old.t != t;
}
