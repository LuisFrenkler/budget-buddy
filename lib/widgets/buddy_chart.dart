// The small charts Buddy shows under an answer: months (income against
// spending), categories (where the money went), a savings plan (the way
// to a target, month by month) and payslips (gross, net, deductions).
// Plain bars, the app's colours, no library.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../screens/account_screen.dart';
import '../services/buddy_proposals.dart';
import '../services/db.dart';
import '../services/history.dart';
import '../services/ledger_busy.dart';
import '../services/money_accounts.dart';
import '../services/onboarding_service.dart';
import '../services/price_service.dart';
import '../utils/money.dart';
import '../utils/motion.dart';
import '../utils/theme.dart';
import '../l10n/l10n.dart';

class BuddyChartCard extends StatelessWidget {
  final BuddyChart chart;
  const BuddyChartCard(this.chart, {super.key});

  // what the chart shows, in one sentence for a screen reader
  static String describe(BuddyChart c) {
    final rows = c.rows.take(8);
    final parts = switch (c.kind) {
      ChartKind.months => [
          for (final r in rows)
            tr('{x}: Einnahmen {y}, Ausgaben {z}', {'x': r.label, 'y': Money.format(r.a), 'z': Money.format(r.b)})
        ],
      ChartKind.categories => [for (final r in rows) '${r.label} ${Money.format(r.a)}'],
      ChartKind.plan => rows.isEmpty
          ? <String>[]
          : [
              tr('nach {x} Monaten {y} von {z}',
                  {'x': c.rows.length, 'y': Money.format(c.rows.last.a), 'z': Money.format(c.rows.last.b)})
            ],
      ChartKind.payslip => [
          for (final r in rows)
            tr('{x}: Brutto {y}, Netto {z}, Abzüge {a}', {
              'x': r.label,
              'y': Money.format(r.a),
              'z': Money.format(r.b),
              'a': Money.format(_deduct(r)),
            })
        ],
    };
    return tr('Diagramm {x}: {y}', {'x': c.title, 'y': parts.join('; ')});
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: describe(chart),
      excludeSemantics: true,
      child: Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: _box,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(chart.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        const SizedBox(height: 12),
        switch (chart.kind) {
          ChartKind.months => _months(),
          ChartKind.categories => _categories(),
          ChartKind.plan => _plan(),
          ChartKind.payslip => _payslip(),
        },
      ]),
      ),
    );
  }

  static BoxDecoration get _box => BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.hairline),
      );

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

  static int _deduct(({String label, int a, int b}) r) => (r.a - r.b).clamp(0, r.a);

  Widget _payslip() {
    final max = chart.rows.fold<int>(1, (m, r) => [m, r.a, r.b, _deduct(r)].reduce((x, y) => x > y ? x : y));
    String line(({String label, int a, int b}) r) => tr('{x}: Brutto {y}, Netto {z}, Abzüge {a}', {
          'x': r.label,
          'y': Money.format(r.a),
          'z': Money.format(r.b),
          'a': Money.format(_deduct(r)),
        });
    return Column(children: [
      SizedBox(
        height: 96,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (final r in chart.rows)
            Expanded(
              child: Semantics(
                label: line(r),
                child: Row(crossAxisAlignment: CrossAxisAlignment.end, mainAxisAlignment: MainAxisAlignment.center, children: [
                  _bar(r.a / max, AppColors.textDim.withValues(alpha: 0.35), 6),
                  const SizedBox(width: 2),
                  _bar(r.b / max, _copper, 6),
                  const SizedBox(width: 2),
                  _bar(_deduct(r) / max, AppColors.textDim.withValues(alpha: 0.8), 6),
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
      Wrap(spacing: 14, runSpacing: 4, children: [
        _key(AppColors.textDim.withValues(alpha: 0.35), tr('Brutto')),
        _key(_copper, tr('Netto')),
        _key(AppColors.textDim.withValues(alpha: 0.8), tr('Abzüge')),
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

// where a question was asked: its answer starts with that place's chart
enum AskPlace { overview, account, depot }

// a place as one line and one number
class PlaceChart {
  // read out instead of the drawing
  final String label;
  final String number;
  final List<int> cents;
  const PlaceChart(this.label, this.number, this.cents);

  // null when the place has nothing to draw, or amounts are hidden
  static Future<PlaceChart?> of(AskPlace place) async {
    if (Money.masked) return null;
    if (place == AskPlace.depot) {
      final cents = await PriceService.portfolioHistory(days: 30);
      if (_flat(cents)) return null;
      final change = Money.signed(DB.portfolioValue() - cents.first);
      return PlaceChart('${tr('Depot')} $change ${tr('in 30 Tagen')}', change, cents);
    }
    if (!OnboardingService.balanceKnown) return null;
    final all = DB.getTx();
    // Konto draws the chosen account, Überblick all of them together
    final chosen = place == AskPlace.account ? MoneyAccounts.byId(AccountScreen.selected.value) : null;
    final one = chosen != null || !MoneyAccounts.several;
    final account = chosen ?? MoneyAccounts.main;
    final tx = one ? MoneyAccounts.bookingsOf(account.id, all) : all;
    final opening = one ? MoneyAccounts.openingOf(account) : MoneyAccounts.openingTotal;
    final live = DB.balanceOf(tx) + opening;
    final balance = MoneyAccounts.several && one ? live : LedgerBusy.cashOr(live);
    final now = DateTime.now();
    final cents = [
      for (final p in History.dailyBalance(tx, from: DateTime(now.year, now.month, now.day - 91), opening: opening))
        p.cents
    ];
    if (_flat(cents)) return null;
    return PlaceChart('${tr('Kontostand')} ${Money.format(balance)}', Money.format(balance), cents);
  }

  static bool _flat(List<int> v) => v.length < 2 || v.every((c) => c == v.first);
}

class PlaceChartCard extends StatelessWidget {
  final PlaceChart chart;
  // arrives with a streamed answer: a fade, no drawing that delays reading
  final bool fade;
  const PlaceChartCard(this.chart, {super.key, this.fade = false});

  @override
  Widget build(BuildContext context) {
    final up = chart.cents.last >= chart.cents.first;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: fade ? Motion.base : Duration.zero,
      curve: Motion.color,
      builder: (_, t, child) => Opacity(opacity: t, child: child),
      child: Semantics(
        container: true,
        image: true,
        label: chart.label,
        excludeSemantics: true,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BuddyChartCard._box,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(chart.number, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 20)),
            const SizedBox(height: 10),
            SizedBox(
              height: 64,
              width: double.infinity,
              child: CustomPaint(painter: _LinePainter(chart.cents, up ? BuddyChartCard._copper : AppColors.error)),
            ),
          ]),
        ),
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  final List<int> cents;
  final Color color;
  const _LinePainter(this.cents, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    var lo = cents.reduce(math.min).toDouble(), hi = cents.reduce(math.max).toDouble();
    // at least 4 % of the value as range, like the screens' own charts
    final span = math.max(hi.abs(), lo.abs()) * 0.04;
    if (hi - lo < span) {
      final mid = (hi + lo) / 2;
      hi = mid + span / 2;
      lo = mid - span / 2;
    }
    const pad = 2.0;
    final h = size.height - pad * 2, dx = size.width / (cents.length - 1);
    final line = Path();
    for (var i = 0; i < cents.length; i++) {
      final y = pad + h - (cents[i] - lo) / (hi - lo) * h;
      i == 0 ? line.moveTo(0, y) : line.lineTo(i * dx, y);
    }
    canvas.drawPath(
        line,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round
          ..color = color);
  }

  @override
  bool shouldRepaint(_LinePainter old) => old.cents != cents || old.color != color;
}
