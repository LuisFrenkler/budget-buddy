import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'dart:math' as math;
import '../models/holding.dart';
import '../services/db.dart';
import '../services/price_service.dart';
import '../utils/theme.dart';
import '../utils/money.dart';
import '../widgets/hero_card.dart';
import '../widgets/line_chart.dart';
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
  int _days = 30;
  List<double> _series = []; // portfolio value history in euros

  static const _ranges = {'7T': 7, '1M': 30, '3M': 90, '1J': 365};

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    if (mounted) setState(() => _historyLoading = true);
    final cents = await PriceService.portfolioHistory(days: _days);
    if (mounted) {
      setState(() {
        _series = cents.map((c) => c / 100).toList();
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
          floatingActionButton: FloatingActionButton.extended(
            heroTag: 'fab_depot',
            onPressed: () => _add(),
            icon: const Icon(Icons.add),
            label: const Text('Position'),
          ),
          body: holdings.isEmpty
              ? _emptyState()
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _overviewCard(value, invested, gain),
                    const SizedBox(height: 24),
                    _historyCard(),
                    const SizedBox(height: 24),
                    if (holdings.length > 1) ...[
                      _allocationCard(holdings, value),
                      const SizedBox(height: 24),
                    ],
                    const Text('Positionen',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    ...holdings.map(_holdingCard),
                    const SizedBox(height: 80),
                  ],
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

  // top gradient hero: total value, gain/loss pill and invested amount
  Widget _overviewCard(int value, int invested, int gain) {
    final up = gain >= 0;
    final percent = invested == 0 ? 0.0 : gain / invested * 100;
    final pct = Money.percent(percent, digits: 2);

    return HeroCard(
      label: 'Depotwert',
      value: Money.format(value),
      gradient: AppColors.heroBlue,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(up ? Icons.trending_up : Icons.trending_down, color: Colors.white, size: 18),
                  const SizedBox(width: 6),
                  Text('${Money.signed(gain)} · $pct',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text('Investiert: ${Money.format(invested)}',
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }

  // portfolio value over the selected period, with % / € change + range selector
  Widget _historyCard() {
    final hasData =
        _series.length >= 2 && _series.reduce(math.max) != _series.reduce(math.min);
    double pct = 0;
    int changeCents = 0;
    bool up = true;
    if (hasData) {
      final first = _series.first;
      final last = _series.last;
      up = last >= first;
      pct = first != 0 ? (last - first) / first * 100 : 0;
      changeCents = ((last - first) * 100).round();
    }
    final color = up ? AppColors.primary : AppColors.error;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Depot-Verlauf',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              if (hasData)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(up ? Icons.trending_up : Icons.trending_down, color: color, size: 16),
                    const SizedBox(width: 4),
                    Text(Money.percent(pct),
                        style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
                  ]),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_historyLoading)
            const SizedBox(
                height: 130,
                child: Center(child: CircularProgressIndicator(color: AppColors.primary)))
          else if (hasData) ...[
            LineChart(_series, color: color, height: 130),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Veränderung (${_rangeLabel()})',
                    style: TextStyle(fontSize: 12, color: AppColors.textDim)),
                Text(Money.signed(changeCents),
                    style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.bold)),
              ],
            ),
          ] else
            SizedBox(
              height: 80,
              child: Center(
                child: Text('Noch kein Verlauf verfügbar',
                    style: TextStyle(color: AppColors.textDim)),
              ),
            ),
          const SizedBox(height: 12),
          Row(children: [for (final e in _ranges.entries) _rangeChip(e.key, e.value)]),
        ],
      ),
    );
  }

  String _rangeLabel() => _ranges.entries
      .firstWhere((e) => e.value == _days, orElse: () => const MapEntry('', 0))
      .key;

  Widget _rangeChip(String label, int days) {
    final active = _days == days;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () {
          if (_days == days) return;
          setState(() => _days = days);
          _loadHistory();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: active ? AppColors.primary.withValues(alpha: 0.15) : AppColors.bg,
            borderRadius: BorderRadius.circular(10),
            border: active ? Border.all(color: AppColors.primary) : null,
          ),
          child: Text(label,
              style: TextStyle(
                  color: active ? AppColors.primary : AppColors.textDim,
                  fontWeight: active ? FontWeight.bold : null,
                  fontSize: 13)),
        ),
      ),
    );
  }

  // allocation donut + legend by holding value
  Widget _allocationCard(List<Holding> holdings, int totalValue) {
    final entries = <MapEntry<String, int>>[
      for (final h in holdings) if (h.valueCents > 0) MapEntry(h.name, h.valueCents)
    ];
    if (entries.isEmpty || totalValue == 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          SizedBox(
            height: 120, width: 120,
            child: CustomPaint(painter: _DonutPainter(entries, totalValue)),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (int i = 0; i < entries.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(children: [
                      Container(
                        width: 12, height: 12,
                        decoration: BoxDecoration(
                          color: AppColors.chart[i % AppColors.chart.length],
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(entries[i].key,
                          style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
                      Text('${(entries[i].value / totalValue * 100).toStringAsFixed(0)}%',
                          style: TextStyle(fontSize: 12, color: AppColors.textDim)),
                    ]),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // single holding row
  Widget _holdingCard(Holding h) {
    final up = h.isUp;
    final color = up ? AppColors.primary : AppColors.error;
    final emoji = AssetTypes.list.firstWhere(
        (t) => t['name'] == h.type, orElse: () => {'emoji': '💎'})['emoji']!;

    return Dismissible(
      key: Key(h.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(color: AppColors.error, borderRadius: BorderRadius.circular(12)),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) => _confirmDelete(h),
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => HoldingDetailScreen(holding: h))),
          leading: CircleAvatar(
            backgroundColor: AppColors.bg,
            child: Text(emoji, style: const TextStyle(fontSize: 20)),
          ),
          title: Text(h.name),
          subtitle: Text('${_trimShares(h.shares)} Stück'
              '${h.symbol.isNotEmpty ? ' · ${h.symbol}' : ''}'),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(Money.format(h.valueCents), style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(Money.percent(h.gainPercent),
                  style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
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
          bg = AppColors.primary;
        } else if (result.live > 0) {
          // crypto refreshed; stocks/ETFs can't live-update in the browser
          msg = 'Krypto aktualisiert · Aktien nur am iPhone/mit Key live';
          bg = AppColors.primary;
        } else {
          // nothing could be fetched live (only stocks, in the browser)
          msg = 'Aktien-Kurse brauchen einen Finnhub-Key oder das iPhone';
          bg = AppColors.warning;
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: bg));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e'), backgroundColor: AppColors.error),
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(holding == null ? 'Hinzugefügt' : 'Aktualisiert'),
        backgroundColor: AppColors.primary,
      ));
    }
  }

  Future<bool> _confirmDelete(Holding h) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Position löschen?'),
        content: Text(h.name),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Nein')),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('Ja', style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (confirmed == true) {
      await DB.deleteHolding(h.id);
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${h.name} gelöscht'),
          action: SnackBarAction(
            label: 'Rückgängig',
            textColor: AppColors.primary,
            onPressed: () => DB.addHolding(h),
          ),
        ));
      }
    }
    return false;
  }
}

// donut chart painter (a pie with a hole in the middle)
class _DonutPainter extends CustomPainter {
  final List<MapEntry<String, int>> entries;
  final int total;
  _DonutPainter(this.entries, this.total);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final paint = Paint()..style = PaintingStyle.fill;
    double angle = -math.pi / 2;

    for (int i = 0; i < entries.length; i++) {
      final sweep = (entries[i].value / total) * 2 * math.pi;
      paint.color = AppColors.chart[i % AppColors.chart.length];
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius), angle, sweep, true, paint);
      angle += sweep;
    }
    paint.color = AppColors.surface;
    canvas.drawCircle(center, radius * 0.55, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
