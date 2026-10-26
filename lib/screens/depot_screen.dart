import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'dart:math' as math;
import '../models/holding.dart';
import '../services/db.dart';
import '../services/price_service.dart';
import '../utils/theme.dart';
import '../utils/money.dart';
import '../widgets/interactive_chart.dart';
import '../widgets/instrument_avatar.dart';
import '../services/history.dart';
import 'add_holding_screen.dart';
import 'holding_detail_screen.dart';

class DepotScreen extends StatefulWidget {
  const DepotScreen({super.key});

  @override
  State<DepotScreen> createState() => _DepotScreenState();
}

class _DepotScreenState extends State<DepotScreen> {
  bool _refreshing = false;
  bool _historyLoading = false;
  String _range = '1M';
  List<int> _history = []; // portfolio value per day in cents, oldest first
  ChartPoint? _scrub;
  int? _slice; // highlighted allocation slice

  static const _ranges = {'1W': 7, '1M': 30, '3M': 90, '1J': 365};
  static const _periods = {
    '1W': 'in einer Woche',
    '1M': 'im letzten Monat',
    '3M': 'in 3 Monaten',
    '1J': 'im letzten Jahr',
  };

  int get _days => _ranges[_range]!;

  @override
  void initState() {
    super.initState();
    _loadHistory();
    // positions added later (demo, import, Parqet) need a fresh history
    Hive.box('holdings').listenable().addListener(_loadHistory);
  }

  @override
  void dispose() {
    Hive.box('holdings').listenable().removeListener(_loadHistory);
    super.dispose();
  }

  Future<void> _loadHistory() async {
    if (mounted) setState(() => _historyLoading = true);
    final days = _days;
    final cents = await PriceService.portfolioHistory(days: days);
    // ignore late results of a range that is no longer selected
    if (mounted && days == _days) {
      setState(() {
        _history = cents;
        _historyLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Box>(
      valueListenable: Hive.box('holdings').listenable(),
      builder: (_, __, ___) {
        final holdings = DB.getHoldings();
        final value = DB.portfolioValue();
        final invested = DB.portfolioInvested();
        final gain = DB.portfolioGain();

        return Scaffold(
          appBar: AppBar(
            title: const Text('Depot'),
            // lines up with "Konto" on the account tab (20 px page margin)
            titleSpacing: 20,
            actions: [
              // refresh live prices
              if (_refreshing)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)),
                )
              else if (holdings.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Kurse aktualisieren',
                  onPressed: _refreshPrices,
                ),
              IconButton(icon: const Icon(Icons.add), onPressed: () => _add()),
            ],
          ),
          body: holdings.isEmpty
              ? _emptyState()
              : RefreshIndicator(
                  // pull down to refresh the live prices
                  color: AppColors.primary,
                  onRefresh: _refreshPrices,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    children: [
                      ..._header(value, invested, gain),
                      const SizedBox(height: 28),
                      if (holdings.length > 1) ...[
                        _allocationCard(holdings, value),
                        const SizedBox(height: 28),
                      ],
                      const Text('Positionen', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      // same colour per position as in the allocation chart above
                      for (var i = 0, slot = 0; i < holdings.length; i++)
                        _holdingCard(holdings[i], holdings.length > 1 && holdings[i].valueCents > 0 ? slot++ : null),
                      // room for the floating navigation bar
                      const SizedBox(height: 110),
                    ],
                  ),
                ),
        );
      },
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.trending_up, size: 64, color: AppColors.textDim),
            const SizedBox(height: 16),
            const Text('Kein Depot', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Füge deine erste Position hinzu', style: TextStyle(color: AppColors.textDim)),
          ],
        ),
      ),
    );
  }

  // value with an interactive chart; scrubbing shows the value of each day
  List<Widget> _header(int value, int invested, int gain) {
    final today = DateTime.now();
    final points = [
      for (int i = 0; i < _history.length; i++)
        ChartPoint(DateTime(today.year, today.month, today.day - (_history.length - 1 - i)), _history[i]),
    ];
    final hasHistory = points.length >= 2;
    return [
      ChartHeader(
        label: 'Depotwert',
        cents: value,
        // change over the range, or overall when no history is available
        startCents: hasHistory ? points.first.cents : invested,
        period: hasHistory ? _periods[_range]! : 'gesamt',
        scrub: _scrub,
        startDate: hasHistory ? points.first.date : null,
      ),
      const SizedBox(height: 16),
      if (_historyLoading && !hasHistory)
        const SizedBox(height: 160, child: Center(child: CircularProgressIndicator(color: AppColors.primary)))
      else
        InteractiveChart(points: points, onScrub: (p) => setState(() => _scrub = p)),
      const SizedBox(height: 12),
      RangeSelector(
        labels: _ranges.keys.toList(),
        selected: _range,
        onChanged: (r) {
          setState(() => _range = r);
          _loadHistory();
        },
      ),
      const SizedBox(height: 16),
      // overall performance since buying
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
        child: Row(
          children: [
            Expanded(child: _stat('Investiert', Money.format(invested), AppColors.text)),
            Expanded(
              child: _stat('Gewinn/Verlust', Money.signed(gain), gain >= 0 ? AppColors.positive : AppColors.error),
            ),
            Expanded(
              child: _stat('Rendite', invested == 0 ? '–' : Money.percent(gain / invested * 100),
                  gain >= 0 ? AppColors.positive : AppColors.error),
            ),
          ],
        ),
      ),
    ];
  }

  Widget _stat(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: AppColors.textDim)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontWeight: FontWeight.w600, color: color), overflow: TextOverflow.ellipsis),
      ],
    );
  }

  // allocation donut + legend; tap a slice or a row to highlight it
  Widget _allocationCard(List<Holding> holdings, int totalValue) {
    final entries = <MapEntry<String, int>>[
      for (final h in holdings) if (h.valueCents > 0) MapEntry(h.name, h.valueCents)
    ];
    if (entries.isEmpty || totalValue == 0) return const SizedBox.shrink();
    final sel = _slice != null && _slice! < entries.length ? _slice : null;

    void select(int? i) {
      HapticFeedback.selectionClick();
      setState(() => _slice = i == sel ? null : i);
    }

    // which slice was tapped, measured clockwise from the top
    void onTap(Offset local, double size) {
      final d = local - Offset(size / 2, size / 2);
      if (d.distance < size * 0.27 || d.distance > size / 2) return select(null);
      var angle = math.atan2(d.dy, d.dx) + math.pi / 2;
      if (angle < 0) angle += 2 * math.pi;
      double acc = 0;
      for (int i = 0; i < entries.length; i++) {
        acc += entries[i].value / totalValue * 2 * math.pi;
        if (angle <= acc) return select(i);
      }
    }

    const size = 130.0;
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
                      painter: _DonutPainter(entries, totalValue, sel, t, AppColors.surface),
                    ),
                  ),
                  Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(sel == null ? 'Gesamt' : '${(entries[sel].value / totalValue * 100).toStringAsFixed(0)} %',
                        style: TextStyle(fontSize: 10, color: AppColors.textDim)),
                    Text(Money.format(sel == null ? totalValue : entries[sel].value),
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                  ]),
                ],
              ),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (int i = 0; i < entries.length; i++)
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => select(i),
                    child: Opacity(
                      opacity: sel == null || sel == i ? 1 : 0.4,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(children: [
                          Container(
                            width: 10, height: 10,
                            decoration: BoxDecoration(
                              color: AppColors.chart[i % AppColors.chart.length],
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: Text(entries[i].key,
                              style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
                          Text('${(entries[i].value / totalValue * 100).toStringAsFixed(0)} %',
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

  // single holding row in the same calm style as the transaction list
  Widget _holdingCard(Holding h, int? slot) {
    final color = h.isUp ? AppColors.positive : AppColors.error;

    return Dismissible(
      key: Key(h.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(color: AppColors.error, borderRadius: BorderRadius.circular(14)),
        child: const Icon(Icons.delete_rounded, color: Colors.white),
      ),
      confirmDismiss: (_) => _confirmDelete(h),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => HoldingDetailScreen(holding: h))),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              InstrumentAvatar(h.name, color: slot == null ? null : AppColors.chart[slot % AppColors.chart.length]),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(h.name,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text('${_trimShares(h.shares)} Stück${h.symbol.isNotEmpty ? ' · ${h.symbol}' : ''}',
                        style: TextStyle(fontSize: 13, color: AppColors.textDim),
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(Money.format(h.valueCents), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(Money.percent(h.gainPercent),
                      style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _trimShares(double v) {
    final s = v.toStringAsFixed(4);
    return s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '').replaceAll('.', ',');
  }

  // fetches the latest live prices for all holdings
  Future<void> _refreshPrices() async {
    setState(() => _refreshing = true);
    try {
      final result = await PriceService.refreshAll();
      _loadHistory(); // refresh the depot trend too
      if (mounted) {
        String msg;
        Color bg;
        if (result.failed == 0) {
          // every holding has a live source
          msg = result.updated > 0 ? '${result.updated} Kurse aktualisiert' : 'Kurse sind aktuell';
          bg = AppColors.surfaceAlt;
        } else if (result.live > 0) {
          // crypto refreshed; stocks/ETFs can't live-update in the browser
          msg = 'Krypto aktualisiert · Aktien nur am iPhone/mit Key live';
          bg = AppColors.surfaceAlt;
        } else {
          // nothing could be fetched live (only stocks, in the browser)
          msg = 'Aktien-Kurse brauchen einen Finnhub-Key oder das iPhone';
          bg = AppColors.warning;
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(duration: const Duration(milliseconds: 2800), content: Text(msg), backgroundColor: bg));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(duration: const Duration(milliseconds: 2800), content: Text('Fehler: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  void _add({Holding? holding}) async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => AddHoldingScreen(holding: holding)),
    );
    if (ok == true && mounted) {
      setState(() {});
      _loadHistory(); // include the new/changed position in the trend
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(duration: const Duration(milliseconds: 2800), 
        content: Text(holding == null ? 'Hinzugefügt' : 'Aktualisiert'),
      ));
    }
  }

  // deletes right away and offers an undo instead of asking first. Returning
  // false keeps the row in place until the box notifies, so the Dismissible
  // never lingers in the tree after being dismissed.
  Future<bool> _confirmDelete(Holding h) async {
    HapticFeedback.mediumImpact();
    await DB.deleteHolding(h.id);
    if (mounted) {
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(persist: false, duration: const Duration(seconds: 5), 
        content: Text('${h.name} gelöscht'),
        action: SnackBarAction(
          label: 'Rückgängig',
          textColor: AppColors.primary,
          onPressed: () => DB.addHolding(h),
        ),
      ));
    }
    return false;
  }
}

// donut chart painter; the selected slice pops out, the others fade.
// [t] animates the sweep from 0 to 1 when the chart appears.
class _DonutPainter extends CustomPainter {
  final List<MapEntry<String, int>> entries;
  final int total;
  final int? selected;
  final double t;
  final Color hole;
  _DonutPainter(this.entries, this.total, this.selected, this.t, this.hole);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;
    final paint = Paint()..style = PaintingStyle.fill;
    double angle = -math.pi / 2;

    for (int i = 0; i < entries.length; i++) {
      final sweep = (entries[i].value / total) * 2 * math.pi * t;
      final color = AppColors.chart[i % AppColors.chart.length];
      paint.color = selected == null || selected == i ? color : color.withValues(alpha: 0.3);
      final r = selected == i ? radius + 4 : radius;
      canvas.drawArc(Rect.fromCircle(center: center, radius: r), angle, sweep, true, paint);
      angle += sweep;
    }
    paint.color = hole;
    canvas.drawCircle(center, radius * 0.6, paint);
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.selected != selected || old.t != t || old.entries != entries || old.hole != hole;
}
