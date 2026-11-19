import 'dart:io';

import 'package:budget_buddy/models/transaction.dart';
import 'package:budget_buddy/services/buddy_log.dart';
import 'package:budget_buddy/services/buddy_memory.dart';
import 'package:budget_buddy/services/buddy_proposals.dart';
import 'package:budget_buddy/services/buddy_tasks.dart';
import 'package:budget_buddy/services/buddy_tools.dart';
import 'package:budget_buddy/services/db.dart';
import 'package:budget_buddy/services/goals_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  String? clipboard;

  setUpAll(() async {
    Hive.init(Directory.systemTemp.createTempSync('buddyactions').path);
    for (final b in ['settings', 'transactions', 'budgets', 'goals']) {
      await Hive.openBox(b);
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform,
        (call) async {
      if (call.method == 'Clipboard.setData') clipboard = (call.arguments as Map)['text'] as String?;
      return null;
    });
  });

  setUp(() async {
    for (final b in ['settings', 'transactions', 'budgets', 'goals']) {
      await Hive.box(b).clear();
    }
  });

  final now = DateTime(2026, 11, 14);
  BuddyTools tools() => BuddyTools(
        tx: [
          for (final m in [9, 10])
            Transaction(
                id: 'g$m', amountCents: 240000, category: 'Gehalt', date: DateTime(2026, m, 28), isIncome: true, note: 'Gehalt'),
          Transaction(
              id: 'r', amountCents: 6230, category: 'Lebensmittel', date: DateTime(2026, 11, 3), isIncome: false, note: 'Rewe'),
        ],
        snapshot: const {},
        now: now,
      );

  group('the agent proposes, the person decides', () {
    test('a budget card does nothing until it is applied', () async {
      final t = tools();
      final r = t.run('budget_vorschlagen', {'kategorie': 'Lebensmittel', 'betrag': 250});
      expect(r['karte'], 'gezeigt');
      expect(r['hinweis'], contains('Gespeichert ist noch nichts'));
      expect(DB.getBudgets(), isEmpty);
      final said = await t.proposals.single.apply(now: now);
      expect(said, contains('Lebensmittel'));
      expect(DB.getBudgets().single.limitCents, 25000);
    });

    test('a savings goal with month and rate', () async {
      final t = tools();
      t.run('sparziel_vorschlagen', {'name': 'Urlaub', 'betrag': 800, 'bis': '2027-07', 'monatlich': 90});
      final p = t.proposals.single;
      expect(p.detail, contains('07/2027'));
      await p.apply(now: now);
      final g = GoalsService.all().single;
      expect(g.name, 'Urlaub');
      expect(g.targetCents, 80000);
      expect(g.deadline, DateTime(2027, 7, 31));
      expect(g.monthlyCents, 9000);
    });

    test('a cancellation letter is copied, never sent', () async {
      final t = tools();
      t.run('kuendigung_vorbereiten', {'anbieter': 'FitX'});
      expect(t.proposals.single.confirm, 'Text kopieren');
      await t.proposals.single.apply(now: now);
      expect(clipboard, contains('hiermit kündige ich meinen Vertrag bei FitX'));
    });

    test('moving a merchant to another category moves every booking', () async {
      await DB.addTx(Transaction(
          id: 'b1', amountCents: 1860, category: 'Sonstiges', date: DateTime(2026, 10, 3), isIncome: false, note: 'Burger Bar'));
      await DB.addTx(Transaction(
          id: 'b2', amountCents: 2140, category: 'Sonstiges', date: DateTime(2026, 11, 2), isIncome: false, note: 'Burger Bar'));
      final t = tools();
      t.run('kategorie_vorschlagen', {'haendler': 'Burger Bar', 'kategorie': 'Essen gehen'});
      final said = await t.proposals.single.apply(now: now);
      expect(said, contains('2 Buchungen'));
      expect(DB.getTx().every((x) => x.category == 'Essen gehen'), isTrue);
    });

    test('a reminder becomes an open task with its date', () async {
      final t = tools();
      t.run('erinnerung_vorschlagen', {'text': 'Personalabteilung fragen', 'datum': '2026-11-20'});
      await t.proposals.single.apply(now: now);
      final task = BuddyTasks.open().single;
      expect(task.text, 'Personalabteilung fragen');
      expect(task.due, DateTime(2026, 11, 20));
    });

    test('at most three cards per answer, the same one only once', () {
      final t = tools();
      for (var i = 0; i < 2; i++) {
        t.run('budget_vorschlagen', {'kategorie': 'Lebensmittel', 'betrag': 250});
      }
      t.run('budget_vorschlagen', {'kategorie': 'Shopping', 'betrag': 80});
      t.run('budget_vorschlagen', {'kategorie': 'Freizeit', 'betrag': 60});
      expect(t.proposals.length, 3);
      expect(t.run('budget_vorschlagen', {'kategorie': 'Abos', 'betrag': 30})['fehler'], contains('drei'));
    });

    test('missing fields come back as an error for the model', () {
      expect(tools().run('sparziel_vorschlagen', {'betrag': 800})['fehler'], contains('name'));
      expect(tools().run('budget_vorschlagen', {'kategorie': 'X', 'betrag': 0})['fehler'], contains('betrag'));
    });
  });

  group('putting money aside', () {
    test('after payday: an amount for the goal, counted and undone again', () async {
      final t = tools();
      t.run('sparziel_vorschlagen', {'name': 'Notgroschen', 'betrag': 3000});
      await t.proposals.single.apply(now: now);
      final t2 = tools();
      final r = t2.run('zuruecklegen_vorschlagen', {'ziel': 'notgroschen', 'betrag': 250});
      expect(r['karte'], 'gezeigt');
      expect(t2.proposals.single.detail, contains('2.750'));
      await t2.proposals.single.apply(now: now);
      expect(GoalsService.all().single.savedCents, 25000);
      await BuddyLog.undo(BuddyLog.all().first.id);
      expect(GoalsService.all().single.savedCents, 0);
    });

    test('without a goal Buddy is told to propose one first', () {
      expect(tools().run('zuruecklegen_vorschlagen', {'ziel': 'Urlaub', 'betrag': 100})['fehler'],
          contains('kein offenes Sparziel'));
    });
  });

  group('notice periods', () {
    BuddyTools withContract(String name, String category, String since, String next) => BuddyTools(
          tx: const [],
          snapshot: {
            'vertraegeUndAbos': [
              {'name': name, 'proMonat': 29.9, 'kategorie': category, 'naechste': next, 'seit': since}
            ]
          },
          now: now,
        );

    test('a gym still in its minimum term: earliest end and the last day to cancel', () {
      final r = withContract('FitX', 'Sport', '2025-06-01', '2026-12-01').run('kuendigungsfrist', {'anbieter': 'fitx'});
      expect(r['erkannt'], isTrue);
      expect(r['art'], 'fitness');
      expect(r['endetFruehestens'], '2027-06-01');
      expect(r['kuendigenBis'], '2027-05-01');
      expect(r['mindestlaufzeitGeschaetzt'], isTrue);
    });

    test('after the minimum term: any time with one month', () {
      final r = withContract('FitX', 'Sport', '2023-01-01', '2026-12-01')
          .run('kuendigungsfrist', {'anbieter': 'FitX', 'mindestlaufzeit_monate': 12});
      expect(r['endetFruehestens'], '2026-12-14');
      expect(r['kuendigenBis'], 'jederzeit');
    });

    test('a streaming subscription ends with the paid month', () {
      final r = withContract('Netflix', 'Abos', '2024-02-10', '2026-12-10').run('kuendigungsfrist', {'anbieter': 'Netflix'});
      expect(r['art'], 'abo');
      expect(r['endetFruehestens'], '2026-12-09');
    });

    test('old contracts and insurance only get the rule', () {
      expect(withContract('Stadtwerke', 'Wohnen', '2021-05-01', '2026-12-01')
          .run('kuendigungsfrist', {'anbieter': 'Stadtwerke'})['altvertrag'], isTrue);
      final ins = withContract('HUK Haftpflicht', 'Versicherung', '2024-01-01', '2027-01-01')
          .run('kuendigungsfrist', {'anbieter': 'HUK'});
      expect(ins['regel'], contains('Versicherungsjahres'));
      expect(ins.containsKey('endetFruehestens'), isFalse);
    });

    test('an unknown provider still gets the general rule', () {
      final r = tools().run('kuendigungsfrist', {'anbieter': 'Unbekannt GmbH'});
      expect(r['erkannt'], isFalse);
      expect(r['hinweis'], contains('Schätzung'));
    });
  });

  group('charts', () {
    test('months, categories and a savings plan', () {
      final t = tools();
      expect(t.run('diagramm', {'art': 'monate', 'monate': 3})['diagramm'], 'gezeigt');
      expect(t.charts.single.rows.length, 3);
      expect(t.charts.single.rows.last.label, 'Nov');
      t.run('diagramm', {'art': 'sparplan', 'betrag': 600, 'bis_monat': '2027-01', 'schon_gespart': 0});
      final plan = t.charts.last;
      expect(plan.rows.length, 3);
      expect(plan.rows.last.a, 60000);
      expect(t.run('diagramm', {'art': 'kategorien', 'von': '2026-11-01', 'bis': '2026-11-14'})['fehler'],
          contains('zwei'));
    });
    test('an unknown kind explains itself', () {
      expect(tools().run('diagramm', {'art': 'torte'})['fehler'], contains('monate'));
    });
  });

  group('open tasks', () {
    test('the same step is kept once, done ones leave the open list', () async {
      await BuddyTasks.add('Frag nach dem Zuschuss', now: now);
      await BuddyTasks.add('**Frag nach dem Zuschuss**', now: now);
      expect(BuddyTasks.open(now: now).length, 1);
      await BuddyTasks.doneByText('Frag nach dem Zuschuss');
      expect(BuddyTasks.open(now: now), isEmpty);
    });

    test('Buddy sees what is open and for how long', () async {
      await BuddyTasks.add('Notgroschen-Dauerauftrag einrichten', now: DateTime(2026, 11, 2));
      final open = BuddyTasks.forAgent(now: now);
      expect(open.single['aufgabe'], 'Notgroschen-Dauerauftrag einrichten');
      expect(open.single['vorTagen'], 12);
    });

    test('undated steps fade after 30 days, at most eight stay open', () async {
      await BuddyTasks.add('Alt', now: DateTime(2026, 9, 1));
      expect(BuddyTasks.open(now: now), isEmpty);
      for (var i = 0; i < 10; i++) {
        await BuddyTasks.add('Schritt $i', now: now.add(Duration(minutes: i)));
      }
      expect(BuddyTasks.open(now: now).length, BuddyTasks.maxOpen);
    });
  });

  group('everything Buddy did can be taken back', () {
    test('a budget, a goal and a reminder disappear again', () async {
      final t = tools();
      t.run('budget_vorschlagen', {'kategorie': 'Lebensmittel', 'betrag': 250});
      t.run('sparziel_vorschlagen', {'name': 'Urlaub', 'betrag': 800});
      t.run('erinnerung_vorschlagen', {'text': 'Personalabteilung fragen', 'datum': '2026-11-20'});
      for (final p in t.proposals) {
        await p.apply(now: now);
      }
      expect(BuddyLog.all().length, 3);
      for (final e in BuddyLog.all()) {
        await BuddyLog.undo(e.id);
      }
      expect(DB.getBudgets(), isEmpty);
      expect(GoalsService.all(), isEmpty);
      expect(BuddyTasks.open(now: now), isEmpty);
      expect(BuddyLog.all().every((e) => e.undone && !e.canUndo), isTrue);
    });

    test('moved bookings go back to their old categories', () async {
      await DB.addTx(Transaction(
          id: 'b1', amountCents: 1860, category: 'Sonstiges', date: DateTime(2026, 10, 3), isIncome: false, note: 'Burger Bar'));
      await DB.addTx(Transaction(
          id: 'b2', amountCents: 2140, category: 'Freizeit', date: DateTime(2026, 11, 2), isIncome: false, note: 'Burger Bar'));
      final t = tools();
      t.run('kategorie_vorschlagen', {'haendler': 'Burger Bar', 'kategorie': 'Essen gehen'});
      await t.proposals.single.apply(now: now);
      expect(DB.getTx().every((x) => x.category == 'Essen gehen'), isTrue);
      await BuddyLog.undo(BuddyLog.all().single.id);
      final back = {for (final x in DB.getTx()) x.id: x.category};
      expect(back, {'b1': 'Sonstiges', 'b2': 'Freizeit'});
    });

    test('a copied letter is logged, but there is nothing to undo', () async {
      final t = tools();
      t.run('kuendigung_vorbereiten', {'anbieter': 'FitX'});
      await t.proposals.single.apply(now: now);
      expect(BuddyLog.all().single.canUndo, isFalse);
    });
  });

  test('memory is sorted by what it is about', () {
    expect(BuddyMemory.kindOf('Gehalt kommt am 28.'), MemoryKind.money);
    expect(BuddyMemory.kindOf('Spart für einen Urlaub in Portugal'), MemoryKind.goal);
    expect(BuddyMemory.kindOf('Hat im Oktober den ersten Job angefangen'), MemoryKind.life);
    expect(BuddyMemory.kindOf('Mag keine Aktien'), MemoryKind.preference);
  });

  test('every proposal kind has an apply path', () {
    // the six new ones are applied and undone in agent_reach_test.dart
    expect(ProposalKind.values.length, 12);
  });
}
