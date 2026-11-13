import 'dart:io';

import 'package:budget_buddy/services/buddy_history.dart';
import 'package:budget_buddy/services/buddy_markers.dart';
import 'package:budget_buddy/services/buddy_memory.dart';
import 'package:budget_buddy/services/glossary.dart';
import 'package:budget_buddy/services/guest_buddy.dart';
import 'package:budget_buddy/services/life_stages.dart';
import 'package:budget_buddy/widgets/share_card.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  setUpAll(() async {
    Hive.init(Directory.systemTemp.createTempSync('buddybrain').path);
    await Hive.openBox('settings');
  });

  setUp(() async => Hive.box('settings').clear());

  group('markers', () {
    test('follow-ups and a fact to remember are taken out of the text', () {
      final m = BuddyMarkers.parse('**450 €** bleiben.\n\nNächster Schritt: Budget setzen.\n'
          '[merken: Spart auf eine Wohnung]\n[weiter: Wo kann ich sparen? | Reicht das bis Monatsende?]');
      expect(m.text, '**450 €** bleiben.\n\nNächster Schritt: Budget setzen.');
      expect(m.remember, 'Spart auf eine Wohnung');
      expect(m.followUps, ['Wo kann ich sparen?', 'Reicht das bis Monatsende?']);
    });

    test('a marker that is still streaming in never shows', () {
      expect(BuddyMarkers.parse('Antwort.\n[wei').text, 'Antwort.');
      expect(BuddyMarkers.parse('Antwort.\n[weiter: Wo kann').text, 'Antwort.');
      expect(BuddyMarkers.parse('Antwort.\n[weiter: Wo kann').followUps, isEmpty);
    });

    test('ordinary brackets in the text stay', () {
      expect(BuddyMarkers.parse('Netflix [Abo] kostet 13 €').text, 'Netflix [Abo] kostet 13 €');
    });
  });

  group('memory', () {
    test('adds, refuses duplicates and sensitive things, deletes', () async {
      expect(await BuddyMemory.add('Hat im Oktober den ersten Job angefangen.'), true);
      expect(await BuddyMemory.add('hat im oktober den ersten job angefangen'), false);
      expect(await BuddyMemory.add('Ist gerade krank geschrieben'), false);
      expect(await BuddyMemory.add('Meine IBAN ist DE12 3456'), false);
      expect(BuddyMemory.texts(), ['Hat im Oktober den ersten Job angefangen']);
      await BuddyMemory.remove(BuddyMemory.all().single.id);
      expect(BuddyMemory.all(), isEmpty);
    });

    test('"Merk dir, dass …" becomes a fact to confirm', () {
      expect(BuddyMemory.fromCommand('Merk dir, dass ich im März umziehe'), 'Dass ich im März umziehe');
      expect(BuddyMemory.fromCommand('bitte merk dir: Gehalt kommt am 28.'), 'Gehalt kommt am 28');
      expect(BuddyMemory.fromCommand('Was kann ich mir merken?'), isNull);
    });

    test('keeps at most the newest facts', () async {
      for (var i = 0; i < BuddyMemory.max + 5; i++) {
        await BuddyMemory.add('Fakt Nummer $i');
      }
      expect(BuddyMemory.all().length, BuddyMemory.max);
      expect(BuddyMemory.texts().last, 'Fakt Nummer ${BuddyMemory.max + 4}');
    });
  });

  group('glossary', () {
    test('finds each money word once, longest spelling first', () {
      final hits = Glossary.find('Ein ETF-Sparplan ist ein Sparplan auf einen ETF. Dein Notgroschen zuerst.');
      expect(hits.map((h) => h.term.term), ['Sparplan', 'ETF', 'Notgroschen']);
    });

    test('does not mark parts of other words', () {
      expect(Glossary.find('Die Tetfabrik'), isEmpty);
      expect(Glossary.find('Bruttoinlandsprodukt'), isEmpty);
    });

    test('at most three per answer', () {
      expect(Glossary.find('ETF, TER, Dispo, Schufa, Inflation').length, 3);
    });
  });

  group('life stages', () {
    test('progress is kept per step and goes into the AI summary', () async {
      final s = LifeStages.firstJob;
      await LifeStages.choose(s);
      await LifeStages.setDone(s, s.steps[0], true);
      expect(LifeStages.progress(s), 1);
      final snap = LifeStages.snapshot()!;
      expect(snap['name'], 'Erster Job');
      expect(snap['erledigt'], ['Gehaltsabrechnung prüfen']);
      expect((snap['offen'] as List).length, s.steps.length - 1);
    });

    test('questions find their step', () {
      expect(LifeStages.stepFor('Lohnt sich die bAV?')?.id, 'betriebsrente');
      expect(LifeStages.stepFor('Wie viel Notgroschen brauche ich?')?.id, 'notgroschen');
      expect(LifeStages.stepFor('Wie wird das Wetter?'), isNull);
    });
  });

  group('guest', () {
    test('three answers a day, counted per day', () {
      expect(GuestBuddy.left(), GuestBuddy.perDay);
      Hive.box('settings').put(GuestBuddy.usedKey, {'day': DateTime.now().toIso8601String().substring(0, 10), 'n': 3});
      expect(GuestBuddy.left(), 0);
      expect(GuestBuddy.left(now: DateTime.now().add(const Duration(days: 1))), GuestBuddy.perDay);
    });

    test('offline: life stage steps and words, otherwise an honest note', () {
      expect(GuestBuddy.offline('Wie viel Notgroschen brauche ich?'), contains('drei Monatsausgaben'));
      expect(GuestBuddy.offline('Was ist die TER?'), startsWith('**TER**'));
      expect(GuestBuddy.offline('Wer gewinnt die Bundesliga?'), contains('Erster Job'));
    });

    test('a device id is made once and kept', () {
      final id = GuestBuddy.deviceId;
      expect(id.length, 24);
      expect(GuestBuddy.deviceId, id);
    });
  });

  group('history', () {
    test('the guest chat moves into the account once', () async {
      await BuddyHistory.save([SavedMessage(true, 'Hallo', DateTime(2026, 11, 13))], guest: true);
      expect(await BuddyHistory.adoptGuest(), true);
      expect(BuddyHistory.load().single.text, 'Hallo');
      expect(BuddyHistory.load(guest: true), isEmpty);
      expect(await BuddyHistory.adoptGuest(), false);
    });

    test('keeps the newest messages', () async {
      await BuddyHistory.save([
        for (var i = 0; i < BuddyHistory.max + 10; i++) SavedMessage(i.isEven, 'm$i', DateTime(2026))
      ]);
      expect(BuddyHistory.load().length, BuddyHistory.max);
      expect(BuddyHistory.load().last.text, 'm${BuddyHistory.max + 9}');
    });
  });

  test('share card hides amounts but keeps the sentence', () {
    expect(hideAmounts('Du sparst 128,40 € im Monat und 1.540 Euro im Jahr.'),
        'Du sparst ••• € im Monat und ••• Euro im Jahr.');
    expect(hideAmounts('3 Abos gefunden'), '3 Abos gefunden');
  });
}
