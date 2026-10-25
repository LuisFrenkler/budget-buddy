import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/holding.dart';
import '../services/db.dart';
import '../services/price_service.dart';
import '../utils/theme.dart';
import '../utils/money.dart';
import '../widgets/line_chart.dart';
import 'add_holding_screen.dart';

class HoldingDetailScreen extends StatefulWidget {
  final Holding holding;
  const HoldingDetailScreen({super.key, required this.holding});

  @override
  State<HoldingDetailScreen> createState() => _HoldingDetailScreenState();
}

class _HoldingDetailScreenState extends State<HoldingDetailScreen> {
  List<double> _series = [];
  bool _loading = true;
  int _days = 30;

  static const _ranges = {'7T': 7, '1M': 30, '3M': 90, '1J': 365};

  @override
  void initState() {
    super.initState();
    _loadChart();
  }

  Future<void> _loadChart() async {
    setState(() => _loading = true);
    final h = widget.holding;
    final series = await PriceService.history(symbol: h.symbol, type: h.type, days: _days);
    if (mounted) {
      setState(() {
        _series = series;
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
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) Navigator.pop(context);
          });
          return const SizedBox.shrink();
        }
        final h = matches.first;
        final up = h.isUp;
        final color = up ? AppColors.primary : AppColors.error;

        return Scaffold(
          appBar: AppBar(
            title: Text(h.name),
            actions: [
              IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => _edit(h)),
              IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _delete(h)),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(Money.format(h.valueCents),
                  style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Row(children: [
                Icon(up ? Icons.trending_up : Icons.trending_down, color: color, size: 18),
                const SizedBox(width: 6),
                Text(
                  '${Money.signed(h.gainCents)} · ${h.gainPercent >= 0 ? '+' : ''}${h.gainPercent.toStringAsFixed(2)} %',
                  style: TextStyle(color: color, fontWeight: FontWeight.bold),
                ),
              ]),
              const SizedBox(height: 20),

              // range selector
              Row(
                children: [
                  for (final entry in _ranges.entries) _rangeChip(entry.key, entry.value),
                ],
              ),
              const SizedBox(height: 12),

              // price chart
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
                child: _loading
                    ? const SizedBox(
                        height: 150,
                        child: Center(child: CircularProgressIndicator(color: AppColors.primary)))
                    : _series.length < 2
                        ? SizedBox(
                            height: 150,
                            child: Center(
                              child: Text(
                                h.type == 'Krypto'
                                    ? 'Chart nicht verfügbar'
                                    : 'Aktien-Chart ist auf dem iPhone live',
                                style: TextStyle(color: AppColors.textDim),
                              ),
                            ),
                          )
                        : LineChart(_series, color: color),
              ),
              const SizedBox(height: 24),

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

  Widget _rangeChip(String label, int days) {
    final active = _days == days;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () {
          setState(() => _days = days);
          _loadChart();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: active ? AppColors.primary.withValues(alpha: 0.15) : AppColors.surface,
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
