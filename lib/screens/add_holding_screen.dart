import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/holding.dart';
import '../services/db.dart';
import '../services/price_service.dart';
import '../utils/theme.dart';
import '../utils/money.dart';
import '../utils/instruments.dart';
import '../widgets/instrument_search_sheet.dart';
import '../widgets/segmented.dart';
import '../widgets/instrument_avatar.dart';

class AddHoldingScreen extends StatefulWidget {
  // holding == null -> create new, otherwise edit existing
  final Holding? holding;
  const AddHoldingScreen({super.key, this.holding});

  // shows a share count without trailing zeros, with every decimal it has
  // (crypto goes down to satoshis), so saving unchanged keeps it exactly
  static String trimNum(double v) {
    final s = v.toStringAsFixed(10);
    return s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '').replaceAll('.', ',');
  }

  // German first, like the price fields: "1.000,5" and "1.000" are thousands,
  // "0,25" and "0.25" a fraction
  static double? parseShares(String input) {
    var s = input.trim().replaceAll(' ', '');
    if (s.contains(',')) {
      s = s.replaceAll('.', '').replaceAll(',', '.');
    } else if (RegExp(r'^\d{1,3}(\.\d{3})+$').hasMatch(s)) {
      s = s.replaceAll('.', '');
    }
    return double.tryParse(s);
  }

  // A searched ticker keeps its type (Apple stays Aktie). A custom name, or a
  // symbol the user typed themselves, can still choose the type.
  static bool typeLocked({required String symbol, required bool customSymbol}) =>
      symbol.trim().isNotEmpty && !customSymbol;

  @override
  State<AddHoldingScreen> createState() => _AddHoldingScreenState();
}

class _AddHoldingScreenState extends State<AddHoldingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _symbolCtrl = TextEditingController();
  final _depotCtrl = TextEditingController();
  final _sharesCtrl = TextEditingController();
  final _buyCtrl = TextEditingController();
  final _currentCtrl = TextEditingController();
  String _type = 'Aktie';
  // the symbol field stays while the user types into it
  bool _customSymbol = false;
  // buy price follows the quote until the user types their own
  bool _buyEdited = false;
  // a search quote filled the price fields, so the hint applies
  bool _quoted = false;
  // drops a live quote that belongs to an instrument the user already replaced
  int _pickGen = 0;
  bool _saving = false;

  bool get _isEdit => widget.holding != null;

  bool get _typeLocked => AddHoldingScreen.typeLocked(symbol: _symbolCtrl.text, customSymbol: _customSymbol);

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      final h = widget.holding!;
      _nameCtrl.text = h.name;
      _symbolCtrl.text = h.symbol;
      _depotCtrl.text = h.depot ?? '';
      _sharesCtrl.text = _trimNum(h.shares);
      _buyCtrl.text = (h.buyPriceCents / 100).toStringAsFixed(2).replaceAll('.', ',');
      _currentCtrl.text = (h.currentPriceCents / 100).toStringAsFixed(2).replaceAll('.', ',');
      _type = h.type;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _symbolCtrl.dispose();
    _depotCtrl.dispose();
    _sharesCtrl.dispose();
    _buyCtrl.dispose();
    _currentCtrl.dispose();
    super.dispose();
  }

  String _trimNum(double v) => AddHoldingScreen.trimNum(v);

  static double? _parseShares(String s) => AddHoldingScreen.parseShares(s);

  @override
  Widget build(BuildContext context) {
    final types = [for (final t in AssetTypes.list) t['name']!];
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Position bearbeiten' : 'Neue Position')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            // instrument: search sheet with live prices
            Material(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                onTap: _pickInstrument,
                borderRadius: BorderRadius.circular(18),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      if (_nameCtrl.text.isEmpty)
                        Container(
                          width: 44,
                          height: 44,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: AppColors.surfaceAlt, shape: BoxShape.circle),
                          child: const Icon(Icons.search_rounded, color: AppColors.primary),
                        )
                      else
                        InstrumentAvatar(_nameCtrl.text, size: 44),
                      const SizedBox(width: 14),
                      Expanded(
                        child: _nameCtrl.text.isEmpty
                            ? Text('Aktie, ETF oder Krypto suchen', style: TextStyle(color: AppColors.textDim))
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(_nameCtrl.text,
                                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                                      overflow: TextOverflow.ellipsis),
                                  if (_symbolCtrl.text.isNotEmpty)
                                    Text(
                                      _typeLocked ? '${_symbolCtrl.text} · $_type' : _symbolCtrl.text,
                                      style: TextStyle(color: AppColors.textDim, fontSize: 13),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                ],
                              ),
                      ),
                      Icon(Icons.chevron_right_rounded, color: AppColors.textDim),
                    ],
                  ),
                ),
              ),
            ),
            if (!_typeLocked) ...[
              const SizedBox(height: 16),
              Segmented(
                labels: types,
                index: types.indexOf(_type).clamp(0, types.length - 1),
                onChanged: (i) => setState(() => _type = types[i]),
              ),
            ],
            const SizedBox(height: 16),

            // amounts as one calm group
            Container(
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(18)),
              child: Column(
                children: [
                  _field('Anzahl', _sharesCtrl, 'z.B. 10', suffix: 'Stück', validator: (v) {
                    final n = _parseShares(v ?? '');
                    return n == null || n <= 0 ? 'Ungültig' : null;
                  }),
                  Divider(height: 1, indent: 16, color: AppColors.border),
                  _field('Kaufpreis', _buyCtrl, '0,00',
                      suffix: '€ / Stück', validator: _priceValidator, onUserEdit: () => _buyEdited = true),
                  Divider(height: 1, indent: 16, color: AppColors.border),
                  _field('Aktueller Kurs', _currentCtrl, '0,00', suffix: '€ / Stück', validator: _priceValidator),
                ],
              ),
            ),
            if (_quoted) ...[
              const SizedBox(height: 8),
              Text(
                'Kaufpreis ist mit dem aktuellen Kurs vorausgefüllt. Passe ihn an, wenn du einen anderen Preis gezahlt hast.',
                style: TextStyle(color: AppColors.textDim, fontSize: 12.5, height: 1.35),
              ),
            ],
            // a position from the custom entry has no ticker yet: with one it gets live prices
            if (_nameCtrl.text.isNotEmpty && (_customSymbol || _symbolCtrl.text.isEmpty)) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _symbolCtrl,
                textCapitalization: TextCapitalization.characters,
                onChanged: (_) => setState(() => _customSymbol = true),
                decoration: const InputDecoration(
                  labelText: 'Symbol (optional)',
                  hintText: 'z. B. SAP.DE, AAPL oder BTC',
                  helperText: 'Damit holt BudgetBuddy den Kurs automatisch.',
                ),
              ),
            ],
            const SizedBox(height: 12),
            // with several depots the positions are grouped by this name
            TextField(
              controller: _depotCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'Depot (optional)',
                hintText: 'z. B. Trade Republic, Scalable',
                suffixIcon: _depotNames.isEmpty
                    ? null
                    : PopupMenuButton<String>(
                        tooltip: 'Depot wählen',
                        icon: const Icon(Icons.arrow_drop_down_rounded),
                        onSelected: (v) => setState(() => _depotCtrl.text = v),
                        itemBuilder: (_) => [for (final d in _depotNames) PopupMenuItem(value: d, child: Text(d))],
                      ),
              ),
            ),
            const SizedBox(height: 16),
            _preview(),
            const SizedBox(height: 24),

            ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
              child: _saving
                  ? const SizedBox(
                      height: 20, width: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text(_isEdit ? 'Aktualisieren' : 'Zum Depot hinzufügen'),
            ),
          ],
        ),
      ),
    );
  }

  // the depots already named, to pick from
  List<String> get _depotNames =>
      {for (final h in DB.getHoldings()) if (h.depot != null && h.depot!.isNotEmpty) h.depot!}.toList()..sort();

  String? _priceValidator(String? v) {
    final cents = Money.parseToCents(v ?? '');
    return cents == null || cents <= 0 ? 'Ungültig' : null;
  }

  // label on the left, right-aligned input with a unit on the right
  Widget _field(String label, TextEditingController ctrl, String hint,
      {required String suffix, required FormFieldValidator<String> validator, VoidCallback? onUserEdit}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              controller: ctrl,
              textAlign: TextAlign.right,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) {
                onUserEdit?.call();
                setState(() {});
              },
              validator: validator,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(color: AppColors.textDim),
                filled: false,
                border: InputBorder.none,
                focusedBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(suffix, style: TextStyle(color: AppColors.textDim, fontSize: 13)),
        ],
      ),
    );
  }

  // live summary of what the position is worth, updated while typing
  Widget _preview() {
    final shares = _parseShares(_sharesCtrl.text) ?? 0;
    final buy = Money.parseToCents(_buyCtrl.text) ?? 0;
    final current = Money.parseToCents(_currentCtrl.text) ?? 0;
    final invested = (shares * buy).round();
    final value = (shares * current).round();
    final gain = value - invested;
    final color = gain >= 0 ? AppColors.positive : AppColors.error;

    Widget cell(String label, String v, Color c) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: AppColors.textDim, fontSize: 12)),
              const SizedBox(height: 2),
              Text(v, style: TextStyle(fontWeight: FontWeight.w700, color: c), overflow: TextOverflow.ellipsis),
            ],
          ),
        );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(children: [
        cell('Investiert', Money.format(invested), AppColors.text),
        cell('Wert', Money.format(value), AppColors.text),
        cell('Gewinn', invested == 0 ? '–' : Money.percent(gain / invested * 100), invested == 0 ? AppColors.textDim : color),
      ]),
    );
  }

  // opens the instrument search sheet and fills name, symbol, type and both
  // prices (reference immediately, live quote when it arrives)
  Future<void> _pickInstrument() async {
    final picked = await showModalBottomSheet<Instrument>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => const InstrumentSearchSheet(),
    );
    if (picked == null) return;
    final gen = ++_pickGen;
    // the same position keeps the price they paid; a new one starts at the quote
    final keptBuy = _isEdit &&
        picked.name.trim() == widget.holding!.name.trim() &&
        picked.symbol.trim() == widget.holding!.symbol.trim();
    setState(() {
      _nameCtrl.text = picked.name;
      _symbolCtrl.text = picked.symbol;
      _type = picked.type;
      _customSymbol = false;
      _buyEdited = keptBuy;
      _quoted = false;
      _livePrice = null;
      if (picked.refCents > 0) {
        _fillQuote(picked.refCents, live: false);
      } else if (!keptBuy) {
        _currentCtrl.text = '';
        _buyCtrl.text = '';
      }
    });
    if (picked.symbol.trim().isEmpty) return;
    // upgrade to a live price where available (crypto always, stocks with key)
    final live = await PriceService.livePrice(symbol: picked.symbol, type: picked.type);
    if (live != null && live > 0 && mounted && gen == _pickGen) {
      setState(() => _fillQuote(live, live: true));
    }
  }

  // current price always; buy price until the user types what they paid
  void _fillQuote(int cents, {required bool live}) {
    final text = (cents / 100).toStringAsFixed(2).replaceAll('.', ',');
    _currentCtrl.text = text;
    if (!_buyEdited) {
      _buyCtrl.text = text;
      _quoted = true;
    }
    if (live) _livePrice = (cents: cents, at: DateTime.now());
  }

  // the live price fetched for the picked instrument, to keep its "Stand"
  ({int cents, DateTime at})? _livePrice;

  // when the price shown is a live one: just fetched, or unchanged since the last refresh
  DateTime? _priceAt(int cents) {
    if (_livePrice?.cents == cents) return _livePrice!.at;
    final old = widget.holding;
    if (old != null && old.currentPriceCents == cents) return old.priceAt;
    return null;
  }

  void _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(duration: Duration(milliseconds: 2800), content: Text('Bitte ein Wertpapier wählen')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final holding = Holding(
        id: _isEdit ? widget.holding!.id : const Uuid().v4(),
        name: _nameCtrl.text.trim(),
        symbol: _symbolCtrl.text.trim(),
        type: _type,
        shares: _parseShares(_sharesCtrl.text)!,
        buyPriceCents: Money.parseToCents(_buyCtrl.text)!,
        currentPriceCents: Money.parseToCents(_currentCtrl.text)!,
        priceAt: _priceAt(Money.parseToCents(_currentCtrl.text)!),
        depot: _depotCtrl.text.trim().isEmpty ? null : _depotCtrl.text.trim(),
      );
      await DB.addHolding(holding);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            duration: Duration(milliseconds: 2800),
            content: Text('Speichern hat nicht geklappt. Bitte prüf die Eingaben.')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
