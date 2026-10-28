import 'package:flutter/material.dart';
import '../utils/brands.dart';
import '../services/settings_service.dart';
import '../utils/money.dart';
import '../utils/theme.dart';

// A money amount that glides from the previous value (not always from €0).
// With animate = false it follows changes instantly (e.g. while scrubbing).
class AnimatedMoney extends StatefulWidget {
  final int cents;
  final TextStyle style;
  final bool signed;
  final bool animate;

  const AnimatedMoney(this.cents, {super.key, required this.style, this.signed = false, this.animate = true});

  @override
  State<AnimatedMoney> createState() => _AnimatedMoneyState();
}

class _AnimatedMoneyState extends State<AnimatedMoney> {
  late int _from;

  @override
  void initState() {
    super.initState();
    _from = widget.cents; // first paint: no fake count-up from zero
  }

  @override
  void didUpdateWidget(covariant AnimatedMoney old) {
    super.didUpdateWidget(old);
    if (old.cents != widget.cents) _from = old.cents;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: Settings.hideAmounts,
      builder: (_, hidden, __) => hidden
          ? Text(Money.hidden, style: widget.style)
          : TweenAnimationBuilder<double>(
              key: ValueKey(widget.cents),
              tween: Tween(begin: _from.toDouble(), end: widget.cents.toDouble()),
              duration: widget.animate ? const Duration(milliseconds: 500) : Duration.zero,
              curve: Curves.easeOutCubic,
              builder: (_, v, __) {
                final c = v.round();
                return Text(widget.signed ? Money.signed(c) : Money.format(c),
                    style: widget.style.copyWith(fontFeatures: const [FontFeature.tabularFigures()]));
              },
            ),
    );
  }
}

// The large headline number at the top of a screen: a quiet label, the big
// animated amount and optional content below (e.g. a ChangeLabel).
class BigNumber extends StatelessWidget {
  final String label;
  final int cents;
  final bool signed;
  final bool animate;
  final Widget? below;

  const BigNumber({
    super.key,
    required this.label,
    required this.cents,
    this.signed = false,
    this.animate = true,
    this.below,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                color: AppColors.textDim, fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.2)),
        const SizedBox(height: 6),
        AnimatedMoney(
          cents,
          signed: signed,
          animate: animate,
          style: TextStyle(
            color: AppColors.text,
            fontSize: 44,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.8,
            height: 1.05,
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
    return ValueListenableBuilder<bool>(
      valueListenable: Settings.hideAmounts,
      builder: (_, hidden, __) {
        // privacy: no green/red direction cue over the shoulder
        final color = hidden ? AppColors.textDim : (up ? AppColors.positive : AppColors.error);
        final pct = percent != null ? Money.percent(percent!, digits: 2, signed: hidden) : null;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(up ? Icons.arrow_drop_up_rounded : Icons.arrow_drop_down_rounded, color: color, size: 24),
            Text(
              hidden ? (pct ?? Money.hidden) : Money.signed(cents) + (pct != null ? ' ($pct)' : ''),
              style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 14),
            ),
            if (suffix != null) ...[
              const SizedBox(width: 6),
              Flexible(
                child: Text(suffix!,
                    style: TextStyle(color: AppColors.textDim, fontSize: 14), overflow: TextOverflow.ellipsis),
              ),
            ],
          ],
        );
      },
    );
  }
}

// Round avatar leading list rows: a known merchant in its brand colour
// (from [merchant], e.g. the booking note), otherwise the category icon
// tinted in the category's colour.
class CategoryAvatar extends StatelessWidget {
  final String category;
  final bool isIncome;
  final double size;
  final String? merchant;

  const CategoryAvatar(this.category, {super.key, required this.isIncome, this.size = 42, this.merchant});

  @override
  Widget build(BuildContext context) {
    final brand = Brands.of(merchant);
    if (brand != null) return BrandAvatar(brand, size: size);
    final color = Categories.color(category);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.16), shape: BoxShape.circle),
      child: Icon(Categories.icon(category), color: color, size: size * 0.48),
    );
  }
}
