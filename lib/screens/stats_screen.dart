import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'dart:math' as math;
import '../services/db.dart';
import '../utils/theme.dart';
import '../utils/money.dart';
import '../widgets/hero_card.dart';
import '../services/insights_service.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});
  
  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  // currently selected month for statistics
  late DateTime _month;
  
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
        // load data
        final tx = DB.getTxByMonth(_month);
        final income = DB.income(month: _month);
        final expenses = DB.expenses(month: _month);
        final balance = income - expenses;
        
        // get category breakdown
        final data = DB.byCategory(month: _month, isIncome: _tab == 1);
        
        // color for charts (red for expenses, green for income)
        final color = _tab == 0 ? AppColors.error : AppColors.primary;

        // month-over-month expense insights
        final lastMonth = DateTime(_month.year, _month.month - 1);
        final insights = InsightsService.generate(
          thisByCat: DB.byCategory(month: _month, isIncome: false),
          lastByCat: DB.byCategory(month: lastMonth, isIncome: false),
          thisExpenses: expenses,
          lastExpenses: DB.expenses(month: lastMonth),
        );

        // 6-month net balance trend (oldest -> newest)
        final trend = <int>[];
        final trendLabels = <String>[];
        for (int i = 5; i >= 0; i--) {
          final m = DateTime(_month.year, _month.month - i);
          trend.add(DB.income(month: m) - DB.expenses(month: m));
          trendLabels.add(_shortMonths[m.month - 1]);
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

                // 6-month net trend
                _trendCard(trend, trendLabels),
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

  // widget to select month with arrow buttons
  Widget _monthSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // go to previous month
          IconButton(
            onPressed: () => setState(() => _month = DateTime(_month.year, _month.month - 1)),
            icon: const Icon(Icons.chevron_left, color: AppColors.primary),
          ),
          // display current month and year
          Text(
            '${_monthNames[_month.month - 1]} ${_month.year}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          // button to go to next month (not into the future)
          IconButton(
            onPressed: () {
              final now = DateTime.now();
              // only allow if not already at current month
              bool canGoForward = _month.year < now.year || 
                                  (_month.year == now.year && _month.month < now.month);
              if (canGoForward) {
                setState(() => _month = DateTime(_month.year, _month.month + 1));
              }
            },
            icon: const Icon(Icons.chevron_right, color: AppColors.primary),
          ),
        ],
      ),
    );
  }

  // bar chart of the net balance over the last 6 months
  Widget _trendCard(List<int> nets, List<String> labels) {
    int maxAbs = 0;
    for (final n in nets) {
      if (n.abs() > maxAbs) maxAbs = n.abs();
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Verlauf (6 Monate)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          SizedBox(
            height: 110,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (int i = 0; i < nets.length; i++)
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Container(
                          width: 18,
                          height: maxAbs == 0 ? 4.0 : (nets[i].abs() / maxAbs * 72).clamp(4.0, 72.0),
                          decoration: BoxDecoration(
                            color: nets[i] >= 0 ? AppColors.primary : AppColors.error,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(labels[i], style: TextStyle(fontSize: 10, color: AppColors.textDim)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
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

  // gradient hero card showing monthly balance, income and expenses (cents)
  Widget _overviewCard(int income, int expenses, int balance) {
    return HeroCard(
      label: 'Monatsbilanz',
      value: Money.signed(balance),
      gradient: AppColors.heroGreen,
      child: Row(
        children: [
          HeroPill(icon: Icons.south_west, label: 'Einnahmen', value: Money.format(income)),
          const SizedBox(width: 10),
          HeroPill(icon: Icons.north_east, label: 'Ausgaben', value: Money.format(expenses)),
        ],
      ),
    );
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
