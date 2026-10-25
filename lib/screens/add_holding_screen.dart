import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/holding.dart';
import '../services/db.dart';
import '../services/price_service.dart';
import '../utils/theme.dart';
import '../utils/money.dart';
import '../utils/instruments.dart';
import '../widgets/instrument_search_sheet.dart';

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
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Position bearbeiten' : 'Neue Position')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _label('Wertpapier'),
            InkWell(
              onTap: _pickInstrument,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(16)),
                child: Row(
                  children: [
                    const Icon(Icons.search, color: AppColors.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _nameCtrl.text.isEmpty
                          ? Text('Aktie, ETF oder Krypto suchen...',
                              style: TextStyle(color: AppColors.textDim))
                          : Text(
                              _symbolCtrl.text.isEmpty
                                  ? _nameCtrl.text
                                  : '${_nameCtrl.text} · ${_symbolCtrl.text}',
                              style: const TextStyle(fontWeight: FontWeight.w500)),
                    ),
                    Icon(Icons.chevron_right, color: AppColors.textDim),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            _label('Typ'),
            DropdownButtonFormField<String>(
              initialValue: _type,
              items: [
                for (final t in AssetTypes.list)
                  DropdownMenuItem(
                    value: t['name'],
                    child: Row(children: [
                      Text(t['emoji']!, style: const TextStyle(fontSize: 20)),
                      const SizedBox(width: 12),
                      Text(t['name']!),
                    ]),
                  ),
              ],
              onChanged: (v) => setState(() => _type = v ?? 'Aktie'),
            ),
            const SizedBox(height: 20),

            _label('Anzahl'),
            TextFormField(
              controller: _sharesCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(hintText: 'z.B. 10'),
              validator: (v) {
                final n = _parseShares(v ?? '');
                if (n == null || n <= 0) return 'Ungültig';
                return null;
              },
            ),
            const SizedBox(height: 20),

            _label('Kaufpreis pro Stück'),
            _priceField(_buyCtrl),
            const SizedBox(height: 20),

            _label('Aktueller Kurs pro Stück'),
            _priceField(_currentCtrl),
            const SizedBox(height: 32),

            ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
              child: _saving
                  ? const SizedBox(
                      height: 20, width: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text(_isEdit ? 'Aktualisieren' : 'Speichern'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t, style: const TextStyle(fontWeight: FontWeight.bold)),
      );

  Widget _priceField(TextEditingController ctrl) {
    return TextFormField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: const InputDecoration(hintText: '0,00', prefixText: '€ '),
      validator: (v) {
        final cents = Money.parseToCents(v ?? '');
        if (cents == null || cents <= 0) return 'Ungültig';
        return null;
      },
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
