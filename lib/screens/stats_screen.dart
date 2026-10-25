import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'dart:math' as math;
import '../services/db.dart';
import '../models/transaction.dart';
import '../utils/theme.dart';
import '../utils/money.dart';
import '../widgets/big_number.dart';
import '../services/insights_service.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});
  
  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  // currently selected month for statistics
  late DateTime _month;

  // until the user picks a month, follow the latest month that has data
  bool _autoMonth = true;
  
  // which tab is active (0 = expenses, 1 = income)
  int _tab = 0;

  // month names for display
  static const _monthNames = ['Januar', 'Februar', 'März', 'April', 'Mai', 'Juni',
                              'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember'];

  // short month names for the trend chart
  static const _shortMonths = ['Jan', 'Feb', 'Mär', 'Apr', 'Mai', 'Jun',
                               'Jul', 'Aug', 'Sep', 'Okt', 'Nov', 'Dez'];

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
        final color = _tab == 0 ? AppColors.error : AppColors.primary;

        // month-over-month expense insights
        final last = DB.inMonth(all, DateTime(_month.year, _month.month - 1));
        final insights = InsightsService.generate(
          thisByCat: DB.categoriesOf(tx, isIncome: false),
          lastByCat: DB.categoriesOf(last, isIncome: false),
          thisExpenses: expenses,
          lastExpenses: DB.sumOf(last, isIncome: false),
        );

        // income and expenses of the last 6 months (oldest -> newest)
        final trend = <_MonthTotals>[];
        for (int i = 5; i >= 0; i--) {
          final m = DateTime(_month.year, _month.month - i);
          final mt = DB.inMonth(all, m);
          trend.add(_MonthTotals(m, DB.sumOf(mt, isIncome: true), DB.sumOf(mt, isIncome: false)));
        }

        return Scaffold(
          appBar: AppBar(title: const Text('Statistiken')),
          body: ListView(
            padding: const EdgeInsets.all(16),
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
                  _pieChart(data),
                  const SizedBox(height: 24),
                ],
                
                // list of categories with amounts
                _categoryList(data, color),
              ],
            ],
          ),
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
          icon: Icon(Icons.chevron_right_rounded,
              color: canGoForward ? AppColors.primary : AppColors.border),
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
            _legendDot(AppColors.primary, 'Einnahmen'),
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
                              bar(m.income, AppColors.primary, m.month == _month),
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

  // big monthly balance with income and expenses below (cents)
  Widget _overviewCard(int income, int expenses, int balance) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: BigNumber(
        label: 'Monatsbilanz',
        cents: balance,
        signed: true,
        below: Row(children: [
          _miniStat(Icons.arrow_downward_rounded, 'Einnahmen', income, AppColors.primary),
          const SizedBox(width: 20),
          _miniStat(Icons.arrow_upward_rounded, 'Ausgaben', expenses, AppColors.error),
        ]),
      ),
    );
  }

  Widget _miniStat(IconData icon, String label, int cents, Color color) {
    return Row(children: [
      Icon(icon, size: 16, color: color),
      const SizedBox(width: 4),
      Text('$label ', style: TextStyle(color: AppColors.textDim, fontSize: 14)),
      Text(Money.format(cents), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
    ]);
  }

  // tab buttons to switch between expenses and income view
  Widget _tabSelector() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          _tabButton('Ausgaben', 0),
          _tabButton('Einnahmen', 1),
        ],
      ),
    );
  }

  // single tab button
  Widget _tabButton(String label, int index) {
    final isActive = _tab == index;
    
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tab = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isActive ? AppColors.primary.withValues(alpha: 0.15) : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: isActive ? FontWeight.bold : null,
              color: isActive ? AppColors.primary : AppColors.textDim,
            ),
          ),
        ),
      ),
    );
  }

  // pie chart showing category distribution (CustomPainter)
  Widget _pieChart(Map<String, int> data) {
    // sort categories by amount (highest first)
    final sorted = data.entries.toList();
    sorted.sort((a, b) => b.value.compareTo(a.value));

    // take top 5 categories
    final entries = <MapEntry<String, int>>[];
    for (int i = 0; i < sorted.length && i < 5; i++) {
      entries.add(sorted[i]);
    }

    // if there are more than 5 categories, group the rest as "Sonstiges"
    if (sorted.length > 5) {
      int otherSum = 0;
      for (int i = 5; i < sorted.length; i++) {
        otherSum += sorted[i].value;
      }
      entries.add(MapEntry('Sonstiges', otherSum));
    }

    // calculate total for percentages
    int total = 0;
    for (var entry in data.values) {
      total += entry;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          // the pie chart itself
          SizedBox(
            height: 120,
            width: 120,
            child: CustomPaint(painter: _PiePainter(entries, total)),
          ),
          const SizedBox(width: 24),
          // legend next to pie chart
          Expanded(
            child: _buildLegend(entries, total),
          ),
        ],
      ),
    );
  }

  // builds the legend for the pie chart
  Widget _buildLegend(List<MapEntry<String, int>> entries, int total) {
    final legendItems = <Widget>[];
    
    for (int i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final percent = (entry.value / total * 100).toStringAsFixed(0);
      
      legendItems.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              // color dot
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: AppColors.chart[i % AppColors.chart.length],
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              // category name
              Expanded(
                child: Text(entry.key, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
              ),
              // percentage
              Text('$percent%', style: TextStyle(fontSize: 12, color: AppColors.textDim)),
            ],
          ),
        ),
      );
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: legendItems,
    );
  }

  // list of all categories with amounts and progress bars
  Widget _categoryList(Map<String, int> data, Color color) {
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
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
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
              Text(Money.percent(percent * 100, signed: false), style: TextStyle(fontSize: 12, color: AppColors.textDim)),
            ],
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

// CustomPainter class to draw the pie chart
class _PiePainter extends CustomPainter {
  // list of categories with amounts (in cents)
  final List<MapEntry<String, int>> entries;
  // total of all amounts (for calculating percentages)
  final int total;
  
  _PiePainter(this.entries, this.total);

  @override
  void paint(Canvas canvas, Size size) {
    // center point of the pie chart
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    
    // paint object for drawing
    final paint = Paint();
    paint.style = PaintingStyle.fill;
    
    // start angle at top
    double currentAngle = -math.pi / 2;

    // draw each pie segment
    for (int i = 0; i < entries.length; i++) {
      // calculate how big this segment is
      final sweepAngle = (entries[i].value / total) * 2 * math.pi;
      
      // set color for this segment
      paint.color = AppColors.chart[i % AppColors.chart.length];

      // pie segment
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        currentAngle,
        sweepAngle,
        true,
        paint,
      );

      currentAngle += sweepAngle;
    }
    
    // draw a circle in the middle
    paint.color = AppColors.surface;
    canvas.drawCircle(center, radius * 0.5, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}

// income and expenses of one month (cents), for the trend chart
class _MonthTotals {
  final DateTime month;
  final int income;
  final int expenses;
  _MonthTotals(this.month, this.income, this.expenses);
}
