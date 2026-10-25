import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../models/transaction.dart';
import '../services/buddy_service.dart';
import '../services/plus_service.dart';
import 'plus_screen.dart';
import '../services/db.dart';
import '../services/quick_parser.dart';
import '../utils/dates.dart';
import '../utils/money.dart';
import '../utils/theme.dart';
import '../widgets/big_number.dart';
import '../widgets/buddy_orb.dart';

// Booking by writing a note ("Döner 8,50 gestern") or snapping a receipt.
// The preview updates with every key press; saving lets Buddy refine it.
Future<void> showSmartEntry(BuildContext context, {bool scan = false}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => _SmartEntry(scanFirst: scan),
  );
}

class _SmartEntry extends StatefulWidget {
  final bool scanFirst;
  const _SmartEntry({required this.scanFirst});

  @override
  State<_SmartEntry> createState() => _SmartEntryState();
}

class _SmartEntryState extends State<_SmartEntry> {
  final _text = TextEditingController();
  ParsedBooking? _preview;
  bool _fromReceipt = false;
  String? _busy; // what Buddy is doing right now
  String? _error;

  static const _examples = ['Kaffee 3,20', 'Tanken 65 gestern', 'Gehalt 2.850 am 1.10.', 'Kino 24 freitag'];

  @override
  void initState() {
    super.initState();
    if (widget.scanFirst) WidgetsBinding.instance.addPostFrameCallback((_) => _scan());
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _typed(String value) {
    setState(() {
      _preview = QuickParser.parse(value);
      _fromReceipt = false;
      _error = null;
    });
  }

  Future<void> _scan() async {
    if (!PlusService.allowed(PlusFeature.receiptScan)) {
      await showPlus(context, reason: 'Du hast deine ${PlusService.freeReceiptScans} Gratis-Scans genutzt');
      if (!PlusService.active.value) return;
    }
    final picked = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    final file = picked?.files.single;
    if (file?.bytes == null) return;
    final ext = (file!.extension ?? 'jpg').toLowerCase();
    final mime = switch (ext) { 'png' => 'image/png', 'webp' => 'image/webp', 'gif' => 'image/gif', _ => 'image/jpeg' };
    setState(() {
      _busy = 'Buddy liest deinen Beleg …';
      _error = null;
    });
    try {
      final booking = await BuddyService.receipt(file.bytes!, mime);
      await PlusService.count(PlusFeature.receiptScan);
      HapticFeedback.mediumImpact();
      setState(() {
        _preview = booking;
        _fromReceipt = true;
      });
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _save() async {
    var booking = _preview;
    if (booking == null) return;
    if (!_fromReceipt) {
      setState(() => _busy = 'Buddy prüft …');
      booking = await BuddyService.parse(_text.text) ?? booking;
    }
    final tx = Transaction(
      id: const Uuid().v4(),
      amountCents: booking.cents,
      category: booking.category,
      date: booking.date,
      isIncome: booking.isIncome,
      note: booking.note.isEmpty ? null : booking.note,
    );
    await DB.addTx(tx);
    await DB.checkBadges();
    HapticFeedback.mediumImpact();
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messenger.showSnackBar(SnackBar(
      content: Text('${tx.note ?? tx.category} · ${tx.amountText} gespeichert'),
      action: SnackBarAction(label: 'Rückgängig', onPressed: () => DB.deleteTx(tx.id)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          BuddyOrb(size: 28, active: _busy != null),
          const SizedBox(width: 10),
          const Text('Schnell erfassen', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 6),
        Text('Schreib es so, wie du es sagen würdest, oder fotografiere den Beleg.',
            style: TextStyle(color: AppColors.textDim, fontSize: 14)),
        const SizedBox(height: 16),
        TextField(
          controller: _text,
          autofocus: !widget.scanFirst,
          onChanged: _typed,
          onSubmitted: (_) => _preview != null ? _save() : null,
          textInputAction: TextInputAction.done,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            hintText: 'z. B. Döner 8,50 gestern',
            prefixIcon: const Icon(Icons.auto_awesome_rounded, color: AppColors.primary),
            suffixIcon: IconButton(
              tooltip: 'Beleg scannen',
              icon: const Icon(Icons.document_scanner_rounded),
              onPressed: _busy == null ? _scan : null,
            ),
          ),
        ),
        const SizedBox(height: 14),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          transitionBuilder: (child, a) => FadeTransition(
            opacity: a,
            child: SizeTransition(sizeFactor: a, axisAlignment: -1, child: child),
          ),
          child: _busy != null
              ? _status(_busy!)
              : _preview != null
                  ? _previewCard(_preview!)
                  : _exampleChips(),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 13)),
        ],
        const SizedBox(height: 18),
        FilledButton(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            disabledBackgroundColor: AppColors.surfaceAlt,
            disabledForegroundColor: AppColors.textDim,
          ),
          onPressed: _preview != null && _busy == null ? _save : null,
          child: const Text('Speichern', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }

  Widget _status(String text) => Container(
        key: const ValueKey('busy'),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(18)),
        child: Row(children: [
          const BuddyOrb(size: 32, active: true),
          const SizedBox(width: 14),
          Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
      );

  Widget _previewCard(ParsedBooking b) {
    final title = b.note.isNotEmpty ? b.note : b.category;
    return Container(
      key: ValueKey('${b.cents}${b.category}${b.note}${b.date}'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.5)),
      ),
      child: Row(children: [
        CategoryAvatar(b.category, isIncome: b.isIncome),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text('${b.category} · ${Dates.relativeDay(b.date)}${_fromReceipt ? ' · vom Beleg' : ''}',
                style: TextStyle(color: AppColors.textDim, fontSize: 13)),
          ]),
        ),
        Text(Money.withSign(b.cents, b.isIncome),
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: b.isIncome ? AppColors.positive : AppColors.text)),
      ]),
    );
  }

  Widget _exampleChips() => Wrap(
        key: const ValueKey('examples'),
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final e in _examples)
            ActionChip(
              label: Text(e),
              onPressed: () {
                _text.text = e;
                _typed(e);
              },
            ),
        ],
      );
}
