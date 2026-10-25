import 'package:flutter/material.dart';

// a rounded-square icon chip (used as leading element in list rows)
class IconChip extends StatelessWidget {
  final IconData icon;
  final Color color;
  const IconChip(this.icon, this.color, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, color: color, size: 22),
    );
  }
}
