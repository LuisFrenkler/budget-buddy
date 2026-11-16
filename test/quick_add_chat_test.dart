// Adding a booking is Buddy's job now: the short quick-add form counts as
// something that happened, questions do not.
import 'package:budget_buddy/services/buddy_entries.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('short entries without a verb', () {
    for (final t in ['Kaffee 3,50', '12 € Döner gestern', 'Rewe 23,40', '+2400 Gehalt', 'Kaffee 3,50 bezahlt']) {
      expect(BuddyEntries.looksLikeEvent(t), isTrue, reason: t);
    }
  });

  test('questions and long sentences stay questions', () {
    for (final t in [
      'Wie viel habe ich für Kaffee ausgegeben?',
      'Kann ich 500 sparen',
      'Was mache ich mit 2000 Euro Bonus',
      '500',
      'Ich überlege, ob ich mir für 800 Euro ein neues Fahrrad hole',
    ]) {
      expect(BuddyEntries.looksLikeEvent(t), isFalse, reason: t);
    }
  });
}
