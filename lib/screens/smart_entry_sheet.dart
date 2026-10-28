import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../models/transaction.dart';
import '../services/account_service.dart';
import '../services/buddy_service.dart';
import '../services/onboarding_service.dart';
import '../services/plus_service.dart';
import 'auth_screens.dart';
import 'buddy_screen.dart';
import 'plus_screen.dart';
import '../services/category_rules.dart';
import '../services/db.dart';
import '../services/money_accounts.dart';
import 'account_screen.dart';
import '../services/quick_parser.dart';
import '../utils/dates.dart';
import '../utils/money.dart';
import '../utils/theme.dart';
import '../widgets/big_number.dart';
import '../widgets/buddy_orb.dart';
import '../widgets/getting_started.dart';

// Booking by writing a note ("Döner 8,50 gestern") or snapping a receipt.
// The preview updates with every key press (offline parser); when typing
// pauses, Buddy refines it. What the preview shows is exactly what is saved.
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
  bool _withoutAi = false; // local parser only (KI aus / offline)
  String? _busy; // what Buddy is doing right now
  String? _error;
  // Buddy refines the preview once typing pauses
  Timer? _refine;
  bool _refining = false;

  static const _examples = ['Kaffee 3,20', 'Tanken 65 gestern', 'Gehalt 2.850 am 1.10.', 'Kino 24 freitag'];

  @override
  void initState() {
    super.initState();
    if (widget.scanFirst) WidgetsBinding.instance.addPostFrameCallback((_) => _scan());
  }

  @override
  void dispose() {
    _refine?.cancel();
    _text.dispose();
    super.dispose();
  }

  void _typed(String value) {
    setState(() {
      _preview = QuickParser.parse(value);
      _fromReceipt = false;
      _withoutAi = true; // until a live refine succeeds
      _error = null;
      _refining = false;
    });
    _refine?.cancel();
    if (_preview != null && value.trim().length >= 4) {
      _refine = Timer(const Duration(milliseconds: 900), () => _refineNow(value));
    }
  }

  // Buddy's reading of the same words; shown only if nothing changed meanwhile
  Future<void> _refineNow(String value) async {
    setState(() => _refining = true);
    final usedAi = await BuddyService.liveAllowed();
    final better = await BuddyService.parse(value);
    if (!mounted || _text.text != value || _fromReceipt) return;
    setState(() {
      if (better != null) _preview = better;
      _withoutAi = !usedAi;
      _refining = false;
    });
  }

  Future<void> _scan() async {
    if (!PlusService.allowed(PlusFeature.receiptScan)) {
      await showPlus(context,
          reason: 'Gratis-Scans aufgebraucht — mit Plus jeden Beleg in Sekunden erfassen');
      if (!mounted || !PlusService.active.value) return;
    }
    if (AccountService.current.value == null) {
      if (!mounted) return;
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Konto für Beleg-Scan'),
          content: const Text(
              'Belege liest Buddy online. Dafür brauchst du ein kostenloses Konto — Tippen geht weiter ohne.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Später')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Konto erstellen')),
          ],
        ),
      );
      if (go == true && mounted) {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => const SignUpScreen()));
      }
      return;
    }
    if (!BuddyService.hasConsent) {
      if (!mounted) return;
      final ok = await BuddyScreen.requestAiConsent(context);
      if (!ok || !mounted) return;
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
      if (!mounted) return;
      setState(() {
        _preview = booking;
        _fromReceipt = true;
      });
    } catch (e) {
      // the server's reasons are German; a dropped connection is not
      final s = '$e';
      if (mounted) {
        setState(() => _error = RegExp(r'Exception|Error|Failed|Socket|Timeout').hasMatch(s)
            ? 'Den Beleg konnte Buddy gerade nicht lesen. Prüf die Verbindung und versuch es noch einmal.'
            : s);
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  // saves exactly the booking the user sees
  Future<void> _save() async {
    final booking = _preview;
    if (booking == null) return;
    _refine?.cancel();
    final tx = Transaction(
      id: const Uuid().v4(),
      amountCents: booking.cents,
      category: booking.category,
      date: booking.date,
      isIncome: booking.isIncome,
      note: booking.note.isEmpty ? null : booking.note,
      // on the account open on Konto, like the form
      accountId: MoneyAccounts.byId(AccountScreen.selected.value)?.isMain == false ? AccountScreen.selected.value : null,
    );
    await DB.addTx(tx);
    if (tx.note != null) {
      await CategoryRules.remember(tx.note!, tx.category, isIncome: tx.isIncome);
    }
    HapticFeedback.mediumImpact();
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final needBalance = !OnboardingService.balanceKnown;
    Navigator.pop(context);
    messenger.showSnackBar(SnackBar(
      persist: false,
      duration: const Duration(seconds: 5),
      content: Text('${tx.note ?? tx.category} · ${tx.amountText} gespeichert'),
      action: SnackBarAction(label: 'Rückgängig', onPressed: () => DB.deleteTx(tx.id)),
    ));
    if (needBalance) {
      messenger.showSnackBar(SnackBar(
        duration: const Duration(milliseconds: 3200),
        content: const Text('Damit „noch frei“ stimmt: Kontostand einmal eintragen.'),
        action: SnackBarAction(
          label: 'Kontostand',
          onPressed: () => showBalanceSheet(messenger.context),
        ),
      ));
    }
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
              icon: Icon(Icons.document_scanner_rounded,
                  color: !PlusService.active.value &&
                          PlusService.left(PlusFeature.receiptScan) == 0
                      ? AppColors.textDim
                      : null),
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
          Text(_error!, style: TextStyle(color: AppColors.errorText, fontSize: 13)),
        ],
        if (_preview == null && _busy == null && _text.text.trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          Text('Ich brauche mindestens einen Betrag — z. B. „Kaffee 3,20“.',
              style: TextStyle(color: AppColors.textDim, fontSize: 13, height: 1.35)),
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
        if (!PlusService.active.value) ...[
          const SizedBox(height: 8),
          Text(
            PlusService.left(PlusFeature.receiptScan) == 0
                ? 'Gratis-Beleg-Scans aufgebraucht · Tippen geht weiter'
                : 'Noch ${PlusService.left(PlusFeature.receiptScan)} von ${PlusService.freeReceiptScans} Gratis-Beleg-Scans diesen Monat',
            style: TextStyle(
                fontSize: 12, color: AppColors.primaryText, fontWeight: FontWeight.w600, height: 1.3),
          ),
        ],
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
    final remembered = b.note.isNotEmpty && CategoryRules.forName(b.note, isIncome: b.isIncome) == b.category;
    return Container(
      key: ValueKey('${b.cents}${b.category}${b.note}${b.date}'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.5)),
      ),
      child: Row(children: [
        CategoryAvatar(b.category, isIncome: b.isIncome, merchant: b.note),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(
                '${b.category} · ${Dates.relativeDay(b.date)}'
                '${remembered ? ' · Merkt sich $title' : ''}'
                '${_fromReceipt ? ' · vom Beleg' : _refining ? ' · Buddy prüft …' : _withoutAi ? ' · Ohne KI erkannt' : ''}',
                style: TextStyle(color: AppColors.textDim, fontSize: 13)),
          ]),
        ),
        // the user's own input, so shown even in privacy mode
        Text('${b.isIncome ? '+' : Money.minus}${Money.raw(b.cents)}',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: b.isIncome ? AppColors.positiveText : AppColors.text)),
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
