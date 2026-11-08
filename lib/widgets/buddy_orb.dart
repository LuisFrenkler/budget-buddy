import 'package:flutter/material.dart';
import '../utils/theme.dart';
import 'brand.dart';

// Buddy's avatar: the "b" of the logo in a brand-coloured circle. [active]
// (Buddy is answering) adds a thin ring; the chat's typing dots carry the rest.
class BuddyOrb extends StatelessWidget {
  final double size;
  final bool active;
  const BuddyOrb({super.key, this.size = 40, this.active = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.primary,
        border: active ? Border.all(color: AppColors.primary.withValues(alpha: 0.35), width: size * 0.06, strokeAlign: BorderSide.strokeAlignOutside) : null,
      ),
      child: CustomPaint(painter: MarkPainter()),
    );
  }
}
