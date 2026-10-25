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

  @override
  State<AddHoldingScreen> createState() => _AddHoldingScreenState();
}

class _AddHoldingScreenState extends State<AddHoldingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _symbolCtrl = TextEditingController();
  final _sharesCtrl = TextEditingController();
  final _buyCtrl = TextEditingController();
  final _currentCtrl = TextEditingController();
  String _type = 'Aktie';
  bool _saving = false;

  bool get _isEdit => widget.holding != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      final h = widget.holding!;
      _nameCtrl.text = h.name;
      _symbolCtrl.text = h.symbol;
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
    _sharesCtrl.dispose();
    _buyCtrl.dispose();
    _currentCtrl.dispose();
    super.dispose();
  }

  // shows a share count without trailing ".0"
  String _trimNum(double v) {
    final s = v.toStringAsFixed(4);
    return s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '').replaceAll('.', ',');
  }

  static double? _parseShares(String s) => double.tryParse(s.trim().replaceAll(',', '.'));

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
                                    Text(_symbolCtrl.text, style: TextStyle(color: AppColors.textDim, fontSize: 13)),
                                ],
                              ),
                      ),
                      Icon(Icons.chevron_right_rounded, color: AppColors.textDim),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Segmented(
              labels: types,
              index: types.indexOf(_type).clamp(0, types.length - 1),
              onChanged: (i) => setState(() => _type = types[i]),
            ),
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
                  _field('Kaufpreis', _buyCtrl, '0,00', suffix: '€ / Stück', validator: _priceValidator),
                  Divider(height: 1, indent: 16, color: AppColors.border),
                  _field('Aktueller Kurs', _currentCtrl, '0,00', suffix: '€ / Stück', validator: _priceValidator),
                ],
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

  String? _priceValidator(String? v) {
    final cents = Money.parseToCents(v ?? '');
    return cents == null || cents <= 0 ? 'Ungültig' : null;
  }

  // label on the left, right-aligned input with a unit on the right
  Widget _field(String label, TextEditingController ctrl, String hint,
      {required String suffix, required FormFieldValidator<String> validator}) {
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
              onChanged: (_) => setState(() {}),
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
    final color = gain >= 0 ? AppColors.primary : AppColors.error;

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

  // opens the instrument search sheet and fills name/symbol/type (and the
  // current price when a live API key is configured)
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
    setState(() {
      _nameCtrl.text = picked.name;
      _symbolCtrl.text = picked.symbol;
      _type = picked.type;
      // pre-fill the current price right away from the reference value
      if (picked.refCents > 0) {
        _currentCtrl.text =
            (picked.refCents / 100).toStringAsFixed(2).replaceAll('.', ',');
      }
    });
    // upgrade to a live price where available (crypto always, stocks with key)
    final live = await PriceService.livePrice(symbol: picked.symbol, type: picked.type);
    if (live != null && live > 0 && mounted) {
      setState(() => _currentCtrl.text =
          (live / 100).toStringAsFixed(2).replaceAll('.', ','));
    }
  }

  void _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte ein Wertpapier wählen')),
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
      );
      await DB.addHolding(holding);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
