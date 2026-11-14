// The small charts Buddy shows under an answer: months (income against
// spending), categories (where the money went) and a savings plan (the way
// to a target, month by month). Plain bars, the app's colours, no library.
import 'package:flutter/material.dart';

import '../services/buddy_proposals.dart';
import '../utils/money.dart';
import '../utils/theme.dart';
import '../l10n/l10n.dart';

class BuddyChartCard extends StatelessWidget {
  final BuddyChart chart;
  const BuddyChartCard(this.chart, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(chart.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        const SizedBox(height: 12),
        switch (chart.kind) {
          ChartKind.months => _months(),
          ChartKind.categories => _categories(),
          ChartKind.plan => _plan(),
        },
      ]),
    );
  }

  static Color get _copper => ThemeController.isDark.value ? const Color(0xFFF4B98A) : AppColors.brand;

  Widget _months() {
    final max = chart.rows.fold<int>(1, (m, r) => [m, r.a, r.b].reduce((x, y) => x > y ? x : y));
    return Column(children: [
      SizedBox(
        height: 96,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (final r in chart.rows)
            Expanded(
              child: Semantics(
                label: tr('{x}: Einnahmen {y}, Ausgaben {z}', {'x': r.label, 'y': Money.format(r.a), 'z': Money.format(r.b)}),
                child: Row(crossAxisAlignment: CrossAxisAlignment.end, mainAxisAlignment: MainAxisAlignment.center, children: [
                  _bar(r.a / max, AppColors.textDim.withValues(alpha: 0.35), 9),
                  const SizedBox(width: 3),
                  _bar(r.b / max, _copper, 9),
                ]),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 6),
      Row(children: [
        for (final r in chart.rows)
          Expanded(
              child: Text(r.label,
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: AppColors.textDim))),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        _key(AppColors.textDim.withValues(alpha: 0.35), tr('Einnahmen')),
        const SizedBox(width: 14),
        _key(_copper, tr('Ausgaben')),
      ]),
    ]);
  }

  Widget _categories() {
    final max = chart.rows.fold<int>(1, (m, r) => r.a > m ? r.a : m);
    return Column(children: [
      for (final r in chart.rows)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            SizedBox(
                width: 96,
                child: Text(r.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
            Expanded(
              child: LayoutBuilder(
                builder: (_, c) => Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    width: (c.maxWidth * r.a / max).clamp(4.0, c.maxWidth),
                    height: 10,
                    decoration: BoxDecoration(color: _copper, borderRadius: BorderRadius.circular(5)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(Money.format(r.a), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          ]),
        ),
    ]);
  }

  Widget _plan() {
    final target = chart.rows.isEmpty ? 1 : chart.rows.first.b;
    return Column(children: [
      SizedBox(
        height: 72,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (var i = 0; i < chart.rows.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: _bar(chart.rows[i].a / target,
                    i == chart.rows.length - 1 ? _copper : _copper.withValues(alpha: 0.35), double.infinity,
                    height: 72),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 6),
      Row(children: [
        for (final r in chart.rows)
          Expanded(
              child: Text(r.label,
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: AppColors.textDim))),
      ]),
    ]);
  }

  Widget _bar(double share, Color color, double width, {double height = 96}) => Container(
        width: width,
        height: (share.clamp(0.04, 1.0)) * height,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(5)),
      );

  Widget _key(Color c, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 11.5, color: AppColors.textDim)),
      ]);
}
