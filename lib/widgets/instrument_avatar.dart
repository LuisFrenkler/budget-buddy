import 'package:flutter/material.dart';
import '../utils/brands.dart';
import '../utils/theme.dart';

// Round avatar with the initials of a stock, ETF or coin on a color that is
// always the same for the same name (a calm stand-in for a logo). Fund-house
// words are skipped, so two iShares ETFs read "W" and "S5", not "I" and "I".
class InstrumentAvatar extends StatelessWidget {
  final String name;
  final double size;
  final Color? color; // e.g. the slice colour in the allocation chart

  const InstrumentAvatar(this.name, {super.key, this.size = 42, this.color});

  static const _generic = {
    'ishares', 'core', 'xtrackers', 'vanguard', 'amundi', 'spdr', 'lyxor', 'invesco', 'ucits', 'etf',
    'msci', 'ftse', 'the', 'inc', 'ag', 'se',
  };

  static String initials(String name) {
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return '?';
    final meaningful = words.where((w) => !_generic.contains(w.toLowerCase())).toList();
    final pick = meaningful.isEmpty ? words : meaningful;
    String first(String w) {
      final m = RegExp(r'[A-Za-z0-9ÄÖÜäöü]').firstMatch(w);
      return m == null ? '' : m.group(0)!.toUpperCase();
    }
    // a long fund name keeps two telling parts ("S&P 500" -> "S5")
    if (words.length > 2 && pick.length >= 2) return first(pick[0]) + first(pick[1]);
    return first(pick[0]).isEmpty ? '?' : first(pick[0]);
  }

  @override
  Widget build(BuildContext context) {
    final brand = Brands.of(name);
    if (brand != null && this.color == null) return BrandAvatar(brand, size: size);
    final trimmed = name.trim();
    final letter = initials(trimmed);
    // stable color per name (String.hashCode is not stable across runs)
    int hash = 0;
    for (final c in trimmed.codeUnits) {
      hash = (hash * 31 + c) & 0x7fffffff;
    }
    final color = this.color ?? AppColors.chart[hash % AppColors.chart.length];
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.18), shape: BoxShape.circle),
      child: Text(letter,
          style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: size * (letter.length > 1 ? 0.34 : 0.42))),
    );
  }
}
