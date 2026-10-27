import 'package:flutter/material.dart';
import '../widgets/big_number.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../models/money_account.dart';
import '../models/transaction.dart';
import '../services/money_accounts.dart';
import 'account_screen.dart';
import '../models/recurring.dart';
import '../services/db.dart';
import '../services/recurring_service.dart';
import '../utils/amount_input.dart';
import '../utils/dates.dart';
import '../utils/theme.dart';
import '../utils/money.dart';
import '../widgets/segmented.dart';

// Fast entry: a big amount on top, category chips, date/repeat chips and an
// on-screen number pad. A physical keyboard works too (digits, comma, Enter).
class AddScreen extends StatefulWidget {
  // tx = null → create new transaction
  // tx = given → update existing transaction
  final Transaction? tx;

  const AddScreen({super.key, this.tx});

  @override
  State<AddScreen> createState() => _AddScreenState();
}

class _AddScreenState extends State<AddScreen> {
  final _noteCtrl = TextEditingController();
  // while the description is typed the keyboard needs the room of the number pad
  final _noteFocus = FocusNode();

  // form state variables
  String _amount = '';         // typed amount, e.g. "12,5"
  bool _isIncome = false;      // false = expense, true = income
  bool _refund = false;        // money back for a purchase: income under a spending category
  String? _category;
  DateTime _date = DateTime.now();
  String _repeat = 'Einmalig';  // 'Einmalig' or one of RecurringService.intervals
  bool _isSaving = false;
  // the account it is booked on (null = main): the one open on Konto by default
  String? _account = AccountScreen.selected.value;

  // helper to check if we're editing or adding
  bool get _isEdit => widget.tx != null;

  bool get _canSave => AmountInput.cents(_amount) > 0 && _category != null && !_isSaving;

  @override
  void initState() {
    super.initState();
    // if editing -> fill form with existing data
    if (_isEdit) {
      final t = widget.tx!;
      _amount = AmountInput.fromCents(t.amountCents);
      _noteCtrl.text = t.note ?? '';
      _isIncome = t.isIncome;
      _refund = t.isRefund;
      _category = t.category;
      _date = t.date;
      _account = t.accountId;
    }
    _noteFocus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    _noteFocus.dispose();
    super.dispose();
  }

  bool get _typingNote => _noteFocus.hasFocus;

  // recent merchants of the current type: one tap fills note, amount and
  // category; while typing a description they narrow down to matches
  List<Transaction> get _recentMerchants {
    final typed = _noteCtrl.text.trim().toLowerCase();
    final seen = <String>{};
    final out = <Transaction>[];
    for (final t in DB.getTx()) {
      final name = t.note?.trim() ?? '';
      if (t.isIncome != _isIncome || t.isRefund != _refund || name.isEmpty || !seen.add(name.toLowerCase())) continue;
      if (typed.isNotEmpty && (!name.toLowerCase().startsWith(typed) || name.toLowerCase() == typed)) continue;
      out.add(t);
      if (out.length == 6) break;
    }
    return out;
  }

  void _useMerchant(Transaction t) {
    HapticFeedback.selectionClick();
    setState(() {
      _noteCtrl.text = t.note!.trim();
      _category = t.category;
      if (_amount.isEmpty) _amount = AmountInput.fromCents(t.amountCents);
    });
  }

  Widget _suggestions() {
    final list = _recentMerchants;
    // only while it helps: nothing typed yet, or a description being typed
    if (list.isEmpty || (_amount.isNotEmpty && _noteCtrl.text.trim().isEmpty)) return const SizedBox(height: 0);
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: SizedBox(
        height: 44,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, i) {
            final t = list[i];
            return Material(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(22),
              child: InkWell(
                borderRadius: BorderRadius.circular(22),
                onTap: () => _useMerchant(t),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
                  child: Row(children: [
                    CategoryAvatar(t.category, isIncome: t.isIncome, merchant: t.note, size: 30),
                    const SizedBox(width: 8),
                    Text(t.note!.trim(), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                    const SizedBox(width: 6),
                    Text(Money.format(t.amountCents), style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
                  ]),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // categories of the current type, the most used ones first
  List<String> get _categories {
    // a refund goes back to what was bought: the spending categories
    final names = (_refund
            ? Categories.expense.where((c) => Categories.isExpenseOnly(c['name']!))
            : _isIncome
                ? Categories.income
                : Categories.expense)
        .map((c) => c['name']!)
        .toList();
    final usage = <String, int>{};
    for (final t in DB.getTx()) {
      if (t.isIncome == _isIncome) usage[t.category] = (usage[t.category] ?? 0) + 1;
    }
    names.sort((a, b) => (usage[b] ?? 0).compareTo(usage[a] ?? 0));
    return names;
  }

  void _press(String key) {
    final next = AmountInput.press(_amount, key);
    if (next == _amount) return;
    HapticFeedback.selectionClick();
    setState(() => _amount = next);
  }

  // physical keyboard: digits, comma/dot, backspace and Enter
  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final ch = e.character;
    if (e.logicalKey == LogicalKeyboardKey.backspace) {
      _press('del');
    } else if (e.logicalKey == LogicalKeyboardKey.enter) {
      if (_canSave) _save();
    } else if (ch != null && RegExp(r'^\d$').hasMatch(ch)) {
      _press(ch);
    } else if (ch == ',' || ch == '.') {
      _press(',');
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final color = _isIncome ? AppColors.positive : AppColors.text;
    final sign = _amount.isEmpty ? '' : (_isIncome ? '+' : Money.minus);

    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isEdit ? 'Bearbeiten' : 'Neuer Umsatz'),
          actions: [
            if (_isEdit)
              IconButton(tooltip: 'Löschen', icon: const Icon(Icons.delete_outline_rounded), onPressed: _delete),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Segmented(
                  labels: const ['Ausgabe', 'Einnahme', 'Erstattung'],
                  index: _refund ? 2 : (_isIncome ? 1 : 0),
                  onChanged: (i) => setState(() {
                    _isIncome = i != 0;
                    _refund = i == 2;
                    // expense, income and refund have different categories
                    if (!_categories.contains(_category)) _category = null;
                  }),
                ),
              ),

              // big amount, grows with the input; scrolls when the keyboard leaves little room
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 150),
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 56,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -2,
                            color: _amount.isEmpty ? AppColors.textDim : color,
                          ),
                          child: Text('$sign${AmountInput.display(_amount)} €'),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // optional description as a quiet inline field
                    SizedBox(
                      width: 260,
                      child: TextField(
                        controller: _noteCtrl,
                        focusNode: _noteFocus,
                        textCapitalization: TextCapitalization.sentences,
                        textAlign: TextAlign.center,
                        maxLength: 60,
                        style: TextStyle(color: AppColors.text),
                        decoration: InputDecoration(
                          hintText: 'Beschreibung hinzufügen',
                          hintStyle: TextStyle(color: AppColors.textDim),
                          counterText: '',
                          filled: false,
                          border: InputBorder.none,
                          focusedBorder: InputBorder.none,
                        ),
                        onSubmitted: (_) => FocusScope.of(context).unfocus(),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    if (!_isEdit) _suggestions(),
                  ],
                    ),
                  ),
                ),
              ),

              _categoryChips(),
              if (!_typingNote) ...[
                const SizedBox(height: 12),
                _optionChips(),
                const SizedBox(height: 8),
                _numberPad(),
              ] else
                const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _canSave ? _save : null,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      disabledBackgroundColor: AppColors.surfaceAlt,
                      disabledForegroundColor: AppColors.textDim,
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : Text(_category == null && AmountInput.cents(_amount) > 0
                            ? 'Kategorie wählen'
                            : (_isEdit ? 'Aktualisieren' : 'Speichern')),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // horizontally scrolling category chips
  Widget _categoryChips() {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: _categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final c = _categories[i];
          final selected = c == _category;
          final tint = Categories.color(c);
          return Semantics(
            button: true,
            selected: selected,
            child: GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _category = c);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: selected ? tint.withValues(alpha: 0.2) : AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: selected ? tint : Colors.transparent),
              ),
              child: Row(
                children: [
                  Icon(Categories.icon(c), size: 18, color: tint),
                  const SizedBox(width: 6),
                  Text(c,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.text,
                      )),
                ],
              ),
            ),
          ));
        },
      ),
    );
  }

  // date and repeat as small chips
  Widget _optionChips() {
    final now = DateTime.now();
    final isToday = _date.year == now.year && _date.month == now.month && _date.day == now.day;
    final accounts = MoneyAccounts.all;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _chip(Icons.calendar_today_rounded, isToday ? 'Heute' : Dates.relativeDay(_date), _openDatePicker),
          if (accounts.length > 1)
            PopupMenuButton<String>(
              tooltip: 'Konto',
              color: AppColors.surface,
              initialValue: _account ?? MoneyAccount.main,
              onSelected: (v) => setState(() => _account = v == MoneyAccount.main ? null : v),
              itemBuilder: (_) => [for (final a in accounts) PopupMenuItem(value: a.id, child: Text(a.name))],
              child: _chip(Icons.account_balance_wallet_rounded,
                  (MoneyAccounts.byId(_account) ?? MoneyAccounts.main).name, null),
            ),
          if (!_isEdit) ...[
            PopupMenuButton<String>(
              tooltip: 'Wiederholen',
              color: AppColors.surface,
              initialValue: _repeat,
              onSelected: (v) => setState(() {
                _repeat = v;
                // a one-off booking cannot lie in the future
                if (v == 'Einmalig' && _date.isAfter(DateTime.now())) _date = DateTime.now();
              }),
              itemBuilder: (_) => [
                for (final o in ['Einmalig', ...RecurringService.intervals])
                  PopupMenuItem(value: o, child: Text(o)),
              ],
              child: _chip(Icons.repeat_rounded, _repeat, null),
            ),
          ],
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String label, VoidCallback? onTap) {
    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: AppColors.textDim),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      ]),
    );
    return onTap == null ? content : Semantics(button: true, child: GestureDetector(onTap: onTap, child: content));
  }

  // 3x4 number pad; long-press on delete clears everything
  Widget _numberPad() {
    const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', ',', '0', 'del'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: 2.4,
        children: [
          for (final k in keys)
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => _press(k),
              onLongPress: k == 'del'
                  ? () {
                      HapticFeedback.mediumImpact();
                      setState(() => _amount = '');
                    }
                  : null,
              child: Center(
                child: k == 'del'
                    ? Icon(Icons.backspace_outlined, color: AppColors.text, semanticLabel: 'Löschen, lang drücken leert')
                    : Text(k, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w500)),
              ),
            ),
        ],
      ),
    );
  }

  // opens the date picker dialog
  // A booking happened on a day up to today; only a repeating one may start
  // later. Older bookings (imports, years of history) stay editable.
  void _openDatePicker() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final first = _date.isBefore(DateTime(2000)) ? _date : DateTime(2000);
    final last = _repeat == 'Einmalig' ? today : DateTime(now.year + 1, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _date.isAfter(last) ? last : _date,
      firstDate: first,
      lastDate: last,
      helpText: _repeat == 'Einmalig' ? 'Wann war das?' : 'Ab wann?',
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _delete() async {
    final tx = widget.tx!;
    final messenger = ScaffoldMessenger.of(context);
    HapticFeedback.mediumImpact();
    await DB.deleteTx(tx.id);
    if (!mounted) return;
    Navigator.pop(context, true);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      duration: const Duration(seconds: 5),
      content: const Text('Umsatz gelöscht'),
      action: SnackBarAction(label: 'Rückgängig', onPressed: () => DB.addTx(tx)),
    ));
  }

  // a repeating booking that starts in the past fills in every date up to today
  Future<bool> _confirmBackfill(RecurringRule rule) async {
    final count = RecurringService.dueOccurrences(rule, DateTime.now()).length;
    if (count <= 1) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$count Umsätze nachtragen?'),
        content: Text('Der Beginn liegt in der Vergangenheit. BudgetBuddy trägt jeden ${rule.interval}en Termin '
            'bis heute nach, also $count Umsätze über zusammen ${Money.raw(rule.amountCents * count)}.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Datum ändern')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Nachtragen')),
        ],
      ),
    );
    return ok == true;
  }

  // saves the transaction (or a recurring rule) to the database
  void _save() async {
    setState(() => _isSaving = true);
    try {
      final cents = AmountInput.cents(_amount);
      final date = DateTime(_date.year, _date.month, _date.day);
      final note = _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim();

      if (!_isEdit && _repeat != 'Einmalig') {
        // create a recurring rule; the engine generates the due transactions
        final rule = RecurringRule(
          id: const Uuid().v4(),
          amountCents: cents,
          category: _category!,
          isIncome: _isIncome,
          note: note,
          interval: _repeat,
          startDate: date,
        );
        if (!await _confirmBackfill(rule)) return;
        await DB.addRule(rule);
        await RecurringService.process();
      } else {
        // one-off transaction (also the path for editing)
        await DB.addTx(Transaction(
          id: _isEdit ? widget.tx!.id : const Uuid().v4(),
          amountCents: cents,
          category: _category!,
          date: date,
          isIncome: _isIncome,
          note: note,
          accountId: _account == MoneyAccount.main ? null : _account,
        ));
        await DB.checkBadges();
      }
      HapticFeedback.lightImpact();
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            duration: Duration(milliseconds: 2800),
            content: Text('Speichern hat nicht geklappt. Bitte versuch es noch einmal.')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}
