import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';
import '../models/split.dart';
import '../models/transaction.dart';
import '../services/split_service.dart';
import '../utils/dates.dart';
import '../utils/money.dart';
import '../utils/theme.dart';

// "Geteilt": groups for shared spending (flat share, couple, trip) and who
// owes whom. Kept on this device; the others get their balance as a message.
class SplitsScreen extends StatelessWidget {
  const SplitsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Box>(
      valueListenable: Hive.box('splits').listenable(),
      builder: (context, _, __) {
        final groups = SplitService.all();
        final total = SplitService.myTotal();
        return Scaffold(
          appBar: AppBar(title: const Text('Geteilt')),
          floatingActionButton: groups.isEmpty
              ? null
              : FloatingActionButton.extended(
                  onPressed: () => newSplitGroup(context),
                  icon: const Icon(Icons.group_add_rounded),
                  label: const Text('Neue Gruppe', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
          body: groups.isEmpty
              ? _empty(context)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
                  children: [
                    Text(total == 0 ? 'Alles ausgeglichen' : (total > 0 ? 'Du bekommst insgesamt' : 'Du schuldest insgesamt'),
                        style: TextStyle(color: AppColors.textDim)),
                    const SizedBox(height: 4),
                    Text(total == 0 ? '🤝' : Money.format(total.abs()),
                        style: TextStyle(
                            fontSize: 38,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1.2,
                            color: total > 0 ? AppColors.positive : (total < 0 ? AppColors.error : AppColors.text))),
                    const SizedBox(height: 20),
                    for (final g in groups) _GroupTile(g),
                  ],
                ),
        );
      },
    );
  }

  Widget _empty(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('🍕', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 14),
            const Text('Ausgaben teilen, ohne Rechnerei',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text('WG-Einkauf, Urlaub, Pizza-Abend: Trag ein, wer was bezahlt hat. BudgetBuddy sagt, wer wem '
                'wie viel schuldet, mit so wenigen Überweisungen wie möglich.',
                textAlign: TextAlign.center, style: TextStyle(color: AppColors.textDim, height: 1.4)),
            const SizedBox(height: 22),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size(220, 50)),
              onPressed: () => newSplitGroup(context),
              icon: const Icon(Icons.group_add_rounded),
              label: const Text('Erste Gruppe anlegen'),
            ),
          ]),
        ),
      );
}

class _GroupTile extends StatelessWidget {
  final SplitGroup group;
  const _GroupTile(this.group);

  @override
  Widget build(BuildContext context) {
    final mine = SplitMath.balances(group)[0];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SplitGroupScreen(group.id))),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(16)),
                child: Text(group.emoji, style: const TextStyle(fontSize: 24)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(group.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  Text('${group.members.length} Personen · ${group.expenses.length} Ausgaben',
                      style: TextStyle(color: AppColors.textDim, fontSize: 13)),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(mine == 0 ? 'quitt' : Money.format(mine.abs()),
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: mine > 0 ? AppColors.positive : (mine < 0 ? AppColors.error : AppColors.textDim))),
                if (mine != 0)
                  Text(mine > 0 ? 'bekommst du' : 'schuldest du',
                      style: TextStyle(color: AppColors.textDim, fontSize: 12)),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

// a new group: name, emoji and the people in it
Future<SplitGroup?> newSplitGroup(BuildContext context) => showModalBottomSheet<SplitGroup>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      builder: (_) => const _NewGroupSheet(),
    );

class _NewGroupSheet extends StatefulWidget {
  const _NewGroupSheet();

  @override
  State<_NewGroupSheet> createState() => _NewGroupSheetState();
}

class _NewGroupSheetState extends State<_NewGroupSheet> {
  static const _presets = [('🏠', 'WG'), ('💑', 'Wir zwei'), ('✈️', 'Urlaub'), ('🍕', 'Freunde')];
  final _name = TextEditingController(text: 'WG');
  final _person = TextEditingController();
  final _personFocus = FocusNode();
  final _people = <String>[];
  String _emoji = '🏠';

  @override
  void dispose() {
    _name.dispose();
    _person.dispose();
    _personFocus.dispose();
    super.dispose();
  }

  void _addPerson() {
    final name = _person.text.trim();
    if (name.isEmpty || _people.contains(name)) return;
    HapticFeedback.selectionClick();
    setState(() {
      _people.add(name);
      _person.clear();
    });
    // ready for the next name right away
    _personFocus.requestFocus();
  }

  Future<void> _save() async {
    _addPerson();
    if (_people.isEmpty) return;
    final g = SplitGroup(
      id: const Uuid().v4(),
      name: _name.text.trim().isEmpty ? 'Gruppe' : _name.text.trim(),
      emoji: _emoji,
      members: ['Ich', ..._people],
    );
    await SplitService.save(g);
    if (mounted) Navigator.pop(context, g);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Neue Gruppe', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 14),
        Wrap(spacing: 8, children: [
          for (final (emoji, name) in _presets)
            ChoiceChip(
              selected: _emoji == emoji,
              showCheckmark: false,
              side: BorderSide(color: AppColors.border),
              label: Text('$emoji $name'),
              onSelected: (_) => setState(() {
                _emoji = emoji;
                if (_name.text.isEmpty || _presets.any((p) => p.$2 == _name.text)) _name.text = name;
              }),
            ),
        ]),
        const SizedBox(height: 12),
        TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name der Gruppe')),
        const SizedBox(height: 16),
        Text('Wer ist dabei?', style: TextStyle(color: AppColors.textDim, fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          const Chip(label: Text('Ich')),
          for (final p in _people) InputChip(label: Text(p), onDeleted: () => setState(() => _people.remove(p))),
        ]),
        const SizedBox(height: 8),
        TextField(
          controller: _person,
          focusNode: _personFocus,
          textCapitalization: TextCapitalization.words,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _addPerson(),
          decoration: InputDecoration(
            labelText: 'Name hinzufügen',
            suffixIcon: IconButton(icon: const Icon(Icons.person_add_alt_1_rounded), onPressed: _addPerson),
          ),
        ),
        const SizedBox(height: 18),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          onPressed: _people.isEmpty && _person.text.trim().isEmpty ? null : _save,
          child: const Text('Gruppe anlegen', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }
}

class SplitGroupScreen extends StatelessWidget {
  final String id;
  const SplitGroupScreen(this.id, {super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Box>(
      valueListenable: Hive.box('splits').listenable(keys: [id]),
      builder: (context, _, __) {
        final g = SplitService.byId(id);
        if (g == null) return const Scaffold();
        final mine = SplitMath.balances(g)[0];
        final transfers = SplitMath.settleUp(g);
        String who(int i) => i == 0 ? 'Du' : g.members[i];
        return Scaffold(
          appBar: AppBar(
            title: Text('${g.emoji} ${g.name}'),
            actions: [
              PopupMenuButton<String>(
                color: AppColors.surfaceAlt,
                onSelected: (_) async {
                  await SplitService.delete(g.id);
                  if (context.mounted) Navigator.pop(context);
                },
                itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('Gruppe löschen'))],
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => addSplitExpense(context, g),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Ausgabe', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
            children: [
              Text(mine == 0 ? 'Ihr seid quitt' : (mine > 0 ? 'Du bekommst' : 'Du schuldest'),
                  style: TextStyle(color: AppColors.textDim)),
              Text(mine == 0 ? '🤝' : Money.format(mine.abs()),
                  style: TextStyle(
                      fontSize: 38,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1.2,
                      color: mine > 0 ? AppColors.positive : (mine < 0 ? AppColors.error : AppColors.text))),
              if (transfers.isNotEmpty) ...[
                const SizedBox(height: 22),
                Text('So wird es ausgeglichen',
                    style: TextStyle(color: AppColors.textDim, fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 8),
                for (final t in transfers)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
                    child: Row(children: [
                      Expanded(
                        child: Text.rich(TextSpan(children: [
                          TextSpan(text: who(t.from), style: const TextStyle(fontWeight: FontWeight.w700)),
                          TextSpan(text: ' → ', style: TextStyle(color: AppColors.textDim)),
                          TextSpan(text: who(t.to), style: const TextStyle(fontWeight: FontWeight.w700)),
                          TextSpan(text: '   ${Money.format(t.cents)}'),
                        ])),
                      ),
                      if (t.to == 0)
                        TextButton(onPressed: () => _remind(context, g, t), child: const Text('Erinnern')),
                      TextButton(
                        onPressed: () async {
                          g.settlements.add(Settlement(t.from, t.to, t.cents, DateTime.now()));
                          await SplitService.save(g);
                          HapticFeedback.mediumImpact();
                        },
                        child: Text(t.from == 0 ? 'Bezahlt' : 'Erhalten'),
                      ),
                    ]),
                  ),
              ],
              const SizedBox(height: 18),
              Text('Ausgaben', style: TextStyle(color: AppColors.textDim, fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 6),
              if (g.expenses.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Text('Noch nichts eingetragen. Tipp unten auf „Ausgabe“.',
                      style: TextStyle(color: AppColors.textDim)),
                ),
              for (final e in g.expenses.reversed)
                Dismissible(
                  key: ValueKey(e.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    child: const Icon(Icons.delete_rounded, color: AppColors.error),
                  ),
                  onDismissed: (_) async {
                    g.expenses.removeWhere((x) => x.id == e.id);
                    await SplitService.save(g);
                  },
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(e.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('${who(e.paidBy)} ${e.paidBy == 0 ? 'hast' : 'hat'} bezahlt · ${Dates.dayMonth(e.date)}'
                        '${e.shares.containsKey(0) ? ' · dein Anteil ${Money.format(e.shares[0]!)}' : ''}',
                        style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
                    trailing: Text(Money.format(e.cents), style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  // a friendly message with the amount, through the share sheet
  Future<void> _remind(BuildContext context, SplitGroup g, Transfer t) async {
    final text = 'Hey ${g.members[t.from]} 👋 kleine Erinnerung: Aus „${g.name}“ bekomme ich noch '
        '${Money.format(t.cents)} von dir. Danke dir! (aus BudgetBuddy)';
    try {
      await Share.share(text);
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: text));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nachricht kopiert')));
      }
    }
  }
}

// adds a shared expense; [tx] prefills it from a booking the user paid
Future<void> addSplitExpense(BuildContext context, SplitGroup group, {Transaction? tx}) =>
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      builder: (_) => _ExpenseSheet(group, tx),
    );

class _ExpenseSheet extends StatefulWidget {
  final SplitGroup group;
  final Transaction? tx;
  const _ExpenseSheet(this.group, this.tx);

  @override
  State<_ExpenseSheet> createState() => _ExpenseSheetState();
}

class _ExpenseSheetState extends State<_ExpenseSheet> {
  late final _title = TextEditingController(text: widget.tx?.note ?? '');
  late final _amount = TextEditingController(
      text: widget.tx == null
          ? ''
          : '${widget.tx!.amountCents ~/ 100},${(widget.tx!.amountCents % 100).toString().padLeft(2, '0')}');
  int _paidBy = 0;
  late final Set<int> _among = {for (var i = 0; i < widget.group.members.length; i++) i};

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final cents = Money.parseToCents(_amount.text);
    if (cents == null || cents <= 0 || _among.isEmpty) return;
    final g = widget.group;
    g.expenses.add(SplitExpense(
      id: const Uuid().v4(),
      title: _title.text.trim().isEmpty ? 'Ausgabe' : _title.text.trim(),
      cents: cents,
      paidBy: _paidBy,
      shares: SplitExpense.even(cents, _among.toList()..sort()),
      date: widget.tx?.date ?? DateTime.now(),
      txId: widget.tx?.id,
    ));
    await SplitService.save(g);
    HapticFeedback.mediumImpact();
    if (!mounted) return;
    Navigator.pop(context);
    final share = SplitExpense.even(cents, _among.toList()..sort());
    final others = _paidBy == 0 ? cents - (share[0] ?? 0) : 0;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(others > 0
            ? 'Geteilt in ${g.name} · ${Money.format(others)} bekommst du zurück'
            : 'In ${g.name} eingetragen')));
  }

  @override
  Widget build(BuildContext context) {
    final members = widget.group.members;
    final cents = Money.parseToCents(_amount.text) ?? 0;
    final each = _among.isEmpty ? 0 : cents ~/ _among.length;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Ausgabe in ${widget.group.emoji} ${widget.group.name}',
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
        const SizedBox(height: 14),
        TextField(controller: _title, decoration: const InputDecoration(labelText: 'Wofür?')),
        const SizedBox(height: 10),
        TextField(
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() {}),
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          decoration: const InputDecoration(labelText: 'Betrag', suffixText: '€'),
        ),
        const SizedBox(height: 14),
        Text('Bezahlt hat', style: TextStyle(color: AppColors.textDim, fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, children: [
          for (var i = 0; i < members.length; i++)
            ChoiceChip(
              selected: _paidBy == i,
              showCheckmark: false,
              side: BorderSide(color: _paidBy == i ? AppColors.primary : AppColors.border),
              selectedColor: AppColors.primary.withValues(alpha: 0.22),
              label: Text(members[i]),
              onSelected: (_) => setState(() => _paidBy = i),
            ),
        ]),
        const SizedBox(height: 12),
        Text('Aufgeteilt auf${each > 0 ? ' · je ${Money.format(each)}' : ''}',
            style: TextStyle(color: AppColors.textDim, fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, children: [
          for (var i = 0; i < members.length; i++)
            FilterChip(
              selected: _among.contains(i),
              side: BorderSide(color: _among.contains(i) ? AppColors.primary : AppColors.border),
              selectedColor: AppColors.primary.withValues(alpha: 0.22),
              label: Text(members[i]),
              onSelected: (v) => setState(() => v ? _among.add(i) : _among.remove(i)),
            ),
        ]),
        const SizedBox(height: 18),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          onPressed: cents > 0 && _among.isNotEmpty ? _save : null,
          child: const Text('Eintragen', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }
}

// From a booking: pick a group (or start one) and split it there.
Future<void> shareTransaction(BuildContext context, Transaction tx) async {
  var groups = SplitService.all();
  SplitGroup? group;
  if (groups.isEmpty) {
    group = await newSplitGroup(context);
  } else if (groups.length == 1) {
    group = groups.single;
  } else {
    group = await showModalBottomSheet<SplitGroup>(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('Mit wem teilen?', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          ),
          for (final g in groups)
            ListTile(
              leading: Text(g.emoji, style: const TextStyle(fontSize: 24)),
              title: Text(g.name),
              subtitle: Text(g.members.join(', ')),
              onTap: () => Navigator.pop(context, g),
            ),
        ]),
      ),
    );
  }
  if (group != null && context.mounted) await addSplitExpense(context, group, tx: tx);
}
