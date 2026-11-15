// Every offline answer in English: with the app set to English, LocalBuddy
// must not slip into German anywhere (labels, list lines, categories).
import 'package:budget_buddy/l10n/l10n.dart';
import 'package:budget_buddy/models/goal.dart';
import 'package:budget_buddy/models/transaction.dart';
import 'package:budget_buddy/services/finance_snapshot.dart';
import 'package:budget_buddy/services/guest_buddy.dart';
import 'package:budget_buddy/services/local_buddy.dart';
import 'package:flutter_test/flutter_test.dart';

Transaction _t(String note, String cat, int cents, DateTime d, {bool income = false}) =>
    Transaction(id: '$note$d$cents', amountCents: cents, category: cat, date: d, isIncome: income, note: note);

// words that only show up in a German sentence
final _german = RegExp(
    r'\b(und|oder|der|die|das|du|dein|deine|dir|dich|ist|sind|noch|nicht|mit|für|bei|im|vom|zum|bis|ein|eine|'
    r'Monat|Monate|Ausgaben|Einnahmen|Konten|Kontostand|Sparziele|Schulden|Sparquote|Vermögen|Nettovermögen|'
    r'Wiederkehrend|Buchungen|Szenario|bleiben|ausgeglichen|entspannt|knapp|Lebensmittel|Wohnen|Unterhaltung|'
    r'Girokonto|Grün|Gelb|Rot)\b');

void main() {
  final now = DateTime(2026, 10, 20);
  final tx = [
    for (int m = 7; m <= 10; m++) ...[
      _t('Salary', 'Gehalt', 300000, DateTime(2026, m, 1), income: true),
      _t('Rent', 'Wohnen', 90000, DateTime(2026, m, 3)),
      _t('Netflix', 'Unterhaltung', 1399, DateTime(2026, m, 12)),
      _t('REWE', 'Lebensmittel', m == 10 ? 60000 : 30000, DateTime(2026, m, 15)),
    ],
  ];
  final goal = Goal(
      id: 'g1', name: 'Holiday', emoji: '🏖️', targetCents: 80000, savedCents: 20000, createdAt: DateTime(2026, 1, 1));
  final s = FinanceSnapshot.build(
    tx: tx,
    openingCents: 100000,
    budgets: const [],
    holdings: const [],
    now: now,
    goals: [goal],
    accounts: [(name: 'Giro', art: 'Girokonto', cents: 120000)],
    splits: [
      (
        name: 'Flat',
        myCents: 2500,
        salden: [(name: 'Me', cents: 2500), (name: 'Anna', cents: -2500)],
        ausgleich: [(von: 'Anna', an: 'Me', cents: 2500)],
      ),
    ],
    debts: [(name: 'Student loan', cents: 50000)],
    emergencyTargetCents: 300000,
    emergencyHaveCents: 50000,
  );

  setUp(() => L10n.lang.value = 'en');
  tearDown(() => L10n.lang.value = 'de');

  const questions = [
    'Where can I save money?',
    'Can I afford a 800 € holiday?',
    'Which subscriptions do I have?',
    'How are my savings goals?',
    'Who owes me money?',
    'What is my net worth?',
    'How is my emergency fund?',
    'Show my accounts',
    'What did I spend this month?',
    'How much is left until the end of the month?',
    'What if I cancel Netflix?',
    'What if I spend 200?',
    'How is my budget?',
    'How is my retirement?',
    'What are my recurring payments?',
    'Do I have Plus?',
    'Hello',
  ];

  for (final q in questions) {
    test('offline in English: $q', () {
      final a = LocalBuddy.answer(q, s);
      expect(a.trim(), isNotEmpty);
      final hit = _german.firstMatch(a);
      expect(hit, isNull, reason: 'German "${hit?.group(0)}" in: $a');
    });
  }

  test('the affordability answer starts with a traffic light', () {
    final a = LocalBuddy.answer('Can I afford a 800 € holiday?', s);
    expect(a, matches(RegExp(r'^(🟢|🟡|🔴) \*\*(Green|Yellow|Red):')));
  });

  test('a short English follow-up goes back to the last topic', () {
    final a = LocalBuddy.answer('why?', s, history: [
      (fromUser: true, text: 'Which subscriptions do I have?'),
      (fromUser: false, text: '…'),
      (fromUser: true, text: 'why?'),
    ]);
    expect(a, contains('Netflix'));
  });

  // without an account: life stage steps, money words and gross to net
  for (final q in [
    'What is an ETF?',
    'How much emergency fund do I need?',
    'What is a tax class?',
    'What is left of 3000 gross?',
    'How do I read my first payslip?',
    'Tell me a joke',
  ]) {
    test('guest offline in English: $q', () {
      final a = GuestBuddy.offline(q);
      final hit = _german.firstMatch(a);
      expect(hit, isNull, reason: 'German "${hit?.group(0)}" in: $a');
    });
  }
}
