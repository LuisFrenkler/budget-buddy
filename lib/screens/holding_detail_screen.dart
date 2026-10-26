import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/holding.dart';
import '../services/db.dart';
import '../services/price_service.dart';
import '../utils/theme.dart';
import '../utils/money.dart';
import '../services/history.dart';
import '../widgets/interactive_chart.dart';
import 'add_holding_screen.dart';

class HoldingDetailScreen extends StatefulWidget {
  final Holding holding;
  const HoldingDetailScreen({super.key, required this.holding});

  @override
  State<HoldingDetailScreen> createState() => _HoldingDetailScreenState();
}

class _HoldingDetailScreenState extends State<HoldingDetailScreen> {
  List<ChartPoint> _points = []; // price per share in cents, oldest first
  bool _loading = true;
  String _range = '1M';
  ChartPoint? _scrub;

  static const _ranges = {'1W': 7, '1M': 30, '3M': 90, '1J': 365};
  static const _periods = {
    '1W': 'in einer Woche',
    '1M': 'im letzten Monat',
    '3M': 'in 3 Monaten',
    '1J': 'im letzten Jahr',
  };

  @override
  void initState() {
    super.initState();
    _loadChart();
  }

  Future<void> _loadChart() async {
    setState(() => _loading = true);
    final h = widget.holding;
    final range = _range;
    final pts = await PriceService.historyPoints(symbol: h.symbol, type: h.type, days: _ranges[range]!);
    // ignore late results of a range that is no longer selected
    if (mounted && range == _range) {
      // the curve ends at the price shown above it, so the change in the
      // headline and the direction of the curve always agree
      final last = pts.isEmpty ? 0.0 : pts.last.$2;
      final scale = last > 0 && h.currentPriceCents > 0 ? h.currentPriceCents / 100 / last : 1.0;
      setState(() {
        _points = [for (final p in pts) ChartPoint(p.$1, (p.$2 * scale * 100).round())];
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Box>(
      valueListenable: Hive.box('holdings').listenable(),
      builder: (_, __, ___) {
        final matches = DB.getHoldings().where((x) => x.id == widget.holding.id).toList();
        if (matches.isEmpty) {
          // deleted elsewhere — leave the screen
          // only while this page is on top: after its own delete it is already leaving
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && (ModalRoute.of(context)?.isCurrent ?? false)) Navigator.pop(context);
          });
          return const SizedBox.shrink();
        }
        final h = matches.first;
        final up = h.isUp;
        final color = up ? AppColors.positive : AppColors.error;

        return Scaffold(
          appBar: AppBar(
            title: Text(h.name),
            actions: [
              IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => _edit(h)),
              IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _delete(h)),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              // price with an interactive chart; scrubbing shows each day's price
              ChartHeader(
                label: h.symbol.isNotEmpty ? 'Kurs · ${h.symbol}' : 'Kurs',
                cents: h.currentPriceCents,
                startCents: _points.length >= 2 ? _points.first.cents : h.buyPriceCents,
                period: _points.length >= 2 ? _periods[_range]! : 'seit Kauf',
                scrub: _scrub,
                startDate: _points.isEmpty ? null : _points.first.date,
              ),
              const SizedBox(height: 16),
              if (_loading)
                const SizedBox(height: 160, child: Center(child: CircularProgressIndicator(color: AppColors.primary)))
              else if (_points.length < 2)
                SizedBox(
                  height: 120,
                  child: Center(
                    child: Text(
                      h.type == 'Krypto' ? 'Chart nicht verfügbar' : 'Aktien-Chart ist auf dem iPhone live',
                      style: TextStyle(color: AppColors.textDim),
                    ),
                  ),
                )
              else
                InteractiveChart(points: _points, onScrub: (p) => setState(() => _scrub = p)),
              const SizedBox(height: 12),
              RangeSelector(
                labels: _ranges.keys.toList(),
                selected: _range,
                onChanged: (r) {
                  setState(() => _range = r);
                  _loadChart();
                },
              ),
              const SizedBox(height: 24),

              // the user's own position
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Deine Position', style: TextStyle(color: AppColors.textDim, fontSize: 13)),
                    const SizedBox(height: 2),
                    Text(Money.format(h.valueCents),
                        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -0.6)),
                    const SizedBox(height: 4),
                    Text('${Money.signed(h.gainCents)} · ${Money.percent(h.gainPercent, digits: 2)} seit Kauf',
                        style: TextStyle(color: color, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // details
              _detailRow('Anzahl', '${_trimShares(h.shares)} Stück'),
              if (h.symbol.isNotEmpty) _detailRow('Symbol', h.symbol),
              _detailRow('Typ', h.type),
              _detailRow('Kaufpreis', Money.format(h.buyPriceCents)),
              _detailRow('Aktueller Kurs', Money.format(h.currentPriceCents)),
              _detailRow('Investiert', Money.format(h.investedCents)),
              _detailRow('Gewinn/Verlust', Money.signed(h.gainCents), color: color),
            ],
          ),
        );
      },
    );
  }

  Widget _detailRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: AppColors.textDim)),
          Text(value, style: TextStyle(fontWeight: FontWeight.w500, color: color)),
        ],
      ),
    );
  }

  String _trimShares(double v) {
    final s = v.toStringAsFixed(4);
    return s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '').replaceAll('.', ',');
  }

  void _edit(Holding h) async {
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => AddHoldingScreen(holding: h)));
    if (mounted) _loadChart(); // symbol may have changed
  }

  Future<void> _delete(Holding h) async {
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
      if (mounted) Navigator.pop(context);
    }
  }
}
