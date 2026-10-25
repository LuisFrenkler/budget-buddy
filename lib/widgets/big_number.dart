import 'package:flutter/material.dart';
import '../utils/money.dart';
import '../utils/theme.dart';

// A money amount that counts up to its new value whenever it changes.
class AnimatedMoney extends StatelessWidget {
  final int cents;
  final TextStyle style;
  final bool signed;

  const AnimatedMoney(this.cents, {super.key, required this.style, this.signed = false});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: cents.toDouble()),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (_, v, __) {
        final c = v.round();
        return Text(signed ? Money.signed(c) : Money.format(c), style: style);
      },
    );
  }
}

// The large headline number at the top of a screen: a quiet label, the big
// animated amount and optional content below (e.g. a ChangeLabel).
class BigNumber extends StatelessWidget {
  final String label;
  final int cents;
  final bool signed;
  final Widget? below;

  const BigNumber({super.key, required this.label, required this.cents, this.signed = false, this.below});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: AppColors.textDim, fontSize: 14, fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        AnimatedMoney(
          cents,
          signed: signed,
          style: TextStyle(
            color: AppColors.text,
            fontSize: 40,
            fontWeight: FontWeight.w700,
            letterSpacing: -1.5,
            height: 1.1,
          ),
        ),
        if (below != null) ...[const SizedBox(height: 6), below!],
      ],
    );
  }
}

// Green/red change line, e.g. "▲ +2.666,10 € (8,4 %) diesen Monat".
class ChangeLabel extends StatelessWidget {
  final int cents;
  final double? percent;
  final String? suffix;

  const ChangeLabel({super.key, required this.cents, this.percent, this.suffix});

  @override
  Widget build(BuildContext context) {
    final up = cents >= 0;
    final color = up ? AppColors.primary : AppColors.error;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(up ? Icons.arrow_drop_up_rounded : Icons.arrow_drop_down_rounded, color: color, size: 24),
        Text(
          Money.signed(cents) + (percent != null ? ' (${Money.percent(percent!, digits: 2, signed: false)})' : ''),
          style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 14),
        ),
        if (suffix != null) ...[
          const SizedBox(width: 6),
          Text(suffix!, style: TextStyle(color: AppColors.textDim, fontSize: 14)),
        ],
      ],
    );
  }
}

// Round, softly tinted category icon used as the leading element of list rows.
class CategoryAvatar extends StatelessWidget {
  final String category;
  final bool isIncome;
  final double size;

  const CategoryAvatar(this.category, {super.key, required this.isIncome, this.size = 42});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isIncome ? AppColors.primary.withValues(alpha: 0.14) : AppColors.surfaceAlt,
        shape: BoxShape.circle,
      ),
      child: Icon(Categories.icon(category), color: isIncome ? AppColors.primary : AppColors.text, size: size * 0.48),
    );
  }
}
