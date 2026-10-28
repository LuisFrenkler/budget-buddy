import 'dart:io';

import 'package:budget_buddy/models/holding.dart';
import 'package:budget_buddy/services/buddy_entries.dart';
import 'package:budget_buddy/services/buddy_wizard.dart';
import 'package:budget_buddy/services/db.dart';
import 'package:budget_buddy/services/goals_service.dart';
import 'package:budget_buddy/services/vorsorge.dart';
import 'package:budget_buddy/utils/instruments.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  setUpAll(() async {
    Hive.init(Directory.systemTemp.createTempSync('bb_wizard').path);
    for (final name in ['settings', 'goals', 'holdings', 'transactions']) {
      await Hive.openBox(name);
    }
  });

  test('questions and purchases are not setup commands', () {
    expect(BuddyWizard.detect('Wie richte ich den Rentenrechner ein?'), isNull);
    expect(BuddyWizard.detect('Wo kann ich sparen'), isNull);
    expect(BuddyWizard.detect('Wie steht meine Vorsorge?'), isNull);
    expect(BuddyWizard.detect('10 Apple zu 180 € gekauft'), isNull);
    expect(BuddyWizard.detect('Füge 12 € für Döner hinzu'), isNull);
    expect(BuddyWizard.detect('Richte den Rentenrechner für mich ein'), 'vorsorge');
    expect(BuddyWizard.detect('Vorsorge einrichten'), 'vorsorge');
    expect(BuddyWizard.detect('Sonstiges aufräumen'), 'categories');
    expect(BuddyWizard.detect('Sparziel Urlaub 800'), 'goal');
    expect(BuddyWizard.detect('Leg ein Sparziel Urlaub 800€ an'), 'goal');
    expect(BuddyWizard.detect('füge Apple hinzu'), 'holding');
    expect(BuddyWizard.detect('Füge Apple Aktien hinzu'), 'holding');
  });

  test('vorsorge parses ages and euro amounts, 0 skips a pillar', () {
    final w = BuddyWizard();
    expect(w.consume('Vorsorge einrichten').text, contains('alt'));
    w.consume('35');
    w.consume('67');
    w.consume('2.000 €');
    w.consume('1.200');
    w.consume('0');
    final e = w.consume('0').proposal!;
    expect(e.age, 35);
    expect(e.retireAge, 67);
    expect(e.cents, 200000);
    expect(e.statutoryCents, 120000);
    expect(e.bavCents, 0);
    expect(e.riesterCents, 0);
    expect(w.isOpen, isFalse);
  });

  test('vorsorge asks what is missing, then proposes a card', () {
    final w = BuddyWizard();
    expect(w.consume('Richte den Rentenrechner für mich ein').text, contains('alt'));
    expect(w.consume('34').text, contains('Rente'));
    expect(w.consume('67').text, contains('Netto'));
    expect(w.consume('2.000 €').text, contains('gesetzlich'));
    expect(w.consume('keine').text, contains('Betriebsrente'));
    expect(w.consume('400').text, contains('Riester'));
    final last = w.consume('weiß nicht');
    final e = last.proposal!;
    expect(e.type, 'vorsorge');
    expect(e.valid, isTrue);
    expect(e.age, 34);
    expect(e.retireAge, 67);
    expect(e.cents, 200000);
    expect(e.statutoryCents, 0);
    expect(e.bavCents, 40000);
    expect(e.riesterCents, 0);
    expect(last.open, isFalse);
    expect(w.isOpen, isFalse);
  });

  test('a goal with name and amount is one card', () {
    final bare = BuddyWizard().consume('Sparziel Urlaub 800');
    expect(bare.proposal!.note, 'Urlaub');
    expect(bare.proposal!.cents, 80000);
    expect(bare.text, contains('Übernehmen'));

    final turn = BuddyWizard().consume('Leg ein Sparziel Urlaub 800€ an');
    final e = turn.proposal!;
    expect(e.type, 'goal');
    expect(e.note, 'Urlaub');
    expect(e.cents, 80000);
    expect(e.emoji, '🏖️');
    expect(turn.text, contains('Übernehmen'));
  });

  test('adding a stock without a count asks, then takes the live quote', () {
    final w = BuddyWizard();
    final ask = w.consume('Füge Apple Aktien hinzu');
    expect(ask.text, contains('Stück'));
    expect(ask.proposal, isNull);
    final quote = w.consume('3');
    expect(quote.quoteFor!.toLowerCase(), 'apple');
    final apple = Instruments.search('apple').single;
    final done = w.quoted(instrument: apple, cents: 19240, live: true);
    final e = done.proposal!;
    expect(e.type, 'holding');
    expect(e.symbol, 'AAPL');
    expect(e.shares, 3);
    expect(e.price, 192.4);
    expect(e.livePrice, isTrue);
    expect(e.note, 'Live-Kurs');
    expect(w.isOpen, isFalse);
  });

  test('abbrechen closes the wizard without a card', () {
    final w = BuddyWizard();
    w.consume('Richte den Rentenrechner ein');
    final stop = w.consume('abbrechen');
    expect(stop.proposal, isNull);
    expect(w.isOpen, isFalse);
    expect(stop.text, contains('nichts'));
  });

  test('confirming stores vorsorge, the goal and the holding', () async {
    final vorsorge = BuddyWizard().consume('Richte den Rentenrechner ein, ich bin 40, Rente mit 65, 2200 netto');
    // pillars were not in the sentence, so it still asks
    expect(vorsorge.proposal, isNull);

    final filled = BuddyEntry(
      type: 'vorsorge', date: DateTime(2026, 1, 1), age: 40, retireAge: 65, cents: 220000,
      statutoryCents: 90000,
    );
    expect(await BuddyEntries.apply(filled), 'Gespeichert');
    expect(Vorsorge.load().age, 40);
    expect(Vorsorge.load().desiredNetCents, 220000);
    expect(Vorsorge.load().statutoryCents, 90000);

    final goal = BuddyWizard().consume('Leg ein Sparziel Urlaub 800€ an').proposal!;
    expect(await BuddyEntries.apply(goal), 'Angelegt');
    expect(GoalsService.all().single.name, 'Urlaub');
    expect(GoalsService.all().single.targetCents, 80000);

    final holding = BuddyEntry(
      type: 'holding', date: DateTime(2026, 1, 1), name: 'Apple', symbol: 'AAPL',
      shares: 2, price: 190, instrumentType: 'Aktie', livePrice: true, note: 'Live-Kurs',
    );
    expect(await BuddyEntries.apply(holding), 'Im Depot');
    final saved = DB.getHoldings().single;
    expect(saved, isA<Holding>());
    expect(saved.shares, 2);
    expect(saved.symbol, 'AAPL');
    expect(saved.currentPriceCents, 19000);
    expect(saved.priceAt, isNotNull);
  });
}
