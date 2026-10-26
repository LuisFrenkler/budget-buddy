import 'package:flutter/material.dart';

// Well-known merchants and instruments, recognised from a booking note or a
// holding name, shown as a monogram in the brand's colour (no logos), so a
// list reads at a glance like in a banking app.
class Brand {
  final String mark; // one to three characters
  final Color background;
  final Color foreground;
  const Brand(this.mark, this.background, [this.foreground = Colors.white]);
}

class Brands {
  // lower-case pattern -> brand; the first match wins, so longer names first
  static const _list = <(String, Brand)>[
    ('lieferando', Brand('L', Color(0xFFFF8000))),
    ('netflix', Brand('N', Color(0xFFE50914))),
    ('spotify', Brand('S', Color(0xFF1DB954), Colors.black)),
    ('disney', Brand('D+', Color(0xFF113CCF))),
    ('youtube', Brand('▶', Color(0xFFFF0000))),
    ('amazon', Brand('a', Color(0xFF232F3E), Color(0xFFFF9900))),
    ('zalando', Brand('Z', Color(0xFFFF6900))),
    ('aldi süd', Brand('A', Color(0xFF00005F), Color(0xFFF7B500))),
    ('aldi', Brand('A', Color(0xFF00005F), Color(0xFFF7B500))),
    ('lidl', Brand('L', Color(0xFF0050AA), Color(0xFFFFF000))),
    ('rewe', Brand('R', Color(0xFFCC071E))),
    ('edeka', Brand('E', Color(0xFFFFD400), Color(0xFF1C3F94))),
    ('penny', Brand('P', Color(0xFFCD1414))),
    ('kaufland', Brand('K', Color(0xFFE10915))),
    ('netto', Brand('N', Color(0xFFFFE500), Color(0xFFE2001A))),
    ('rossmann', Brand('R', Color(0xFFC3002D))),
    ('ikea', Brand('I', Color(0xFF0058A3), Color(0xFFFFDB00))),
    ('h&m', Brand('H&M', Color(0xFFE50010))),
    ('starbucks', Brand('S', Color(0xFF00704A))),
    ('mcdonald', Brand('M', Color(0xFFDA291C), Color(0xFFFFC72C))),
    ('burger king', Brand('BK', Color(0xFFD62300), Color(0xFFF5EBDC))),
    ('deutsche bahn', Brand('DB', Color(0xFFEC0016))),
    ('db ', Brand('DB', Color(0xFFEC0016))),
    ('uber', Brand('U', Color(0xFF000000))),
    ('bolt', Brand('B', Color(0xFF34D186), Colors.black)),
    ('shell', Brand('S', Color(0xFFFFD500), Color(0xFFDD1D21))),
    ('aral', Brand('A', Color(0xFF0063AE))),
    ('paypal', Brand('P', Color(0xFF003087))),
    ('apple', Brand('', Color(0xFF000000))),
    ('google', Brand('G', Color(0xFFFFFFFF), Color(0xFF4285F4))),
    ('microsoft', Brand('M', Color(0xFF00A4EF))),
    ('telekom', Brand('T', Color(0xFFE20074))),
    ('vodafone', Brand('V', Color(0xFFE60000))),
    ('o2', Brand('O₂', Color(0xFF0019A5))),
    ('bitcoin', Brand('₿', Color(0xFFF7931A))),
    ('ethereum', Brand('Ξ', Color(0xFF627EEA))),
    ('solana', Brand('S', Color(0xFF14F195), Colors.black)),
    ('ishares', Brand('iS', Color(0xFF000000))),
    ('vanguard', Brand('V', Color(0xFF96151D))),
    ('xtrackers', Brand('X', Color(0xFF00205B))),
    ('tesla', Brand('T', Color(0xFFCC0000))),
    ('nvidia', Brand('N', Color(0xFF76B900), Colors.black)),
  ];

  static Brand? of(String? name) {
    final n = ' ${name?.toLowerCase().trim() ?? ''} ';
    if (n.trim().isEmpty) return null;
    for (final (pattern, brand) in _list) {
      if (n.contains(pattern)) return brand;
    }
    return null;
  }
}

class BrandAvatar extends StatelessWidget {
  final Brand brand;
  final double size;
  const BrandAvatar(this.brand, {super.key, this.size = 42});

  @override
  Widget build(BuildContext context) {
    final light = brand.background.computeLuminance() > 0.8;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: brand.background,
        shape: BoxShape.circle,
        border: light ? Border.all(color: const Color(0xFFDADCE0)) : null,
      ),
      child: brand.mark.isEmpty
          ? Icon(Icons.apple, color: brand.foreground, size: size * 0.52)
          : Text(
              brand.mark,
              maxLines: 1,
              style: TextStyle(
                color: brand.foreground,
                fontWeight: FontWeight.w900,
                fontSize: size * (brand.mark.length > 2 ? 0.28 : brand.mark.length == 2 ? 0.34 : 0.44),
                letterSpacing: -0.5,
                height: 1,
              ),
            ),
    );
  }
}
