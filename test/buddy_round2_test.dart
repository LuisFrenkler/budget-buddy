// Notgroschen from real costs, „Kann ich mir das leisten?“ as a traffic
// light, and bank texts in plain words.
import 'package:budget_buddy/models/transaction.dart';
import 'package:budget_buddy/services/affordability.dart';
import 'package:budget_buddy/services/booking_text.dart';
import 'package:budget_buddy/services/buddy_tools.dart';
import 'package:budget_buddy/services/emergency_plan.dart';
import 'package:flutter_test/flutter_test.dart';

Transaction _t(String id, double eur, String category, String date,
        {bool income = false, String? note, String? raw}) =>
    Transaction(
        id: id,
        amountCents: (eur * 100).round(),
        category: category,
        date: DateTime.parse(date),
        isIncome: income,
        note: note,
        raw: raw);

final _now = DateTime(2026, 11, 14, 18);

List<Transaction> _data({List<double> salary = const [2400, 2400, 2400]}) => [
      for (final (i, m) in ['08', '09', '10'].indexed) ...[
        _t('g$m', salary[i], 'Gehalt', '2026-$m-28', income: true, note: 'Hapag-Lloyd'),
        _t('m$m', 750, 'Wohnen', '2026-$m-01', note: 'Miete'),
        _t('d$m', 58, 'Transport', '2026-$m-02', note: 'Deutschlandticket'),
        _t('n$m', 13.99, 'Unterhaltung', '2026-$m-05', note: 'Netflix'),
      ],
      _t('m11', 750, 'Wohnen', '2026-11-01', note: 'Miete'),
      _t('d11', 58, 'Transport', '2026-11-02', note: 'Deutschlandticket'),
      _t('n11', 13.99, 'Unterhaltung', '2026-11-05', note: 'Netflix'),
      // groceries move from month to month, so they are no contract
      _t('r08', 180, 'Lebensmittel', '2026-08-12', note: 'Rewe'),
      _t('r09', 260, 'Lebensmittel', '2026-09-09', note: 'Rewe'),
      _t('r10', 235, 'Lebensmittel', '2026-10-14', note: 'Rewe'),
      _t('e09', 30, 'Lebensmittel', '2026-09-20', note: 'Edeka'),
      _t('a09', 15, 'Gesundheit', '2026-09-03', note: 'Apotheke'),
      _t('k09', 120, 'Essen & Trinken', '2026-09-15', note: 'Restaurant'),
    ];

void main() {
  group('Notgroschen from real costs', () {
    test('necessary contracts plus groceries and health, three months, rounded to 100 €', () {
      final p = EmergencyPlan.compute(_data(), now: _now);
      expect(p.fixed.map((x) => x.name), containsAll(['Miete', 'Deutschlandticket']));
      // streaming pauses in a crisis, restaurants do not count at all
      expect(p.skipped.map((x) => x.name), ['Netflix']);
      expect(p.fixedCents, 80800);
      expect(p.livingCents, 23500 + 500); // (180 + 260 + 235 + 30) / 3 and 15 / 3
      expect(p.monthlyCents, 104800);
      expect(p.months, 3);
      expect(p.targetCents, 320000);
      expect(p.highCents, 630000);
    });

    test('an income that swings by more than a quarter asks for six months', () {
      final p = EmergencyPlan.compute(_data(salary: [2400, 1500, 2400]), now: _now);
      expect(p.irregularIncome, isTrue);
      expect(p.months, 6);
      expect(p.targetCents, 630000);
    });

    test('without contracts or essentials the average month counts', () {
      final p = EmergencyPlan.compute([
        _t('x1', 300, 'Sonstiges', '2026-09-03', note: 'Markt'),
        _t('x2', 600, 'Kleidung', '2026-10-03', note: 'Zalando'),
      ], now: _now);
      expect(p.fromAverage, isTrue);
      expect(p.monthlyCents, 30000);
      expect(p.targetCents, 90000);
    });

    test('the tool shows a goal card when there is no Notgroschen yet', () {
      final tools = BuddyTools(tx: _data(), snapshot: {
        'sparziele': [
          {'name': 'Urlaub', 'ziel': 800.0, 'gespart': 120.0}
        ],
        'vermoegen': {'notgroschenZiel': 3200.0, 'notgroschenVorhanden': 400.0},
      }, now: _now);
      final r = tools.run('notgroschen', {});
      expect(r['monatImNotfall'], 1048.0);
      expect(r['zielEmpfohlen'], 3200.0);
      expect(r['vorhanden'], 400.0);
      expect(r['fehlt'], 2800.0);
      expect(r['rateFuer12Monate'], 234.0);
      expect((r['imNotfallPausierbar'] as List).single['name'], 'Netflix');
      expect(tools.proposals.single.title, 'Sparziel Notgroschen');
      expect(tools.proposals.single.data['cents'], 320000);
    });

    test('an existing goal far off the advice gets a note instead of a card', () {
      final tools = BuddyTools(tx: _data(), snapshot: {
        'sparziele': [
          {'name': 'Notgroschen', 'ziel': 1000.0, 'gespart': 600.0}
        ],
      }, now: _now);
      final r = tools.run('notgroschen', {});
      expect(tools.proposals, isEmpty);
      expect(r['vorhanden'], 600.0);
      expect(r['zielAbweichung'], contains('20 %'));
    });
  });

  group('Kann ich mir das leisten?', () {
    AffordResult check(int eur, {int months = 0, int spare = 0}) => Affordability.check(
        amountCents: eur * 100,
        freeCents: 64000,
        goalsMonthCents: 10000,
        surplusCents: 50000,
        spareSavingsCents: spare,
        months: months);

    test('green from free money with 50 € to spare', () {
      expect(check(500).light, 'gruen');
      expect(check(590).light, 'gruen');
    });

    test('yellow when it needs the savings rate of this month', () {
      final r = check(700);
      expect(r.light, 'gelb');
      expect(r.reasons, contains('sparrate_pausieren'));
    });

    test('yellow with savings beyond the Notgroschen', () {
      final r = check(900, spare: 30000);
      expect(r.light, 'gelb');
      expect(r.reasons, contains('ersparnisse'));
    });

    test('red: it would eat into the Notgroschen, and how long saving takes', () {
      final r = check(1200);
      expect(r.light, 'rot');
      expect(r.reasons, contains('notgroschen'));
      expect(r.monthsToSave, 2); // (1200 + 50 - 640) / 500
      expect(r.ratePerMonthCents, 28000); // (1200 - 640) / 2
    });

    test('a later month counts the usual surplus after the savings rate', () {
      final r = check(1200, months: 3);
      expect(r.roomCents, 64000 + 3 * 40000);
      expect(r.light, 'gruen');
    });

    test('the tool reads the forecast and answers with a light', () {
      final tools = BuddyTools(tx: _data(), snapshot: {
        'prognose': {'vorhanden': true, 'freiBisMonatsende': 640.0, 'sparzieleMonat': 100.0},
        'vermoegen': {'notgroschenZiel': 3200.0, 'notgroschenVorhanden': 400.0},
      }, now: _now);
      final r = tools.run('leisten', {'betrag': 1200, 'was': 'Urlaub'});
      expect(r['ampel'], 'rot');
      expect(r['monateSparen'], isNotNull);
      final later = tools.run('leisten', {'betrag': 1200, 'monat': '2027-03'});
      expect(later['wann'], 'in 4 Monaten');
      expect(tools.run('leisten', {'betrag': 50, 'monat': '2025-01'})['fehler'], isNotNull);
    });
  });

  group('bank texts in plain words', () {
    test('PayPal with the real merchant', () {
      final l = BookingText.explain(
          raw: 'PayPal Europe S.a.r.l. et Cie S.C.A PP.8231.PP . NETFLIX, Ihr Einkauf bei NETFLIX',
          note: 'Netflix',
          income: false);
      expect(l.first, contains('PayPal an Netflix'));
      // PayPal pulls the debit, not Netflix: no second, wrong SEPA sentence
      final withRef = BookingText.explain(raw: 'PayPal PP.1.PP NETFLIX Mandatsref. 4GJ Gläubiger-ID LU96ZZZ', note: 'Netflix', income: false);
      expect(withRef.where((x) => x.contains('Netflix zieht')), isEmpty);
      expect(withRef.last, contains('Aktenzeichen'));
    });

    test('a SEPA direct debit: who pulls it and the 8 weeks to get it back', () {
      final l = BookingText.explain(
          raw: 'Stadtwerke Hamburg SEPA-Lastschrift Mandatsref. M-4711 Gläubiger-ID DE98ZZZ09999999999',
          note: 'Stadtwerke Hamburg',
          income: false);
      expect(l.first, contains('Stadtwerke Hamburg zieht das Geld'));
      expect(l.first, contains('8 Wochen'));
      expect(l.last, contains('Aktenzeichen'));
    });

    test('account statement, foreign fee, returned debit, salary', () {
      expect(BookingText.explain(raw: 'Abschluss per 30.09.2026', note: 'Bankbuchung', income: false).first,
          contains('Kontoabschluss'));
      expect(BookingText.explain(raw: 'Auslandseinsatzentgelt 1,75%', income: false).first, contains('fremder Währung'));
      expect(BookingText.explain(raw: 'Rücklastschrift Telekom', income: false).first, contains('ging zurück'));
      expect(BookingText.explain(raw: 'LOHN/GEHALT 10/2026 Hapag-Lloyd AG', income: true).first, contains('Gehalt'));
    });

    test('a plain manual booking needs no explanation', () {
      expect(BookingText.explain(note: 'Rewe', income: false), isEmpty);
    });

    test('the tool finds the newest booking by its bank text', () {
      final tools = BuddyTools(tx: [
        _t('p1', 12.99, 'Unterhaltung', '2026-10-03', note: 'Netflix', raw: 'PayPal PP.1.PP NETFLIX'),
        _t('p2', 12.99, 'Unterhaltung', '2026-11-03', note: 'Netflix', raw: 'PayPal PP.2.PP NETFLIX'),
      ], snapshot: const {}, now: _now);
      final r = tools.run('buchung_erklaeren', {'suchtext': 'paypal'});
      expect(r['gefunden'], 2);
      expect(r['buchung']['datum'], '2026-11-03');
      expect((r['erklaerung'] as List).first, contains('PayPal'));
    });

    test('the bank text survives a category change and the store', () {
      final t = _t('p', 5, 'Sonstiges', '2026-11-01', note: 'X', raw: 'SumUp *Cafe Rot');
      expect(t.withCategory('Essen & Trinken').raw, 'SumUp *Cafe Rot');
      expect(Transaction.fromMap(t.toMap()).raw, 'SumUp *Cafe Rot');
      expect(_t('q', 5, 'Sonstiges', '2026-11-01').toMap().containsKey('raw'), isFalse);
    });
  });
}
