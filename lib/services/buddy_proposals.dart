// What Buddy proposes to do, and the small charts he shows under an answer.
// The agent's action tools only create these; nothing is stored until the
// person taps Übernehmen on the card. Then [apply] does the work and says
// in one line what happened.
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../models/budget.dart';
import '../models/goal.dart';
import '../utils/money.dart';
import 'account_service.dart';
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

  Future<String> apply({DateTime? now}) async {
    final today = now ?? DateTime.now();
    switch (kind) {
      case ProposalKind.budget:
        await DB.addBudget(Budget(
          category: '${data['kategorie']}',
          limitCents: data['cents'] as int,
          startDate: DateTime(today.year, today.month, 1),
          endDate: DateTime(today.year, today.month + 1, 0),
        ));
        return 'Budget für ${data['kategorie']} steht.';
      case ProposalKind.goal:
        final deadline = data['bis'] as DateTime?;
        await GoalsService.save(Goal(
          id: const Uuid().v4(),
          name: '${data['name']}',
          emoji: '🎯',
          targetCents: data['cents'] as int,
          deadline: deadline,
          createdAt: today,
          monthlyCents: (data['monthlyCents'] as int?) ?? 0,
        ));
        return 'Sparziel ${data['name']} ist angelegt.';
      case ProposalKind.cancel:
        await Clipboard.setData(ClipboardData(text: '${data['letter']}'));
        return 'Kündigung kopiert. Schick sie per Mail oder über das Kündigungsformular.';
      case ProposalKind.category:
        final name = '${data['haendler']}'.toLowerCase();
        final category = '${data['kategorie']}';
        final hit = DB.getTx().where((t) => (t.note ?? '').toLowerCase().contains(name) && t.category != category);
        if (hit.isEmpty) {
          await CategoryRules.remember('${data['haendler']}', category, isIncome: false);
          return 'Neue Buchungen von ${data['haendler']} landen in $category.';
        }
        final first = hit.first;
        final moved = await CategoryRules.applyToAll(first, category);
        await DB.addTx(first.withCategory(category));
        return '${moved + 1} Buchungen sind jetzt in $category.';
      case ProposalKind.reminder:
        await BuddyTasks.add('${data['text']}', due: data['datum'] as DateTime?);
        return 'Notiert. Buddy erinnert dich.';
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
