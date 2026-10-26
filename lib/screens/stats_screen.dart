import 'package:flutter/material.dart';
import 'contracts_screen.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'dart:math' as math;
import '../services/db.dart';
import '../models/transaction.dart';
import '../utils/theme.dart';
import '../utils/money.dart';
import '../widgets/big_number.dart';
import '../services/insights_service.dart';
import '../widgets/tx_row.dart';
import '../widgets/segmented.dart';

// Monthly analysis as a section of the account screen (not scrollable on its own).
class StatsView extends StatefulWidget {
  const StatsView({super.key});

  @override
  State<StatsView> createState() => _StatsViewState();
}

class _StatsViewState extends State<StatsView> {
  // currently selected month for statistics
  late DateTime _month;

  // until the user picks a month, follow the latest month that has data
  bool _autoMonth = true;

  // which tab is active (0 = expenses, 1 = income)
  int _tab = 0;

  // highlighted donut slice, if any
  int? _slice;

  // month names for display
  static const _monthNames = [
    'Januar',
    'Februar',
    'März',
    'April',
    'Mai',
    'Juni',
    'Juli',
    'August',
    'September',
    'Oktober',
    'November',
    'Dezember'
  ];

  // short month names for the trend chart
  static const _shortMonths = ['Jan', 'Feb', 'Mär', 'Apr', 'Mai', 'Jun', 'Jul', 'Aug', 'Sep', 'Okt', 'Nov', 'Dez'];

  @override
  void initState() {
    super.initState();
    // start with current month
    _month = DateTime.now();
  }

  @override
  Widget build(BuildContext context) {
    // rebuild when transactions change in hive
    return ValueListenableBuilder<Box>(
      valueListenable: Hive.box('transactions').listenable(),
      builder: (_, __, ___) {
        // load all transactions once and aggregate in memory
        final all = DB.getTx();
        if (_autoMonth) _month = _latestMonthWithData(all);

        final tx = DB.inMonth(all, _month);
        final income = DB.sumOf(tx, isIncome: true);
        final expenses = DB.sumOf(tx, isIncome: false);
        final balance = income - expenses;

        // get category breakdown
        final data = DB.categoriesOf(tx, isIncome: _tab == 1);

        // color for charts (red for expenses, green for income)
        final color = _tab == 0 ? AppColors.error : AppColors.positive;

        // month-over-month expense insights
        final insights = InsightsService.forMonth(all, _month);

        // income and expenses of the last 6 months (oldest -> newest)
        final trend = <_MonthTotals>[];
        for (int i = 5; i >= 0; i--) {
          final m = DateTime(_month.year, _month.month - i);
          final mt = DB.inMonth(all, m);
          trend.add(_MonthTotals(m, DB.sumOf(mt, isIncome: true), DB.sumOf(mt, isIncome: false)));
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // month selector at top
            _monthSelector(),
            const SizedBox(height: 24),

            // show empty state or statistics
            if (tx.isEmpty)
              _emptyState()
            else ...[
              // overview card with balance
              _overviewCard(income, expenses, balance),
              const SizedBox(height: 24),

              // 6-month income vs expenses
              _trendCard(trend),
              const SizedBox(height: 24),

              // contracts and subscriptions found in the bookings
              const ContractsCard(),
              const SizedBox(height: 24),

              // automatic insights vs the previous month
              if (insights.isNotEmpty) ...[
                _insightsCard(insights),
                const SizedBox(height: 24),
              ],

              // tabs switch (expenses/ income)
              _tabSelector(),
              const SizedBox(height: 16),

              // pie chart (only if there is data)
              if (data.isNotEmpty) ...[
                _pieChart(data, tx),
                const SizedBox(height: 24),
              ],

              // list of categories with amounts
              _categoryList(data, color, tx),
            ],
          ],
        );
      },
    );
  }

  // the newest month that has transactions, or the current month
  DateTime _latestMonthWithData(List<Transaction> newestFirst) {
    final now = DateTime.now();
    if (newestFirst.isEmpty || DB.inMonth(newestFirst, now).isNotEmpty) return DateTime(now.year, now.month);
    final d = newestFirst.first.date;
    return DateTime(d.year, d.month);
  }

  void _selectMonth(DateTime m) {
    setState(() {
      _autoMonth = false;
      _slice = null;
      _month = DateTime(m.year, m.month);
    });
  }

  // widget to select month with arrow buttons
  Widget _monthSelector() {
    final now = DateTime.now();
    // not into the future
    final canGoForward = _month.year < now.year || (_month.year == now.year && _month.month < now.month);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // go to previous month
        IconButton(
          onPressed: () => _selectMonth(DateTime(_month.year, _month.month - 1)),
          icon: const Icon(Icons.chevron_left_rounded, color: AppColors.primary),
        ),
        // display current month and year
        Text(
          '${_monthNames[_month.month - 1]} ${_month.year}',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        IconButton(
          onPressed: canGoForward ? () => _selectMonth(DateTime(_month.year, _month.month + 1)) : null,
          icon: Icon(Icons.chevron_right_rounded, color: canGoForward ? AppColors.primary : AppColors.border),
        ),
      ],
    );
  }

  // paired bars of income (green) and expenses (red) for the last 6 months;
  // tapping a month selects it
  Widget _trendCard(List<_MonthTotals> months) {
    int maxValue = 1;
    for (final m in months) {
      maxValue = math.max(maxValue, math.max(m.income, m.expenses));
    }
    Widget bar(int value, Color color, bool selected) {
      return AnimatedContainer(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        width: 10,
        height: (value / maxValue * 80).clamp(3.0, 80.0),
        decoration: BoxDecoration(
          color: selected ? color : color.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(4),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text('Verlauf', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const Spacer(),
            _legendDot(AppColors.positive, 'Einnahmen'),
            const SizedBox(width: 12),
            _legendDot(AppColors.error, 'Ausgaben'),
          ]),
          const SizedBox(height: 16),
          SizedBox(
            height: 110,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final m in months)
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _selectMonth(m.month),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              bar(m.income, AppColors.positive, m.month == _month),
                              const SizedBox(width: 3),
                              bar(m.expenses, AppColors.error, m.month == _month),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(_shortMonths[m.month.month - 1],
                              style: TextStyle(
                                fontSize: 11,
                                color: m.month == _month ? AppColors.text : AppColors.textDim,
                                fontWeight: m.month == _month ? FontWeight.w600 : FontWeight.normal,
                              )),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(children: [
      Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(fontSize: 11, color: AppColors.textDim)),
    ]);
  }

  // card listing the automatic insights
  Widget _insightsCard(List<String> insights) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: const [
            Icon(Icons.lightbulb_outline, color: AppColors.warning, size: 20),
            SizedBox(width: 8),
            Text('Insights', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 12),
          for (final s in insights)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 6, right: 8),
                    child: Icon(Icons.circle, size: 6, color: AppColors.primary),
                  ),
                  Expanded(child: Text(s, style: const TextStyle(height: 1.4))),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // shown when no transactions exist for selected month
  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Icon(Icons.bar_chart, size: 64, color: AppColors.textDim),
            const SizedBox(height: 16),
            const Text('Keine Daten', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  // monthly balance with income and expenses below (cents)
  Widget _overviewCard(int income, int expenses, int balance) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Bilanz', style: TextStyle(color: AppColors.textDim, fontSize: 13)),
          const SizedBox(height: 2),
          AnimatedMoney(balance,
              signed: true,
              style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.8,
                  color: balance >= 0 ? AppColors.text : AppColors.error)),
          const SizedBox(height: 10),
          Wrap(spacing: 20, runSpacing: 6, children: [
            _miniStat(Icons.arrow_downward_rounded, 'Einnahmen', income, AppColors.positive),
            _miniStat(Icons.arrow_upward_rounded, 'Ausgaben', expenses, AppColors.error),
          ]),
        ],
      ),
    );
  }

  Widget _miniStat(IconData icon, String label, int cents, Color color) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 16, color: color),
      const SizedBox(width: 4),
      Text('$label ', style: TextStyle(color: AppColors.textDim, fontSize: 14)),
      Text(Money.format(cents), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
    ]);
  }

  // switch between expenses and income view
  Widget _tabSelector() {
    return Segmented(
      labels: const ['Ausgaben', 'Einnahmen'],
      index: _tab,
      onChanged: (i) => setState(() {
        _tab = i;
        _slice = null;
      }),
    );
  }

  // top 5 categories, the rest grouped as "Weitere"
  List<MapEntry<String, int>> _topEntries(Map<String, int> data) {
    final sorted = data.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final entries = sorted.take(5).toList();
    if (sorted.length > 5) {
      int otherSum = 0;
      for (final e in sorted.skip(5)) {
        otherSum += e.value;
      }
      entries.add(MapEntry('Weitere', otherSum));
    }
    return entries;
  }

  // the month's transactions of one category (or of the grouped rest)
  void _openCategory(String category, List<Transaction> monthTx, List<MapEntry<String, int>> entries) {
    final named = entries.map((e) => e.key).toSet();
    final list = monthTx
        .where((t) => t.isIncome == (_tab == 1))
        .where((t) => category == 'Weitere' ? !named.contains(t.category) : t.category == category)
        .toList();
    showTransactionsSheet(context,
        title: category, subtitle: '${_monthNames[_month.month - 1]} ${_month.year}', tx: list);
  }

  // donut chart: tap a slice to highlight it, tap it again to see its spending
  Widget _pieChart(Map<String, int> data, List<Transaction> monthTx) {
    final entries = _topEntries(data);
    int total = 0;
    for (final v in data.values) {
      total += v;
    }
    final sel = _slice != null && _slice! < entries.length ? _slice : null;

    void onTap(Offset local, double size) {
      final c = Offset(size / 2, size / 2);
      final d = local - c;
      // ignore taps in the hole or outside the ring
      if (d.distance < size * 0.25 || d.distance > size / 2) {
        setState(() => _slice = null);
        return;
      }
      // angle measured clockwise from the top
      var angle = math.atan2(d.dy, d.dx) + math.pi / 2;
      if (angle < 0) angle += 2 * math.pi;
      double acc = 0;
      for (int i = 0; i < entries.length; i++) {
        acc += entries[i].value / total * 2 * math.pi;
        if (angle <= acc) {
          HapticFeedback.selectionClick();
          if (sel == i) {
            _openCategory(entries[i].key, monthTx, entries);
          } else {
            setState(() => _slice = i);
          }
          return;
        }
      }
    }

    const size = 140.0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          GestureDetector(
            onTapUp: (d) => onTap(d.localPosition, size),
            child: SizedBox(
              height: size,
              width: size,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 700),
                    curve: Curves.easeOutCubic,
                    builder: (_, t, __) => CustomPaint(
                      size: const Size(size, size),
                      painter: _PiePainter(entries, total, sel, t, AppColors.surface),
                    ),
                  ),
                  // center label: selected slice or the total
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(sel == null ? 'Gesamt' : entries[sel].key,
                          style: TextStyle(fontSize: 10, color: AppColors.textDim), overflow: TextOverflow.ellipsis),
                      Text(Money.format(sel == null ? total : entries[sel].value),
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 20),
          // legend next to pie chart, tappable as well
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (int i = 0; i < entries.length; i++)
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => _openCategory(entries[i].key, monthTx, entries),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Opacity(
                        opacity: sel == null || sel == i ? 1 : 0.4,
                        child: Row(children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                                color: AppColors.chart[i % AppColors.chart.length], shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(entries[i].key,
                                style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
                          ),
                          Text('${(entries[i].value / total * 100).toStringAsFixed(0)} %',
                              style: TextStyle(fontSize: 12, color: AppColors.textDim)),
                        ]),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // list of all categories with amounts and progress bars
  Widget _categoryList(Map<String, int> data, Color color, List<Transaction> monthTx) {
    // show message if no data
    if (data.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Keine Daten', style: TextStyle(color: AppColors.textDim)),
        ),
      );
    }

    // sort by amount (highest first)
    final sorted = data.entries.toList();
    sorted.sort((a, b) => b.value.compareTo(a.value));

    // calculate total for percentages
    int total = 0;
    for (var entry in data.values) {
      total += entry;
    }

    // build category cards
    final categoryCards = <Widget>[];
    for (var entry in sorted) {
      final percent = entry.value / total;

      categoryCards.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Material(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _openCategory(entry.key, monthTx, const []),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // category name and amount
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(entry.key, style: const TextStyle(fontWeight: FontWeight.bold)),
                        Text(Money.format(entry.value), style: TextStyle(fontWeight: FontWeight.bold, color: color)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // progress bar showing percentage
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: percent,
                        backgroundColor: AppColors.bg,
                        valueColor: AlwaysStoppedAnimation(color),
                        minHeight: 6,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // percentage text
                    Text(Money.percent(percent * 100, signed: false),
                        style: TextStyle(fontSize: 12, color: AppColors.textDim)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // section title
        Text(
          _tab == 0 ? 'Ausgaben nach Kategorie' : 'Einnahmen nach Kategorie',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        // all category cards
        ...categoryCards,
      ],
    );
  }
}

// donut chart; the selected slice pops out, the others fade. [t] animates
// the sweep from 0 to 1 when the chart appears.
class _PiePainter extends CustomPainter {
  final List<MapEntry<String, int>> entries;
  final int total;
  final int? selected;
  final double t;
  final Color hole;

  _PiePainter(this.entries, this.total, this.selected, this.t, this.hole);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;
    final paint = Paint()..style = PaintingStyle.fill;

    // start angle at top
    double angle = -math.pi / 2;
    for (int i = 0; i < entries.length; i++) {
      final sweep = entries[i].value / total * 2 * math.pi * t;
      final color = AppColors.chart[i % AppColors.chart.length];
      paint.color = selected == null || selected == i ? color : color.withValues(alpha: 0.3);
      final r = selected == i ? radius + 4 : radius;
      canvas.drawArc(Rect.fromCircle(center: center, radius: r), angle, sweep, true, paint);
      angle += sweep;
    }
    // hole in the middle
    paint.color = hole;
    canvas.drawCircle(center, radius * 0.62, paint);
  }

  @override
  bool shouldRepaint(covariant _PiePainter old) =>
      old.selected != selected || old.t != t || old.entries != entries || old.hole != hole;
}

// income and expenses of one month (cents), for the trend chart
class _MonthTotals {
  final DateTime month;
  final int income;
  final int expenses;
  _MonthTotals(this.month, this.income, this.expenses);
}
