import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../utils/theme.dart';
import 'brand.dart';

// How Buddy feels right now. Small, quiet signals instead of a mascot:
// - idle: the coin at rest
// - thinking: a copper arc circles him while he works on an answer
// - happy: a short hop and a few sparks (goal saved, step done, fact kept)
// - alert: a slow amber pulse when he speaks up about something important
enum BuddyMood { idle, thinking, happy, alert }

// Buddy's avatar: a glowing copper sphere with the "b" of the logo.
class BuddyOrb extends StatefulWidget {
  // the sphere: lit from the top left, glowing softly (more so at night)
  static BoxDecoration sphere(double size, {double glow = 1}) {
    final night = ThemeController.isDark.value;
    return BoxDecoration(
      shape: BoxShape.circle,
      gradient: const RadialGradient(
        center: Alignment(-0.32, -0.44),
        radius: 0.95,
        colors: [Color(0xFFFFEBD9), Color(0xFFF4B98A), Color(0xFFC8682F), Color(0xFF7A3A16)],
        stops: [0, 0.28, 0.66, 1],
      ),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFFD9813F).withValues(alpha: (night ? 0.55 : 0.32) * glow),
          blurRadius: size * (night ? 0.6 : 0.45),
          offset: Offset(0, night ? 0 : size * 0.18),
        ),
      ],
    );
  }

  final double size;
  // legacy switch: true is the same as BuddyMood.thinking
  final bool active;
  final BuddyMood mood;
  const BuddyOrb({super.key, this.size = 40, this.active = false, this.mood = BuddyMood.idle});

  BuddyMood get effective => active && mood == BuddyMood.idle ? BuddyMood.thinking : mood;

  @override
  State<BuddyOrb> createState() => _BuddyOrbState();
}

class _BuddyOrbState extends State<BuddyOrb> with TickerProviderStateMixin {
  late final AnimationController _loop = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
  late final AnimationController _hop = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void initState() {
    super.initState();
    _apply(null);
  }

  @override
  void didUpdateWidget(BuddyOrb old) {
    super.didUpdateWidget(old);
    if (old.effective != widget.effective) _apply(old.effective);
  }

  void _apply(BuddyMood? before) {
    final m = widget.effective;
    if (m == BuddyMood.thinking || m == BuddyMood.alert) {
      _loop.duration = Duration(milliseconds: m == BuddyMood.alert ? 1800 : 1100);
      _loop.repeat();
    } else {
      _loop.stop();
      _loop.value = 0;
    }
    if (m == BuddyMood.happy) _hop.forward(from: 0);
  }

  @override
  void dispose() {
    _loop.dispose();
    _hop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final coin = Container(
      width: size,
      height: size,
      decoration: BuddyOrb.sphere(size),
      child: CustomPaint(painter: MarkPainter(color: const Color(0xF2FFF7F0))),
    );
    if (reduce) return coin;
    return AnimatedBuilder(
      animation: Listenable.merge([_loop, _hop]),
      builder: (_, child) {
        final m = widget.effective;
        // a hop: up and a little wider, then settle
        final h = _hop.value;
        final lift = m == BuddyMood.happy ? math.sin(h * math.pi) * size * 0.14 : 0.0;
        final scale = m == BuddyMood.happy ? 1 + math.sin(h * math.pi) * 0.08 : 1.0;
        return SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            foregroundPainter: _MoodPainter(m, _loop.value, h),
            child: Transform.translate(
              offset: Offset(0, -lift),
              child: Transform.scale(scale: scale, child: child),
            ),
          ),
        );
      },
      child: coin,
    );
  }
}

class _MoodPainter extends CustomPainter {
  final BuddyMood mood;
  final double t; // 0..1, looping
  final double hop; // 0..1, once
  _MoodPainter(this.mood, this.t, this.hop);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    switch (mood) {
      case BuddyMood.thinking:
        final ring = Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = math.max(1.5, r * 0.1)
          ..color = AppColors.brand.withValues(alpha: 0.9);
        final rr = r + ring.strokeWidth * 1.4;
        canvas.drawArc(Rect.fromCircle(center: c, radius: rr), t * 2 * math.pi, math.pi * 0.6, false, ring);
        canvas.drawArc(Rect.fromCircle(center: c, radius: rr), t * 2 * math.pi + math.pi, math.pi * 0.25, false,
            ring..color = AppColors.brand.withValues(alpha: 0.35));
      case BuddyMood.alert:
        final p = Curves.easeOut.transform(t);
        canvas.drawCircle(
            c,
            r * (1 + 0.35 * p),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = math.max(1.5, r * 0.08)
              ..color = AppColors.warning.withValues(alpha: 0.7 * (1 - p)));
      case BuddyMood.happy:
        if (hop <= 0 || hop >= 1) return;
        // a few sparks fly out and fade
        final spark = Paint()..color = AppColors.warning.withValues(alpha: (1 - hop).clamp(0, 1));
        for (var i = 0; i < 6; i++) {
          final a = -math.pi / 2 + (i - 2.5) * 0.45;
          final d = r * (1.05 + 0.55 * hop);
          canvas.drawCircle(c + Offset(math.cos(a) * d, math.sin(a) * d), math.max(1.2, r * 0.07) * (1 - hop * 0.5), spark);
        }
      case BuddyMood.idle:
        break;
    }
  }

  @override
  bool shouldRepaint(_MoodPainter old) => old.t != t || old.hop != hop || old.mood != mood;
}
