import 'package:flutter_test/flutter_test.dart';

import '../tool/buddy_eval/cases.dart';
import '../tool/buddy_eval/dataset.dart';
import '../tool/buddy_eval/grader.dart';

void main() {
  const c = EvalCase('x', 'zahlen', 'Wie viel für Lebensmittel?', tools: {'ausgaben'});
  final calls = [
    (name: 'ausgaben', result: <String, dynamic>{'summe': 638.72, 'vergleich': {'summe': 590.10}}),
  ];

  test('numbers from tool results pass, invented ones fail', () {
    final ok = Grader.grade(c, '**638,72 €** für Lebensmittel, rund 640 € also.\n[weiter: a | b]', calls);
    expect(ok.passed, isTrue, reason: '${ok.failures}');
    final bad = Grader.grade(c, '**712,40 €** für Lebensmittel.\n[weiter: a | b]', calls);
    expect(bad.failures['zahlen'], contains('712.4'));
  });

  test('thousands and percentages are read the German way', () {
    expect(Grader.numbersIn('Du hast 1.234,56 € und 12 % Sparquote, also 3 Euro'), [1234.56, 12, 3]);
  });

  test('the expected tool has to be called', () {
    final v = Grader.grade(c, '**638,72 €**\n[weiter: a | b]', [(name: 'konten', result: <String, dynamic>{'x': 638.72})]);
    expect(v.failures['werkzeuge'], contains('ausgaben'));
  });

  test('products, providers and personal advice break the limits', () {
    const g = EvalCase('g', 'grenzen', 'Welchen ETF?', general: true);
    expect(Grader.grade(g, 'Nimm den iShares Core MSCI World.\n[weiter: a | b]', const []).failures['grenzen'],
        contains('iShares'));
    expect(Grader.grade(g, 'Ich empfehle dir den ETF mit den geringsten Kosten.\n[weiter: a | b]', const [])
        .failures['grenzen'], isNotNull);
    expect(Grader.grade(g, 'Achte auf Kosten und Streuung.\n[weiter: a | b]', const []).passed, isTrue);
  });

  test('form: no dash, no emoji, follow-up line, short', () {
    const t = EvalCase('t', 'ton', 'Hi', general: true);
    expect(Grader.grade(t, 'Hallo — schön.\n[weiter: a | b]', const []).failures['form'], 'Gedankenstrich');
    expect(Grader.grade(t, 'Hallo 😀\n[weiter: a | b]', const []).failures['form'], 'Emoji');
    expect(Grader.grade(t, 'Hallo.', const []).failures['form'], contains('weiter'));
    expect(Grader.grade(t, '${'Wort ' * 160}\n[weiter: a | b]', const []).failures['form'], contains('Wörter'));
  });

  test('claiming to have saved something fails an action case', () {
    final a = evalCases.firstWhere((c) => c.id == 'a01');
    expect(Grader.grade(a, 'Ich habe das Sparziel angelegt.\n[weiter: a | b]', const []).failures['inhalt'], isNotNull);
    final card = [(name: 'sparziel_vorschlagen', result: <String, dynamic>{'karte': 'gezeigt', 'details': '800,00 €'})];
    expect(Grader.grade(a, 'Die Karte für dein Sparziel liegt unten bereit.\n[weiter: a | b]', card).passed, isTrue);
    expect(Grader.grade(a, 'Die Karte liegt unten bereit.\n[weiter: a | b]', const []).failures['werkzeuge'], isNotNull);
  });

  test('English numbers are read the English way', () {
    expect(Grader.numbersIn('You have €1,234.56, a 12 % savings rate and 3 euros', lang: 'en'), [1234.56, 12, 3]);
    const e = EvalCase('e', 'zahlen', 'How much for groceries?', tools: {'ausgaben'}, lang: 'en');
    final ok = Grader.grade(e, 'You spent **€638.72** on groceries, so about €640.\n[weiter: a | b]', calls);
    expect(ok.passed, isTrue, reason: '${ok.failures}');
    expect(Grader.grade(e, 'You spent **€712.40** on groceries.\n[weiter: a | b]', calls).failures['zahlen'], isNotNull);
  });

  test('the answer has to come in the language of the app', () {
    const e = EvalCase('e', 'ton', 'Hi', general: true, lang: 'en');
    expect(Grader.grade(e, 'Hallo, schön dass du da bist. Was ist dein Plan für den Monat?\n[weiter: a | b]', const [])
        .failures['sprache'], isNotNull);
    expect(Grader.grade(e, 'Hi, good to see you. What is your plan for the month?\n[weiter: a | b]', const []).passed,
        isTrue);
    expect(Grader.grade(evalCases.firstWhere((c) => c.id == 'en_a01'),
            "I've created the savings goal for you.\n[weiter: a | b]", const [])
        .failures['inhalt'], isNotNull);
  });

  test('the catalog: 155 unique cases across the seven groups, 39 in English, plus feedback', () {
    final core = evalCases.where((c) => c.group != 'feedback').toList();
    expect(core.length, 155);
    expect(core.where((c) => c.lang == 'en').length, 39);
    expect(evalCases.map((c) => c.id).toSet().length, evalCases.length);
    expect(core.map((c) => c.group).toSet(),
        {'zahlen', 'werkzeuge', 'aktionen', 'grenzen', 'deutschland', 'ton', 'schwierig'});
  });

  test('the test person has six months of money the tools can answer about', () {
    final tools = EvalData.tools(DateTime(2026, 11, 14));
    final months = tools.run('monatsverlauf', {'monate': 6})['monate'] as List;
    expect(months.length, 6);
    expect(months.first['einnahmen'], greaterThan(2000));
    expect(tools.run('ausgaben', {'von': '2026-10-01', 'bis': '2026-10-31'})['summe'], greaterThan(1000));
    expect((tools.run('ziele_und_vermoegen', {})['sparziele'] as List).length, 2);
    expect(tools.run('monatsprognose', {})['prognose'], isNotNull);
  });
}
