// What Buddy proposes to do, and the small charts he shows under an answer.
// The agent's action tools only create these; nothing is stored until the
// person taps Übernehmen on the card. Then [apply] does the work and says
// in one line what happened.
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../models/budget.dart';
import '../models/goal.dart';
import '../utils/money.dart';
import '../l10n/l10n.dart';
import 'account_service.dart';
import 'buddy_log.dart';
import 'buddy_tasks.dart';
import 'cancellation_service.dart';
import 'category_rules.dart';
import 'db.dart';
import 'goals_service.dart';

enum ProposalKind { budget, goal, cancel, category, reminder }

class BuddyProposal {
  final ProposalKind kind;
  final String title;
  final String detail;
  final Map<String, dynamic> data;
  const BuddyProposal(this.kind, this.title, this.detail, this.data);

  // the button that confirms it
  String get confirm => switch (kind) {
        ProposalKind.cancel => 'Text kopieren',
        _ => 'Übernehmen',
      };

  // does it, writes it into Buddy's log with the way back, and says what happened
  Future<String> apply({DateTime? now}) async {
    final today = now ?? DateTime.now();
    final (said, undo) = await _do(today);
    await BuddyLog.add(kind.name, title, said, undo, now: today);
    return said;
  }

  Future<(String, Map<String, dynamic>)> _do(DateTime today) async {
    switch (kind) {
      case ProposalKind.budget:
        final start = DateTime(today.year, today.month, 1);
        await DB.addBudget(Budget(
          category: '${data['kategorie']}',
          limitCents: data['cents'] as int,
          startDate: start,
          endDate: DateTime(today.year, today.month + 1, 0),
        ));
        return (tr('Budget für {x} steht.', {'x': data['kategorie']}),
            {'kategorie': data['kategorie'], 'start': start.toIso8601String()});
      case ProposalKind.goal:
        final id = const Uuid().v4();
        await GoalsService.save(Goal(
          id: id,
          name: '${data['name']}',
          emoji: '🎯',
          targetCents: data['cents'] as int,
          deadline: data['bis'] as DateTime?,
          createdAt: today,
          monthlyCents: (data['monthlyCents'] as int?) ?? 0,
        ));
        return (tr('Sparziel {x} ist angelegt.', {'x': data['name']}), {'goalId': id});
      case ProposalKind.cancel:
        await Clipboard.setData(ClipboardData(text: '${data['letter']}'));
        return (tr('Kündigung kopiert. Schick sie per Mail oder über das Kündigungsformular.'), <String, dynamic>{});
      case ProposalKind.category:
        final name = '${data['haendler']}'.toLowerCase();
        final category = '${data['kategorie']}';
        final hit = DB.getTx().where((t) => (t.note ?? '').toLowerCase().contains(name) && t.category != category).toList();
        // what each booking was before, for the way back
        final old = {for (final t in hit) t.id: t.category};
        final before = hit.isEmpty ? '' : hit.first.category;
        for (final t in hit) {
          await DB.addTx(t.withCategory(category));
        }
        await CategoryRules.remember('${data['haendler']}', category, isIncome: false);
        final undo = {'old': old, 'haendler': data['haendler'], 'vorher': before};
        if (hit.isEmpty) {
          return (tr('Neue Buchungen von {x} landen in {y}.', {'x': data['haendler'], 'y': category}), undo);
        }
        return (tr('{n} Buchungen sind jetzt in {y}.', {'n': hit.length, 'y': category}), undo);
      case ProposalKind.reminder:
        final id = await BuddyTasks.add('${data['text']}', due: data['datum'] as DateTime?);
        return (tr('Notiert. Buddy erinnert dich.'), {if (id != null) 'taskId': id});
    }
  }

  // --- built by the agent's tools -----------------------------------------

  static int _cents(dynamic eur) {
    final c = (((eur as num?) ?? 0) * 100).round();
    if (c <= 0) throw const FormatException('betrag fehlt');
    return c;
  }

  static BuddyProposal budget(Map<String, dynamic> input) {
    final category = '${input['kategorie'] ?? ''}'.trim();
    if (category.isEmpty) throw const FormatException('kategorie fehlt');
    final cents = _cents(input['betrag']);
    return BuddyProposal(ProposalKind.budget, 'Budget $category',
        '${Money.format(cents)} im Monat, ab diesem Monat', {'kategorie': category, 'cents': cents});
  }

  static BuddyProposal goal(Map<String, dynamic> input, {required DateTime today}) {
    final name = '${input['name'] ?? ''}'.trim();
    if (name.isEmpty) throw const FormatException('name fehlt');
    final cents = _cents(input['betrag']);
    DateTime? until;
    final m = RegExp(r'^(\d{4})-(\d{2})$').firstMatch('${input['bis'] ?? ''}');
    if (m != null) until = DateTime(int.parse(m.group(1)!), int.parse(m.group(2)!) + 1, 0);
    final monthly = input['monatlich'] == null ? null : _cents(input['monatlich']);
    final parts = [
      Money.format(cents),
      if (until != null) 'bis ${until.month.toString().padLeft(2, '0')}/${until.year}',
      if (monthly != null) '${Money.format(monthly)} im Monat',
    ];
    return BuddyProposal(ProposalKind.goal, 'Sparziel $name', parts.join(' · '),
        {'name': name, 'cents': cents, 'bis': until, 'monthlyCents': monthly});
  }

  static BuddyProposal cancel(Map<String, dynamic> input) {
    final provider = '${input['anbieter'] ?? ''}'.trim();
    if (provider.isEmpty) throw const FormatException('anbieter fehlt');
    String name = '', email = '';
    try {
      final a = AccountService.current.value;
      if (a != null) {
        name = a.name;
        email = a.email;
      }
    } catch (_) {}
    final letter = CancellationService.letter(provider: provider, name: name, email: email);
    return BuddyProposal(ProposalKind.cancel, 'Kündigung $provider', 'Fertiger Text, fristgerecht zum nächstmöglichen Termin',
        {'anbieter': provider, 'letter': letter});
  }

  static BuddyProposal category(Map<String, dynamic> input) {
    final merchant = '${input['haendler'] ?? ''}'.trim();
    final category = '${input['kategorie'] ?? ''}'.trim();
    if (merchant.isEmpty || category.isEmpty) throw const FormatException('haendler und kategorie nötig');
    return BuddyProposal(ProposalKind.category, '$merchant → $category', 'Alle Buchungen und neue in Zukunft',
        {'haendler': merchant, 'kategorie': category});
  }

  static BuddyProposal reminder(Map<String, dynamic> input) {
    final text = '${input['text'] ?? ''}'.trim();
    if (text.isEmpty) throw const FormatException('text fehlt');
    final date = DateTime.tryParse('${input['datum'] ?? ''}');
    final when = date == null ? 'ohne Datum' : '${date.day}.${date.month}.${date.year}';
    return BuddyProposal(ProposalKind.reminder, 'Erinnerung', '$text · $when', {'text': text, 'datum': date});
  }
}

// a small chart under an answer; values in cents
enum ChartKind { months, categories, plan }

class BuddyChart {
  final ChartKind kind;
  final String title;
  // months: label, income, spent · categories: label, value · plan: label, value (target per month)
  final List<({String label, int a, int b})> rows;
  const BuddyChart(this.kind, this.title, this.rows);
}
