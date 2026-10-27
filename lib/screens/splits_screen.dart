import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';
import '../models/split.dart';
import '../models/transaction.dart';
import '../services/account_service.dart';
import '../services/split_service.dart';
import 'auth_screens.dart';
import '../utils/dates.dart';
import '../utils/money.dart';
import '../utils/theme.dart';

// "Geteilt": groups for shared spending (flat share, couple, trip) and who
// owes whom. Kept on this device; the others get their balance as a message.

// the server's own messages are German already; anything technical means no connection
String splitError(Object e) {
  final s = '$e';
  return RegExp(r'Exception|Error|Failed|Socket|Timeout').hasMatch(s)
      ? 'Gerade keine Verbindung. Bitte versuch es gleich noch einmal.'
      : s;
}

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
          appBar: AppBar(title: const Text('Geteilt'), actions: [
            TextButton.icon(
              onPressed: () => joinSplitGroup(context),
              icon: const Icon(Icons.qr_code_rounded, size: 18),
              label: const Text('Mit Code beitreten'),
            ),
          ]),
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
                            color: total > 0 ? AppColors.positiveText : (total < 0 ? AppColors.errorText : AppColors.text))),
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
            const SizedBox(height: 8),
            TextButton(onPressed: () => joinSplitGroup(context), child: const Text('Ich habe einen Einladungscode')),
          ]),
        ),
      );
}

class _GroupTile extends StatelessWidget {
  final SplitGroup group;
  const _GroupTile(this.group);

  @override
  Widget build(BuildContext context) {
    final mine = SplitMath.balances(group)[group.me];
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
                  Text('${group.members.length} Personen · ${group.expenses.length} Ausgaben${group.shared ? ' · geteilt' : ''}',
                      style: TextStyle(color: AppColors.textDim, fontSize: 13)),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(mine == 0 ? 'quitt' : Money.format(mine.abs()),
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: mine > 0 ? AppColors.positiveText : (mine < 0 ? AppColors.errorText : AppColors.textDim))),
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

// joins a group someone shared: code first, then who you are in it
Future<void> joinSplitGroup(BuildContext context, {String? code}) async {
  if (AccountService.current.value == null) {
    // the code waits for the sign-up
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(persist: false, duration: const Duration(seconds: 5), 
      content: const Text('Zum Beitreten brauchst du ein kostenloses Konto.'),
      action: SnackBarAction(
        label: 'Konto erstellen',
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SignUpScreen())),
      ),
    ));
    return;
  }
  final group = await showModalBottomSheet<SplitGroup>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    showDragHandle: true,
    builder: (_) => _JoinSheet(code: code),
  );
  // closed without joining: the link is not offered again and again
  if (group == null && code != null) await SplitService.setPendingJoin(null);
  if (group != null && context.mounted) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => SplitGroupScreen(group.id)));
  }
}

class _JoinSheet extends StatefulWidget {
  final String? code; // from an invite link
  const _JoinSheet({this.code});

  @override
  State<_JoinSheet> createState() => _JoinSheetState();
}

class _JoinSheetState extends State<_JoinSheet> {
  late final _code = TextEditingController(text: widget.code ?? '');
  Map<String, dynamic>? _preview;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // with a code from a link, go straight to choosing who you are
    if (widget.code != null) WidgetsBinding.instance.addPostFrameCallback((_) => _look());
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _look() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final p = await SplitService.preview(_code.text);
      if (mounted) setState(() => _preview = p);
    } catch (e) {
      if (mounted) setState(() => _error = splitError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _join(int member) async {
    setState(() => _busy = true);
    try {
      final g = await SplitService.join(_code.text, member);
      HapticFeedback.mediumImpact();
      if (mounted) Navigator.pop(context, g);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = splitError(e);
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _preview;
    final taken = ((p?['taken'] as List?) ?? const []).map((e) => (e as num).toInt()).toSet();
    final members = ((p?['members'] as List?) ?? const []).cast<String>();
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(p == null ? 'Mit Code beitreten' : '${p['emoji']} ${p['name']}',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 14),
        if (p == null) ...[
          TextField(
            controller: _code,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: 6),
            onSubmitted: (_) => _look(),
            decoration: InputDecoration(hintText: 'CODE', errorText: _error),
          ),
          const SizedBox(height: 16),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: _busy ? null : _look,
            child: const Text('Weiter', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
        ] else ...[
          Text('Wer bist du in der Gruppe?', style: TextStyle(color: AppColors.textDim)),
          const SizedBox(height: 8),
          for (var i = 0; i < members.length; i++)
            ListTile(
              enabled: !taken.contains(i) && !_busy,
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: AppColors.primary.withValues(alpha: taken.contains(i) ? 0.06 : 0.18),
                child: Text(members[i].isEmpty ? '?' : members[i][0].toUpperCase(),
                    style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800)),
              ),
              title: Text(members[i], style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: taken.contains(i) ? const Text('schon dabei') : null,
              trailing: taken.contains(i) ? null : const Icon(Icons.chevron_right_rounded),
              onTap: () => _join(i),
            ),
          if (_error != null) Text(_error!, style: TextStyle(color: AppColors.errorText)),
        ],
      ]),
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

class SplitGroupScreen extends StatefulWidget {
  final String id;
  const SplitGroupScreen(this.id, {super.key});

  @override
  State<SplitGroupScreen> createState() => _SplitGroupScreenState();
}

class _SplitGroupScreenState extends State<SplitGroupScreen> {
  String? _syncError;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  // shared groups fetch what the others added; looking at it marks it as seen
  Future<void> _refresh() async {
    final g = SplitService.byId(widget.id);
    if (g == null) return;
    if (!g.shared) return SplitService.markSeen(g);
    try {
      await SplitService.markSeen(await SplitService.refresh(g));
      if (mounted) setState(() => _syncError = null);
    } catch (e) {
      if (mounted) setState(() => _syncError = splitError(e));
    }
  }

  // runs a change and reports a failure instead of losing it silently

  // deleting a group, or leaving a shared one, loses every expense in it: asked first
  Future<void> _remove(BuildContext context, SplitGroup g, int mine) async {
    final creator = g.shared && g.me == 0;
    final open = mine == 0
        ? ''
        : mine > 0
            ? '\n\nDu bekommst noch ${Money.raw(mine)}.'
            : '\n\nDu schuldest noch ${Money.raw(-mine)}.';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(g.shared ? (creator ? 'Gruppe für alle löschen?' : 'Gruppe verlassen?') : 'Gruppe löschen?'),
        content: Text('${g.shared && creator ? 'Alle Mitglieder verlieren „${g.name}“ mit allen Ausgaben.' : 'Alle Ausgaben in „${g.name}“ sind dann von diesem Gerät weg.'}$open'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: Text(g.shared && !creator ? 'Verlassen' : 'Löschen'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await SplitService.remove(g);
    } catch (_) {
      if (!context.mounted) return;
      // offline: the others would not notice; removing only here is the user's call
      final local = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Gerade keine Verbindung'),
          content: const Text('Die anderen bekommen das erst mit, wenn du wieder online bist. '
              'Nur von diesem Gerät entfernen?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Später')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Nur hier entfernen')),
          ],
        ),
      );
      if (local != true || !context.mounted) return;
      await SplitService.remove(g, localOnly: true);
    }
    HapticFeedback.mediumImpact();
    if (context.mounted) Navigator.pop(context);
  }

  // swiped away: removed at once with an undo; offline the row simply stays
  Future<bool> _removeExpense(SplitGroup g, SplitExpense e) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await SplitService.removeExpense(g, e.id);
    } catch (err) {
      messenger.showSnackBar(SnackBar(duration: const Duration(milliseconds: 2800), content: Text(splitError(err))));
      return false;
    }
    HapticFeedback.mediumImpact();
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      duration: const Duration(seconds: 5),
      content: Text('„${e.title}“ entfernt'),
      action: SnackBarAction(label: 'Rückgängig', onPressed: () {
        final now = SplitService.byId(g.id);
        if (now != null) SplitService.addExpense(now, e);
      }),
    ));
    // the box already dropped the row; returning false avoids a lingering dismissed tile
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Box>(
      valueListenable: Hive.box('splits').listenable(keys: [widget.id]),
      builder: (context, _, __) {
        final g = SplitService.byId(widget.id);
        if (g == null) return const Scaffold();
        final mine = SplitMath.balances(g)[g.me];
        final transfers = SplitMath.settleUp(g);
        String who(int i) => i == g.me ? 'Du' : g.members[i];
        return Scaffold(
          appBar: AppBar(
            title: Text('${g.emoji} ${g.name}'),
            actions: [
              IconButton(
                tooltip: 'Einladen',
                icon: const Icon(Icons.person_add_alt_1_rounded),
                onPressed: () => _invite(context, g),
              ),
              PopupMenuButton<String>(
                tooltip: 'Mehr',
                color: AppColors.surfaceAlt,
                onSelected: (_) => _remove(context, g, mine),
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'delete', child: Text(g.shared ? 'Gruppe verlassen' : 'Gruppe löschen')),
                ],
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => addSplitExpense(context, g),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Ausgabe', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          body: RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
              children: [
                if (g.shared)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(children: [
                      Icon(_syncError == null ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
                          size: 16, color: _syncError == null ? AppColors.positive : AppColors.warning),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                            _syncError == null
                                ? 'Geteilt mit der Gruppe · Code ${g.code}'
                                : 'Gerade offline, zeigt den letzten Stand',
                            style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
                      ),
                    ]),
                  ),
                Text(mine == 0 ? 'Ihr seid quitt' : (mine > 0 ? 'Du bekommst' : 'Du schuldest'),
                    style: TextStyle(color: AppColors.textDim)),
                Text(mine == 0 ? '🤝' : Money.format(mine.abs()),
                    style: TextStyle(
                        fontSize: 38,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1.2,
                        color: mine > 0 ? AppColors.positiveText : (mine < 0 ? AppColors.errorText : AppColors.text))),
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
                        if (t.to == g.me)
                          TextButton(onPressed: () => _remind(context, g, t), child: const Text('Erinnern')),
                        // only the people involved confirm a payment
                        if (t.from == g.me || t.to == g.me)
                          TextButton(
                            onPressed: () => _settle(context, g, t, who),
                            child: Text(t.from == g.me ? 'Bezahlt' : 'Erhalten'),
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
                    confirmDismiss: (_) => _removeExpense(g, e),
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(e.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                          '${who(e.paidBy)} ${e.paidBy == g.me ? 'hast' : 'hat'} bezahlt · ${Dates.dayMonth(e.date)}'
                          '${e.shares.containsKey(g.me) ? ' · dein Anteil ${Money.format(e.shares[g.me]!)}' : ''}',
                          style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
                      trailing: Text(Money.format(e.cents), style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                // money that changed hands, newest first, so a settled debt stays traceable
                if (g.settlements.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Text('Ausgeglichen',
                      style: TextStyle(color: AppColors.textDim, fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 6),
                  for (final st in g.settlements.reversed)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.swap_horiz_rounded, color: AppColors.textDim),
                      title: Text('${who(st.from)} → ${who(st.to)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(Dates.dayMonth(st.date), style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
                      trailing: Text(Money.format(st.cents), style: TextStyle(color: AppColors.textDim)),
                    ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  // money changing hands is confirmed with the amount, and can be taken back
  Future<void> _settle(BuildContext context, SplitGroup g, Transfer t,
      String Function(int) who) async {
    final paid = t.from == g.me;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(paid ? 'Bezahlt?' : 'Erhalten?'),
        content: Text(paid
            ? 'Du hast ${who(t.to)} ${Money.raw(t.cents)} gegeben?'
            : '${who(t.from)} hat dir ${Money.raw(t.cents)} gegeben?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Ja, ausgleichen')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(this.context);
    try {
      await SplitService.settle(g, Settlement(t.from, t.to, t.cents, DateTime.now()));
    } catch (e) {
      messenger.showSnackBar(SnackBar(duration: const Duration(milliseconds: 2800), content: Text(splitError(e))));
      return;
    }
    HapticFeedback.mediumImpact();
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      duration: const Duration(seconds: 5),
      content: Text('${Money.raw(t.cents)} ausgeglichen'),
      // taken back by the same amount the other way, so every device agrees
      action: SnackBarAction(label: 'Rückgängig', onPressed: () {
        final now = SplitService.byId(g.id);
        if (now != null) SplitService.settle(now, Settlement(t.to, t.from, t.cents, DateTime.now()));
      }),
    ));
  }

  // shares the group through the server and hands out the code
  Future<void> _invite(BuildContext context, SplitGroup g) async {
    final account = AccountService.current.value;
    if (account == null) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('Gemeinsam rechnen'),
          content: const Text('Damit alle in der Gruppe denselben Stand sehen, braucht ihr jeweils ein '
              'kostenloses BudgetBuddy-Konto.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Später')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Konto erstellen')),
          ],
        ),
      );
      if (ok == true && context.mounted) {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const SignUpScreen()));
      }
      return;
    }
    var group = g;
    if (!group.shared) {
      try {
        group = await SplitService.share(group, account.firstName);
      } catch (e) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(duration: const Duration(milliseconds: 2800), content: Text(splitError(e))));
        return;
      }
    }
    if (!context.mounted) return;
    final link = SplitService.inviteLink(group.code ?? '');
    final text = 'Komm in unsere Gruppe „${group.name}“ bei BudgetBuddy, dann sehen wir alle, wer wem was schuldet. '
        '${link != null ? 'Einfach hier tippen: $link\n' : ''}Code: ${group.code}';
    await showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Leute einladen', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('Sie tippen in BudgetBuddy unter „Geteilt“ auf „Mit Code beitreten“.',
                style: TextStyle(color: AppColors.textDim, height: 1.4)),
            const SizedBox(height: 18),
            Center(
              child: SelectableText(group.code ?? '',
                  style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w900, letterSpacing: 8)),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: () async {
                try {
                  await Share.share(text);
                } catch (_) {
                  await Clipboard.setData(ClipboardData(text: text));
                }
              },
              icon: const Icon(Icons.ios_share_rounded),
              label: const Text('Einladung senden'),
            ),
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: group.code ?? ''));
                if (context.mounted) Navigator.pop(context);
              },
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: const Text('Code kopieren'),
            ),
          ]),
        ),
      ),
    );
  }

  // a friendly message with the amount, through the share sheet
  Future<void> _remind(BuildContext context, SplitGroup g, Transfer t) async {
    final text = 'Hey ${g.members[t.from]} 👋 kleine Erinnerung: Aus „${g.name}“ bekomme ich noch '
        '${Money.raw(t.cents)} von dir. Danke dir! (aus BudgetBuddy)';
    try {
      await Share.share(text);
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: text));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(duration: Duration(milliseconds: 2800), content: Text('Nachricht kopiert')));
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
  late int _paidBy = widget.group.me;
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
    final share = SplitExpense.even(cents, _among.toList()..sort());
    try {
      await SplitService.addExpense(
          g,
          SplitExpense(
            id: const Uuid().v4(),
            title: _title.text.trim().isEmpty ? 'Ausgabe' : _title.text.trim(),
            cents: cents,
            paidBy: _paidBy,
            shares: share,
            date: widget.tx?.date ?? DateTime.now(),
            txId: widget.tx?.id,
          ));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(duration: const Duration(milliseconds: 2800), content: Text(splitError(e))));
      return;
    }
    HapticFeedback.mediumImpact();
    if (!mounted) return;
    Navigator.pop(context);
    final others = _paidBy == g.me ? cents - (share[g.me] ?? 0) : 0;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(duration: const Duration(milliseconds: 2800), 
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
              label: Text(i == widget.group.me ? 'Ich' : members[i]),
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
              label: Text(i == widget.group.me ? 'Ich' : members[i]),
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
