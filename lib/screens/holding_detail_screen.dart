import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/holding.dart';
import '../services/db.dart';
import '../services/depot_sync.dart';
import '../services/price_service.dart';
import '../utils/theme.dart';
import '../utils/dates.dart';
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
  List<MarketHeadline> _news = [];
  bool _loading = true;
  bool _newsLoading = true;
  String _range = '1M';
  // the point under the finger while scrubbing; only the chart header listens
  final _scrub = ValueNotifier<ChartPoint?>(null);

  // 1T asks for one session; the service falls back to the last two closes
  static const _ranges = {'1T': 1, '1W': 7, '1M': 30, '3M': 90, '1J': 365};

  @override
  void initState() {
    super.initState();
    _loadChart();
    _loadNews();
  }

  // the saved position, so an edit that changes the symbol reloads the right data
  Holding _saved() {
    for (final h in DB.getHoldings()) {
      if (h.id == widget.holding.id) return h;
    }
    return widget.holding;
  }

  static bool _tiny(Holding h) => (h.unitEur ?? h.currentPriceCents / 100) < 0.01;

  Future<void> _loadChart() async {
    setState(() => _loading = true);
    final h = _saved();
    final range = _range;
    final pts = await PriceService.historyPoints(symbol: h.symbol, type: h.type, days: _ranges[range]!);
    // ignore late results of a range that is no longer selected
    if (mounted && range == _range) {
      // the curve ends at the price shown above it when the two are close;
      // a typed-in or old price never bends the real quotes
      final last = pts.isEmpty ? 0.0 : pts.last.$2;
      final scale = PriceService.alignScale(h.unitEur ?? h.currentPriceCents / 100, last);
      // a coin under a cent would be a flat line at 0 €: chart the position instead
      final times = _tiny(h) ? h.shares : 1.0;
      setState(() {
        _points = [for (final p in pts) ChartPoint(p.$1, (p.$2 * scale * times * 100).round())];
        _loading = false;
      });
    }
  }

  Future<void> _loadNews() async {
    final symbol = _saved().symbol.trim();
    if (mounted) setState(() => _newsLoading = true);
    if (symbol.isEmpty) {
      if (mounted) {
        setState(() {
          _news = [];
          _newsLoading = false;
        });
      }
      return;
    }
    final news = await PriceService.news(symbol);
    if (!mounted || _saved().symbol.trim() != symbol) return;
    setState(() {
      _news = news;
      _newsLoading = false;
    });
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
            // a synced position is managed by the depot link: the next sync would undo edits
            actions: h.id.startsWith(DepotSync.prefix)
                ? null
                : [
                    IconButton(tooltip: 'Bearbeiten', icon: const Icon(Icons.edit_outlined), onPressed: () => _edit(h)),
                    IconButton(tooltip: 'Löschen', icon: const Icon(Icons.delete_outline), onPressed: () => _delete(h)),
                  ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              // price with an interactive chart; scrubbing shows that point
              ChartHeader(
                label: '${_tiny(h) ? 'Wert' : 'Kurs'}${h.symbol.isNotEmpty ? ' · ${h.symbol}' : ''}',
                cents: _tiny(h) ? h.valueCents : h.currentPriceCents,
                startCents: _points.length >= 2 ? _points.first.cents : (_tiny(h) ? h.investedCents : h.buyPriceCents),
                period: _points.length >= 2 ? RangeSelector.periods[_range]! : 'seit Kauf',
                scrubbing: _scrub,
                startDate: _points.isEmpty ? null : _points.first.date,
                showTime: InteractiveChart.intraday(_points),
              ),
              const SizedBox(height: 16),
              if (_loading)
                const SizedBox(height: 160, child: Center(child: CircularProgressIndicator(color: AppColors.primary)))
              else if (_points.length < 2)
                SizedBox(
                  height: 120,
                  child: Center(
                    child: Text(
                      _range == '1T'
                          ? 'Für heute liegen noch keine Kurse vor'
                          : h.type == 'Krypto'
                              ? 'Chart nicht verfügbar'
                              : 'Aktien-Chart ist auf dem iPhone live',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textDim),
                    ),
                  ),
                )
              else
                InteractiveChart(points: _points, onScrub: (p) => _scrub.value = p),
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
              _detailRow('Aktueller Kurs', Money.unit(h.currentPriceCents, euros: h.unitEur)),
              // where the price comes from, so an old one never passes for today's
              _detailRow('Kurs-Stand', h.priceAt == null ? 'eingegeben, nicht live' : 'live, ${Dates.stand(h.priceAt!)}'),
              _detailRow('Investiert', Money.format(h.investedCents)),
              _detailRow('Gewinn/Verlust', Money.signed(h.gainCents), color: color),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 4, 6),
                decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Nachrichten', style: TextStyle(color: AppColors.textDim, fontSize: 13)),
                    if (_newsLoading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
                      )
                    else if (_news.isEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(0, 10, 12, 14),
                        child: Text(
                          h.symbol.isEmpty
                              ? 'Ohne Börsen-Symbol keine Nachrichten.'
                              : 'Gerade keine Schlagzeilen zu ${h.symbol}.',
                          style: TextStyle(color: AppColors.textDim, height: 1.35),
                        ),
                      )
                    else
                      for (final n in _news)
                        ListTile(
                          contentPadding: const EdgeInsets.only(right: 8),
                          title: Text(n.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                          subtitle: n.publisher.isEmpty ? null : Text(n.publisher),
                          trailing: Icon(Icons.open_in_new, size: 16, color: AppColors.textDim),
                          onTap: () => launchUrl(Uri.parse(n.url), mode: LaunchMode.externalApplication),
                        ),
                  ],
                ),
              ),
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
    if (mounted) {
      _loadChart(); // symbol may have changed
      _loadNews();
    }
  }

  Future<void> _delete(Holding h) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Position löschen?'),
        content: Text(h.name),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: Text('Löschen', style: TextStyle(color: AppColors.errorText))),
        ],
      ),
    );
    if (confirmed == true) {
      await DB.deleteHolding(h.id);
      if (mounted) Navigator.pop(context);
    }
  }
}
