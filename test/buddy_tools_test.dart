import 'package:budget_buddy/models/transaction.dart';
import 'package:budget_buddy/services/buddy_tools.dart';
import 'package:flutter_test/flutter_test.dart';

Transaction _t(String id, double eur, String category, String date, {bool income = false, String? note}) =>
    Transaction(
        id: id,
        amountCents: (eur * 100).round(),
        category: category,
        date: DateTime.parse(date),
        isIncome: income,
        note: note);

void main() {
  // three full months and the current one (today: 14 Nov 2026)
  final tx = [
    for (final m in ['08', '09', '10']) ...[
      _t('g$m', 2400, 'Gehalt', '2026-$m-28', income: true, note: 'Hapag-Lloyd'),
      _t('m$m', 750, 'Wohnen', '2026-$m-01', note: 'Miete'),
      _t('r$m', 220, 'Lebensmittel', '2026-$m-10', note: 'Rewe'),
      _t('n$m', 30, 'Abos', '2026-$m-05', note: 'Netflix'),
    ],
    _t('r1', 45.50, 'Lebensmittel', '2026-11-03', note: 'Rewe'),
    _t('e1', 12.80, 'Lebensmittel', '2026-11-04', note: 'Edeka'),
    _t('m11', 750, 'Wohnen', '2026-11-01', note: 'Miete'),
    _t('l1', 23.90, 'Essen gehen', '2026-11-08', note: 'Lieferando'),
    // a refund lowers spending, a transfer is not spending at all
    _t('ref', 10, 'Lebensmittel', '2026-11-09', income: true, note: 'Rewe Pfand'),
    _t('u1', 500, 'Umbuchung', '2026-11-02', note: 'aufs Tagesgeld'),
  ];
  final tools = BuddyTools(
    tx: tx,
    snapshot: {
      'konten': [
        {'name': 'Giro', 'art': 'Girokonto', 'saldo': 1830.0}
      ],
      'kontostand': 1830.0,
      'depotwert': 4200.0,
      'gesamtvermoegen': 6030.0,
      'vertraegeUndAbos': [
        {'name': 'Netflix', 'proMonat': 13.99},
        {'name': 'Handy', 'proMonat': 15.0},
      ],
      'prognose': {'vorhanden': true, 'freiBisMonatsende': 640.0},
      'sparziele': [
        {'name': 'Urlaub', 'ziel': 800.0, 'gespart': 120.0}
      ],
    },
    now: DateTime(2026, 11, 14, 18),
  );

  test('spending this month by category: refunds count against, transfers do not', () {
    final r = tools.run('ausgaben', {'von': '2026-11-01', 'bis': '2026-11-14'});
    expect(r['summe'], 822.20); // 45.50 + 12.80 + 750 + 23.90 - 10
    final cats = {for (final c in r['nachKategorie'] as List) c['name']: c['summe']};
    expect(cats['Lebensmittel'], 48.30);
    expect(cats.containsKey('Umbuchung'), isFalse);
    // the 14 days before for comparison
    expect(r['vergleich']['von'], '2026-10-18');
    expect(r['vergleich']['bis'], '2026-10-31');
  });

  test('spending by merchant and filtered to one merchant', () {
    final r = tools.run('ausgaben', {'von': '2026-08-01', 'bis': '2026-10-31', 'gruppierung': 'haendler', 'haendler': 'rewe'});
    expect(r['summe'], 660.0);
    expect((r['nachHaendler'] as List).single['name'], 'Rewe');
  });

  test('income by source', () {
    final r = tools.run('einnahmen', {'von': '2026-10-01', 'bis': '2026-10-31'});
    expect(r['summe'], 2400.0);
    expect((r['nachQuelle'] as List).single['name'], 'Hapag-Lloyd');
  });

  test('finding bookings, newest first, with count and sum', () {
    final r = tools.run('buchungen_suchen', {'text': 'miete', 'limit': 2});
    expect(r['anzahl'], 4);
    expect(r['summe'], -3000.0);
    expect((r['buchungen'] as List).first['datum'], '2026-11-01');
    expect(r['weitere'], 2);
  });

  test('months: income, spending, savings rate, current month marked', () {
    final r = tools.run('monatsverlauf', {'monate': 4});
    final months = r['monate'] as List;
    expect(months.first['monat'], '2026-08');
    expect(months.first['gespart'], 1400.0);
    expect(months.first['sparquoteProzent'], 58);
    expect(months.last['laufend'], isTrue);
  });

  test('what if: saving 200 a month on the usual month', () {
    final r = tools.run('was_waere_wenn', {'monatlich_sparen': 200, 'einmalig': 300});
    expect(r['ueblichEinnahmen'], 2400.0);
    expect(r['ueblichAusgaben'], 1000.0);
    expect(r['monatspufferVorher'], 1400.0);
    expect(r['monatspufferNachher'], 1200.0);
    expect(r['gespartNachEinemJahr'], 2400.0);
    expect(r['freiBisMonatsendeNachEinmalig'], 340.0);
  });

  test('a savings plan counts this month and compares with the usual buffer', () {
    final r = tools.run('sparplan', {'betrag': 800, 'bis': '2027-07', 'schon_gespart': 120});
    expect(r['monate'], 9);
    expect(r['rateProMonat'], 75.56);
    expect(r['machbar'], isTrue);
  });

  test('contracts sum per month', () {
    expect(tools.run('vertraege_und_abos', {})['summeProMonat'], 28.99);
  });

  test('bad input explains itself instead of failing', () {
    expect(tools.run('ausgaben', {'von': 'gestern'})['fehler'], contains('von'));
    expect(tools.run('sparplan', {'betrag': 500, 'bis': '2020-01'})['fehler'], contains('Vergangenheit'));
    expect(tools.run('gibtsnicht', {})['fehler'], contains('Unbekannt'));
  });

  group('calculator', () {
    test('exact arithmetic with precedence and parentheses', () {
      expect(tools.run('rechner', {'ausdruck': '(1850 - 1240) / 30'})['ergebnis'], 20.33);
      expect(Calculator.eval('2 + 3 * 4'), 14);
      expect(Calculator.eval('-(5 - 8) * 2'), 6);
      expect(Calculator.eval('12,5 * 2'), 25);
    });
    test('nothing but arithmetic is accepted', () {
      expect(tools.run('rechner', {'ausdruck': 'import dart:io'})['fehler'], isNotNull);
      expect(tools.run('rechner', {'ausdruck': '1/0'})['fehler'], contains('null'));
      expect(tools.run('rechner', {'ausdruck': '(1+2'})['fehler'], contains('Klammer'));
    });
  });

  test('every tool the server offers exists here', () {
    for (final name in BuddyTools.names) {
      expect(tools.run(name, {'von': '2026-11-01', 'bis': '2026-11-14', 'betrag': 1, 'bis_': '', 'ausdruck': '1'})['fehler'] ?? '',
          isNot(contains('Unbekannt')));
    }
  });

  test('steuer_schaetzung for an earlier year: asks for that pay, then gives the deadline and ELSTER fields', () {
    final ask = tools.run('steuer_schaetzung', {'jahr': 2022});
    expect(ask['fehlt'], contains('2022'));
    final r = tools.run('steuer_schaetzung', {'jahr': 2022, 'brutto_monat': 3000, 'monate_gearbeitet': 4});
    expect(r['abgabeBis'], '2026-12-31');
    expect(r['offeneJahre'], [2022, 2023, 2024, 2025]);
    expect(r['erstattungGeschaetzt'], greaterThan(800));
    expect((r['elster'] as List).map((f) => f['feld']), contains('Weitere Werbungskosten: Kontoführungsgebühren'));
    expect(r['regeln'], contains('1.200 €'));
    final late = tools.run('steuer_schaetzung', {'jahr': 2021, 'brutto_monat': 3000});
    expect(late['zuSpaet'], isTrue);
  });
}
