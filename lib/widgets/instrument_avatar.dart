import 'package:flutter/material.dart';
import '../utils/theme.dart';

// Round avatar with the first letter of a stock, ETF or coin on a color that
// is always the same for the same name (a calm stand-in for a logo).
class InstrumentAvatar extends StatelessWidget {
  final String name;
  final double size;

  const InstrumentAvatar(this.name, {super.key, this.size = 42});

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    final letter = trimmed.isEmpty ? '?' : trimmed[0].toUpperCase();
    // stable color per name (String.hashCode is not stable across runs)
    int hash = 0;
    for (final c in trimmed.codeUnits) {
      hash = (hash * 31 + c) & 0x7fffffff;
    }
    final color = AppColors.chart[hash % AppColors.chart.length];
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.18), shape: BoxShape.circle),
      child: Text(letter, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: size * 0.42)),
    );
  }
}
