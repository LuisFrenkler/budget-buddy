import 'dart:io';

import 'package:budget_buddy/services/buddy_journal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  setUpAll(() async {
    Hive.init(Directory.systemTemp.createTempSync('journal').path);
    await Hive.openBox('settings');
  });
  setUp(() => BuddyJournal.clear());

  test('keeps the question and the next step, newest first', () async {
    await BuddyJournal.add('Soll ich mein Gym kündigen?',
        'Du warst seit März nicht da.\n\n**Nächster Schritt:** Kündige **FitX** bis 1. Mai.', now: DateTime(2026, 11, 2));
    await BuddyJournal.add('Wie viel ist noch frei?', '340 € sind frei.', now: DateTime(2026, 11, 10));
    final list = BuddyJournal.forAgent(now: DateTime(2026, 11, 14));
    expect(list.first['frage'], 'Wie viel ist noch frei?');
    expect(list.last['schritt'], 'Kündige FitX bis 1. Mai.');
    expect(list.first.containsKey('schritt'), isFalse);
  });

  test('what is on screen right now and old talks are left out', () async {
    await BuddyJournal.add('Alt', 'x', now: DateTime(2026, 8, 1));
    await BuddyJournal.add('Jetzt', 'Next step: do it', now: DateTime(2026, 11, 14));
    expect(BuddyJournal.forAgent(now: DateTime(2026, 11, 14)).map((e) => e['frage']), ['Jetzt']);
    expect(BuddyJournal.forAgent(current: ['Jetzt'], now: DateTime(2026, 11, 14)), isEmpty);
    expect(BuddyJournal.stepOf('Next step: Ask HR'), 'Ask HR');
  });
}
