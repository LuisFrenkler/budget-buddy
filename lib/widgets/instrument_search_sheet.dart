import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/price_service.dart';
import '../utils/money.dart';
import 'instrument_avatar.dart';
import '../utils/instruments.dart';
import '../utils/theme.dart';

// Bottom sheet to search and pick a real instrument. Tap a hit → live Kurs +
// Nachrichten, then „Übernehmen“ returns the Instrument to the add screen.
class InstrumentSearchSheet extends StatefulWidget {
  const InstrumentSearchSheet({super.key});

  @override
  State<InstrumentSearchSheet> createState() => _InstrumentSearchSheetState();
}

class _InstrumentSearchSheetState extends State<InstrumentSearchSheet> {
  String _q = '';
  List<Instrument> _live = [];
  String _liveFor = '';
  Timer? _debounce;
  int _gen = 0;
  bool _searching = false;
  // symbol → live EUR cents (filled after search)
  final _quotes = <String, int>{};
  int _quoteGen = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onQuery(String v) {
    _debounce?.cancel();
    final q = v.trim();
    if (q.isEmpty) {
      _gen++;
      _quoteGen++;
      setState(() {
        _q = v;
        _live = [];
        _quotes.clear();
        _searching = false;
      });
      return;
    }
    setState(() => _q = v);
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() => _searching = true);
      _search(q);
    });
  }

  Future<void> _search(String q) async {
    final gen = ++_gen;
    final live = await PriceService.search(q);
    if (!mounted || gen != _gen) return;
    setState(() {
      _live = live;
      _liveFor = q;
      _searching = false;
    });
    _fetchQuotes(_merged().take(12).toList(), gen);
  }

  Future<void> _fetchQuotes(List<Instrument> items, int gen) async {
    final qg = ++_quoteGen;
    for (final i in items) {
      if (!mounted || qg != _quoteGen || gen != _gen) return;
      if (i.symbol.isEmpty || _quotes.containsKey(i.symbol)) continue;
      final cents = i.refCents > 0
          ? i.refCents
          : await PriceService.livePrice(symbol: i.symbol, type: i.type);
      if (!mounted || qg != _quoteGen) return;
      if (cents != null && cents > 0) {
        setState(() => _quotes[i.symbol] = cents);
      }
    }
  }

  List<Instrument> _merged() {
    final local = Instruments.search(_q);
    if (_q.trim().isEmpty || _liveFor != _q.trim()) return local;
    final seen = {for (final i in local) i.symbol.toUpperCase()};
    return [
      ...local,
      for (final i in _live)
        if (seen.add(i.symbol.toUpperCase())) i,
    ];
  }

  int _priceOf(Instrument i) => _quotes[i.symbol] ?? (i.refCents > 0 ? i.refCents : 0);

  Future<void> _openPreview(Instrument i) async {
    final priced = Instrument(i.name, i.symbol, i.type, _priceOf(i));
    final picked = await showModalBottomSheet<Instrument>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      builder: (_) => _InstrumentPreview(priced),
    );
    if (picked != null && mounted) Navigator.pop(context, picked);
  }

  @override
  Widget build(BuildContext context) {
    final results = _merged();
    final q = _q.trim().toLowerCase();
    final exact = q.isNotEmpty &&
        results.any((i) => i.name.toLowerCase() == q || i.symbol.toLowerCase() == q);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                autofocus: true,
                onChanged: _onQuery,
                decoration: InputDecoration(
                  hintText: 'Aktie, ETF oder Krypto suchen...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searching
                      ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                          ),
                        )
                      : null,
                ),
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  if (q.isNotEmpty && !exact)
                    ListTile(
                      leading: const Icon(Icons.add, color: AppColors.primary),
                      title: Text('„${_q.trim()}" verwenden'),
                      subtitle: const Text('Eigenes Wertpapier'),
                      onTap: () => Navigator.pop(context, Instrument(_q.trim(), '', 'Aktie', 0)),
                    ),
                  for (final i in results)
                    ListTile(
                      leading: InstrumentAvatar(i.name),
                      title: Text(i.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('${i.symbol.isEmpty ? '—' : i.symbol} · ${i.type}',
                          style: TextStyle(color: AppColors.textDim)),
                      trailing: _priceOf(i) > 0
                          ? Text(Money.format(_priceOf(i)), style: const TextStyle(fontWeight: FontWeight.w700))
                          : Icon(Icons.chevron_right_rounded, color: AppColors.textDim),
                      onTap: () => _openPreview(i),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Live Kurs + Nachrichten, then confirm to use this instrument
class _InstrumentPreview extends StatefulWidget {
  final Instrument instrument;
  const _InstrumentPreview(this.instrument);

  @override
  State<_InstrumentPreview> createState() => _InstrumentPreviewState();
}

class _InstrumentPreviewState extends State<_InstrumentPreview> {
  int? _cents;
  bool _priceLoading = true;
  bool _newsLoading = true;
  List<MarketHeadline> _news = [];

  @override
  void initState() {
    super.initState();
    _cents = widget.instrument.refCents > 0 ? widget.instrument.refCents : null;
    _load();
  }

  Future<void> _load() async {
    final i = widget.instrument;
    final priceFut = i.symbol.isEmpty
        ? Future<int?>.value(_cents)
        : PriceService.livePrice(symbol: i.symbol, type: i.type);
    final newsFut = i.symbol.isEmpty ? Future.value(<MarketHeadline>[]) : PriceService.news(i.symbol);
    final price = await priceFut;
    if (mounted) {
      setState(() {
        if (price != null && price > 0) _cents = price;
        _priceLoading = false;
      });
    }
    final news = await newsFut;
    if (mounted) {
      setState(() {
        _news = news;
        _newsLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final i = widget.instrument;
    final h = MediaQuery.sizeOf(context).height * 0.72;
    return SafeArea(
      child: SizedBox(
        height: h,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                InstrumentAvatar(i.name, size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(i.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                    Text('${i.symbol.isEmpty ? 'ohne Symbol' : i.symbol} · ${i.type}',
                        style: TextStyle(color: AppColors.textDim)),
                  ]),
                ),
              ]),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(16)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Aktueller Kurs', style: TextStyle(color: AppColors.textDim, fontSize: 13)),
                  const SizedBox(height: 4),
                  if (_priceLoading && (_cents == null || _cents == 0))
                    const SizedBox(height: 28, child: Align(alignment: Alignment.centerLeft, child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))))
                  else
                    Text(
                      (_cents != null && _cents! > 0) ? Money.format(_cents!) : 'Kurs gerade nicht verfügbar',
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.6),
                    ),
                ]),
              ),
              const SizedBox(height: 18),
              Text('Nachrichten', style: TextStyle(color: AppColors.textDim, fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Expanded(
                child: _newsLoading
                    ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                    : _news.isEmpty
                        ? Text(
                            i.symbol.isEmpty
                                ? 'Ohne Börsen-Symbol keine Nachrichten.'
                                : 'Gerade keine Schlagzeilen zu ${i.symbol}.',
                            style: TextStyle(color: AppColors.textDim, height: 1.4),
                          )
                        : ListView.separated(
                            itemCount: _news.length,
                            separatorBuilder: (_, __) => Divider(height: 1, color: AppColors.border),
                            itemBuilder: (_, idx) {
                              final n = _news[idx];
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(n.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                subtitle: n.publisher.isEmpty ? null : Text(n.publisher),
                                trailing: Icon(Icons.open_in_new, size: 16, color: AppColors.textDim),
                                onTap: () => launchUrl(Uri.parse(n.url), mode: LaunchMode.externalApplication),
                              );
                            },
                          ),
              ),
              const SizedBox(height: 8),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                onPressed: () => Navigator.pop(
                  context,
                  Instrument(i.name, i.symbol, i.type, _cents ?? i.refCents),
                ),
                child: const Text('Übernehmen'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
