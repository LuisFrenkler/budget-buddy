// What Buddy proposes to do, and the small charts he shows under an answer.
// The agent's action tools only create these; nothing is stored until the
// person taps Übernehmen on the card. Then [apply] does the work and says
// in one line what happened.
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../models/budget.dart';
import '../models/goal.dart';
import '../models/transaction.dart';
import '../utils/money.dart';
import '../utils/theme.dart';
import '../l10n/l10n.dart';
import 'account_service.dart';
import 'buddy_log.dart';
import 'buddy_tasks.dart';
import 'cancellation_service.dart';
import 'category_rules.dart';
import 'contracts.dart';
import 'db.dart';
import 'goals_service.dart';
import 'goal_move.dart';
import 'money_accounts.dart';
import 'notification_service.dart';
import 'onboarding_service.dart';
import 'settings_service.dart';

enum ProposalKind { budget, goal, cancel, category, reminder, save, txEdit, txDelete, goalEdit, balance, contractHide, setting }

class BuddyProposal {
  final ProposalKind kind;
  final String title;
  final String detail;
  final Map<String, dynamic> data;
  const BuddyProposal(this.kind, this.title, this.detail, this.data);

  // the button that confirms it
  String get confirm => switch (kind) {
        ProposalKind.cancel => 'Text kopieren',
        ProposalKind.txDelete => 'Löschen',
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
        // a budget of this month is replaced: the way back needs its old limit
        final before = DB.getBudgets().where((b) => b.category == data['kategorie'] && b.startDate == start).firstOrNull;
        await DB.addBudget(Budget(
          category: '${data['kategorie']}',
          limitCents: data['cents'] as int,
          startDate: start,
          endDate: DateTime(today.year, today.month + 1, 0),
        ));
        return (tr('Budget für {x} steht.', {'x': data['kategorie']}), {
          'kategorie': data['kategorie'],
          'start': start.toIso8601String(),
          if (before != null) 'vorherCents': before.limitCents,
        });
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
        return (tr('Notiert. Ahead erinnert dich.'), {if (id != null) 'taskId': id});
      case ProposalKind.save:
        final goal = GoalsService.all().where((g) => g.id == data['goalId']).firstOrNull;
        if (goal == null) throw tr('Das Sparziel gibt es nicht mehr.');
        final r = await GoalMove.apply(goal: goal, cents: data['cents'] as int, take: false);
        if (r.moved <= 0) return (tr('{x} ist schon voll.', {'x': goal.name}), <String, dynamic>{});
        return (
          r.booked
              ? tr('{x} auf {y} umgebucht. Richte die Überweisung bei deiner Bank genauso ein.',
                  {'x': Money.format(r.moved), 'y': r.potName ?? tr('Sparkonto')})
              : tr('{x} für {y} zurückgelegt.', {'x': Money.format(r.moved), 'y': goal.name}),
          {'goalId': goal.id, 'cents': r.moved}
        );
      case ProposalKind.txEdit || ProposalKind.txDelete:
        final old = DB.getTx().where((t) => t.id == data['id']).firstOrNull;
        if (old == null) throw tr('Die Buchung gibt es nicht mehr.');
        if (kind == ProposalKind.txDelete) {
          await DB.deleteTx(old.id);
          return (tr('Buchung gelöscht.'), {'tx': old.toMap()});
        }
        await DB.addTx(Transaction.fromMap({...old.toMap(), ...data['neu'] as Map<String, dynamic>}));
        return (tr('Buchung geändert.'), {'tx': old.toMap()});
      case ProposalKind.goalEdit:
        final goal = GoalsService.all().where((g) => g.id == data['goalId']).firstOrNull;
        if (goal == null) throw tr('Das Sparziel gibt es nicht mehr.');
        final neu = data['neu'] as Map<String, dynamic>;
        final was = goal.toMap();
        await GoalsService.save(Goal.fromMap({...was, ...neu}));
        return (tr('Sparziel {x} ist geändert.', {'x': goal.name}), {
          'goalId': goal.id,
          'vorher': {for (final k in neu.keys) k: was[k]}
        });
      case ProposalKind.balance:
        final account = MoneyAccounts.byId(data['konto'] as String?) ?? MoneyAccounts.main;
        final before = MoneyAccounts.balanceOf(account, DB.getTx());
        await OnboardingService.setCurrentBalance(data['cents'] as int, account: account);
        return (tr('{x} steht jetzt bei {y}.', {'x': account.name, 'y': Money.format(data['cents'] as int)}),
            {'konto': account.id, 'cents': before});
      case ProposalKind.contractHide:
        await Contracts.hide('${data['name']}');
        return (tr('{x} zählt nicht mehr als Vertrag.', {'x': data['name']}), {'name': data['name']});
      case ProposalKind.setting:
        final was = '${data['was']}';
        final before = settingNow(was);
        await setSetting(was, '${data['wert']}');
        return (tr('{x} ist umgestellt.', {'x': data['label']}), {'was': was, 'wert': before});
    }
  }

  // the way back for the cards the log does not know itself
  static Future<void> undo(String kind, Map<String, dynamic> u) async {
    switch (kind) {
      case 'txEdit' || 'txDelete':
        await DB.addTx(Transaction.fromMap(Map<String, dynamic>.from(u['tx'] as Map)));
      case 'goalEdit':
        final goal = GoalsService.all().where((g) => g.id == u['goalId']).firstOrNull;
        if (goal != null) {
          await GoalsService.save(Goal.fromMap({...goal.toMap(), ...Map<String, dynamic>.from(u['vorher'] as Map)}));
        }
      case 'balance':
        final account = MoneyAccounts.byId(u['konto'] as String?);
        if (account != null) await MoneyAccounts.setBalance(account, u['cents'] as int, DB.getTx());
      case 'contractHide':
        await Contracts.hide('${u['name']}', hide: false);
      case 'setting':
        await setSetting('${u['was']}', '${u['wert']}');
    }
  }

  // the settings Ahead may switch, with the values the model may send
  static const settings = {
    'design': ['hell', 'dunkel'],
    'sprache': ['de', 'en'],
    'betraege_verbergen': ['an', 'aus'],
    'benachrichtigungen': ['an', 'aus'],
  };

  static String settingNow(String was) => switch (was) {
        'design' => Settings.darkMode ? 'dunkel' : 'hell',
        'sprache' => L10n.lang.value,
        'betraege_verbergen' => Settings.hideAmounts.value ? 'an' : 'aus',
        _ => NotificationService.enabled.value ? 'an' : 'aus',
      };

  // the same switches the profile page flips
  static Future<void> setSetting(String was, String wert) async {
    switch (was) {
      case 'design':
        ThemeController.isDark.value = wert == 'dunkel';
        await Settings.setDarkMode(wert == 'dunkel');
      case 'sprache':
        await L10n.set(wert);
      case 'betraege_verbergen':
        await Settings.setHideAmounts(wert == 'an');
      case 'benachrichtigungen':
        if (wert != 'an') return NotificationService.disable();
        if (!await NotificationService.enable()) throw NotificationService.problem;
    }
  }

  // --- built by the agent's tools -----------------------------------------

  static int _cents(dynamic eur) {
    final c = (((eur as num?) ?? 0) * 100).round();
    if (c <= 0) throw const FormatException('betrag fehlt');
    return c;
  }

  // the last day of a month given as JJJJ-MM
  static DateTime? _monthEnd(dynamic raw) {
    final m = RegExp(r'^(\d{4})-(\d{2})$').firstMatch('${raw ?? ''}');
    return m == null ? null : DateTime(int.parse(m.group(1)!), int.parse(m.group(2)!) + 1, 0);
  }

  static BuddyProposal budget(Map<String, dynamic> input) {
    final category = '${input['kategorie'] ?? ''}'.trim();
    if (category.isEmpty) throw const FormatException('kategorie fehlt');
    final cents = _cents(input['betrag']);
    return BuddyProposal(ProposalKind.budget, tr('Budget {category}', {'category': category}),
        tr('{x} im Monat, ab diesem Monat', {'x': Money.format(cents)}), {'kategorie': category, 'cents': cents});
  }

  static BuddyProposal goal(Map<String, dynamic> input, {required DateTime today}) {
    final name = '${input['name'] ?? ''}'.trim();
    if (name.isEmpty) throw const FormatException('name fehlt');
    final cents = _cents(input['betrag']);
    final until = _monthEnd(input['bis']);
    final monthly = input['monatlich'] == null ? null : _cents(input['monatlich']);
    final parts = [
      Money.format(cents),
      if (until != null) tr('bis {x}/{y}', {'x': until.month.toString().padLeft(2, '0'), 'y': until.year}),
      if (monthly != null) tr('{x} im Monat', {'x': Money.format(monthly)}),
    ];
    return BuddyProposal(ProposalKind.goal, tr('Sparziel {x}', {'x': name}), parts.join(' · '),
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
    return BuddyProposal(ProposalKind.cancel, tr('Kündigung {provider}', {'provider': provider}), tr('Fertiger Text, fristgerecht zum nächstmöglichen Termin'),
        {'anbieter': provider, 'letter': letter});
  }

  static BuddyProposal category(Map<String, dynamic> input) {
    final merchant = '${input['haendler'] ?? ''}'.trim();
    final category = '${input['kategorie'] ?? ''}'.trim();
    if (merchant.isEmpty || category.isEmpty) throw const FormatException('haendler und kategorie nötig');
    return BuddyProposal(ProposalKind.category, '$merchant → $category', tr('Alle Buchungen und neue in Zukunft'),
        {'haendler': merchant, 'kategorie': category});
  }

  // put an amount aside for a savings goal now, e.g. right after payday
  static BuddyProposal save(Map<String, dynamic> input) {
    final name = '${input['ziel'] ?? ''}'.trim().toLowerCase();
    final cents = _cents(input['betrag']);
    final goals = GoalsService.all().where((g) => !g.reached).toList();
    if (goals.isEmpty) throw const FormatException('es gibt kein offenes Sparziel; schlag zuerst eins vor');
    final goal = goals.where((g) => g.name.toLowerCase().contains(name) || name.contains(g.name.toLowerCase())).firstOrNull ??
        (goals.length == 1 ? goals.first : null);
    if (goal == null) {
      throw FormatException('ziel nicht gefunden, offen sind: ${goals.map((g) => g.name).join(', ')}');
    }
    final left = goal.remainingCents;
    return BuddyProposal(ProposalKind.save, tr('{x} zurücklegen', {'x': goal.name}),
        tr('{x} jetzt, danach fehlen noch {y}', {'x': Money.format(cents), 'y': Money.format((left - cents).clamp(0, left))}),
        {'goalId': goal.id, 'cents': cents});
  }

  static String _name(Transaction t) => (t.note?.trim().isNotEmpty ?? false) ? t.note!.trim() : t.category;

  // the newest booking whose title contains the text, on that day when one is given
  static Transaction _booking(Map<String, dynamic> input, List<Transaction> tx) {
    final text = '${input['suchtext'] ?? ''}'.trim().toLowerCase();
    if (text.isEmpty) throw const FormatException('suchtext fehlt');
    final day = DateTime.tryParse('${input['datum'] ?? ''}');
    final hits = tx
        .where((t) =>
            _name(t).toLowerCase().contains(text) &&
            (day == null || (t.date.year == day.year && t.date.month == day.month && t.date.day == day.day)))
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    if (hits.isEmpty) throw const FormatException('keine Buchung gefunden; such sie erst mit buchungen_suchen');
    return hits.first;
  }

  // one booking gets another category, amount, title or day
  static BuddyProposal txEdit(Map<String, dynamic> input, List<Transaction> tx) {
    final t = _booking(input, tx);
    final neu = <String, dynamic>{};
    final changes = <String>[];
    final category = '${input['kategorie'] ?? ''}'.trim();
    if (category.isNotEmpty && category != t.category) {
      final known = {for (final c in [...Categories.expense, ...Categories.income]) c['name']};
      if (!known.contains(category)) throw FormatException('kategorie gibt es nicht, möglich: ${known.join(', ')}');
      neu['category'] = category;
      changes.add('${tr(t.category)} → ${tr(category)}');
    }
    if (input['betrag'] != null && _cents(input['betrag']) != t.amountCents) {
      neu['amountCents'] = _cents(input['betrag']);
      changes.add('${Money.format(t.amountCents)} → ${Money.format(neu['amountCents'] as int)}');
    }
    final title = '${input['titel'] ?? ''}'.trim();
    if (title.isNotEmpty && title != t.note) {
      neu['note'] = title;
      changes.add('„$title“');
    }
    final day = DateTime.tryParse('${input['datum_neu'] ?? ''}');
    if (day != null) {
      neu['date'] = DateTime(day.year, day.month, day.day, 12).millisecondsSinceEpoch;
      changes.add('${day.day}.${day.month}.${day.year}');
    }
    if (neu.isEmpty) throw const FormatException('nichts zu ändern: kategorie, betrag, titel oder datum_neu angeben');
    return BuddyProposal(ProposalKind.txEdit, tr('{x} ändern', {'x': _name(t)}),
        '${t.dateText} · ${t.amountText}\n${changes.join(' · ')}', {'id': t.id, 'neu': neu});
  }

  static BuddyProposal txDelete(Map<String, dynamic> input, List<Transaction> tx) {
    final t = _booking(input, tx);
    return BuddyProposal(ProposalKind.txDelete, tr('{x} löschen', {'x': _name(t)}),
        '${t.dateText} · ${t.amountText} · ${tr(t.category)}', {'id': t.id});
  }

  // an existing goal gets another target, monthly rate or month
  static BuddyProposal goalEdit(Map<String, dynamic> input) {
    final name = '${input['ziel'] ?? ''}'.trim().toLowerCase();
    final goals = GoalsService.all();
    final goal = goals.where((g) => g.name.toLowerCase().contains(name) || name.contains(g.name.toLowerCase())).firstOrNull ??
        (goals.length == 1 ? goals.first : null);
    if (goal == null) throw FormatException('ziel nicht gefunden, es gibt: ${goals.map((g) => g.name).join(', ')}');
    final neu = <String, dynamic>{};
    final changes = <String>[];
    if (input['betrag'] != null) {
      neu['targetCents'] = _cents(input['betrag']);
      changes.add('${Money.format(goal.targetCents)} → ${Money.format(neu['targetCents'] as int)}');
    }
    final monthly = input['monatlich'] as num?;
    if (monthly != null && monthly >= 0) {
      neu['monthlyCents'] = (monthly * 100).round();
      changes.add(tr('{x} im Monat', {'x': Money.format(neu['monthlyCents'] as int)}));
    }
    final until = _monthEnd(input['bis']);
    if (until != null) {
      neu['deadline'] = until.millisecondsSinceEpoch;
      changes.add(tr('bis {x}/{y}', {'x': until.month.toString().padLeft(2, '0'), 'y': until.year}));
    }
    if (neu.isEmpty) throw const FormatException('nichts zu ändern: betrag, monatlich oder bis angeben');
    return BuddyProposal(ProposalKind.goalEdit, tr('Sparziel {x} ändern', {'x': goal.name}), changes.join(' · '),
        {'goalId': goal.id, 'neu': neu});
  }

  // what an account kept by hand really holds today
  static BuddyProposal balance(Map<String, dynamic> input) {
    final eur = input['betrag'] as num?;
    if (eur == null) throw const FormatException('betrag fehlt');
    final name = '${input['konto'] ?? ''}'.trim().toLowerCase();
    final account = name.isEmpty
        ? MoneyAccounts.main
        : MoneyAccounts.all.where((a) => a.name.toLowerCase().contains(name)).firstOrNull;
    if (account == null) {
      throw FormatException('konto nicht gefunden, es gibt: ${MoneyAccounts.all.map((a) => a.name).join(', ')}');
    }
    // a linked account takes its balance from the bank; a hand-set one would be wrong after the next sync
    if (account.link != null) throw const FormatException('das Konto kommt von der Bank, sein Stand lässt sich nicht von Hand setzen');
    final cents = (eur * 100).round();
    return BuddyProposal(ProposalKind.balance, tr('Kontostand {x}', {'x': account.name}),
        '${Money.format(MoneyAccounts.balanceOf(account, DB.getTx()))} → ${Money.format(cents)}',
        {'konto': account.id, 'cents': cents});
  }

  // a regular payment that is no contract; [name] as the app detected it
  static BuddyProposal contractHide(String name) => BuddyProposal(ProposalKind.contractHide,
      tr('{x} ausblenden', {'x': name}), tr('Zählt nicht mehr als Vertrag. Die Buchungen bleiben.'), {'name': name});

  // "Stell die App auf Englisch", "Dunkelmodus an": a setting asked for by name works on the device,
  // without the model. Null when the sentence is no such order (it needs a verb and a known setting).
  static BuddyProposal? settingFrom(String question) {
    final q = question.toLowerCase();
    bool has(String re) => RegExp(re).hasMatch(q);
    if (!has(r'\b(stell|schalt|mach|wechs|änder|aender|setz|aktivier|switch|set|turn|change|use|make)')) return null;
    final off = has(r'\b(aus|off|weg|deaktivier\w*|nicht mehr)\b');
    final (String, String)? order;
    if (has(r'englisch|english')) {
      order = ('sprache', 'en');
    } else if (has(r'deutsch|german')) {
      order = ('sprache', 'de');
    } else if (has(r'dunkel|dark|nachtmodus')) {
      order = ('design', off ? 'hell' : 'dunkel');
    } else if (has(r'\bhell|light')) {
      order = ('design', off ? 'dunkel' : 'hell');
    } else if (has(r'betr(ä|ae)ge|amounts')) {
      order = has(r'zeig|show|einblend|sichtbar')
          ? ('betraege_verbergen', 'aus')
          : has(r'verberg|versteck|hide|ausblend')
              ? ('betraege_verbergen', off ? 'aus' : 'an')
              : null;
    } else {
      order = null;
    }
    return order == null ? null : setting({'was': order.$1, 'wert': order.$2});
  }

  static BuddyProposal setting(Map<String, dynamic> input) {
    final was = '${input['was'] ?? ''}', wert = '${input['wert'] ?? ''}';
    if (settings[was]?.contains(wert) != true) {
      throw FormatException(
          'was und wert passen nicht, möglich: ${settings.entries.map((e) => '${e.key} = ${e.value.join(' oder ')}').join(', ')}');
    }
    final label = switch (was) {
      'design' => tr('Design'),
      'sprache' => tr('Sprache'),
      'betraege_verbergen' => tr('Beträge verbergen'),
      _ => tr('Mitteilungen'),
    };
    final value = switch (wert) {
      'hell' => tr('hell'),
      'dunkel' => tr('dunkel'),
      'an' => tr('an'),
      'aus' => tr('aus'),
      _ => L10n.names[wert]!,
    };
    return BuddyProposal(ProposalKind.setting, tr('Einstellung: {x}', {'x': label}), value,
        {'was': was, 'wert': wert, 'label': label});
  }

  static BuddyProposal reminder(Map<String, dynamic> input) {
    final text = '${input['text'] ?? ''}'.trim();
    if (text.isEmpty) throw const FormatException('text fehlt');
    final date = DateTime.tryParse('${input['datum'] ?? ''}');
    final when = date == null ? tr('ohne Datum') : '${date.day}.${date.month}.${date.year}';
    return BuddyProposal(ProposalKind.reminder, tr('Erinnerung'), '$text · $when', {'text': text, 'datum': date});
  }
}

// a small chart under an answer; values in cents
enum ChartKind { months, categories, plan, payslip }

class BuddyChart {
  final ChartKind kind;
  final String title;
  // months: label, income, spent · categories: label, value · plan: label, saved, target
  // payslip: label, brutto, netto (deductions = brutto − netto)
  final List<({String label, int a, int b})> rows;
  const BuddyChart(this.kind, this.title, this.rows);
}
