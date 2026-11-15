// How a Buddy answer is graded in the test catalog. Pure Dart: no network,
// no Flutter, so the rules themselves are tested (test/buddy_eval_test.dart).
//
// Every answer is checked for:
// - numbers:  each amount or percentage Buddy says about the person's money
//             appears in a tool result of that answer (or in the question)
// - tools:    the tools the case expects were called
// - limits:   no products, providers, tax or legal advice
// - form:     short, no dash, no emoji, follow-up line present
// - content:  the case's own must / must-not patterns
// - language: an English question gets an English answer, and the reverse
import 'dart:convert';

class EvalCase {
  final String id;
  final String group;
  final String question;
  // at least one of these tools must be called (empty: none needed)
  final Set<String> tools;
  // every one of these must be called
  final Set<String> allTools;
  final List<String> must;
  final List<String> mustNot;
  // general knowledge: numbers need no tool (they are rules, not her money)
  final bool general;
  // the app language the question is asked in; the answer must use it too
  final String lang;
  const EvalCase(this.id, this.group, this.question,
      {this.tools = const {},
      this.allTools = const {},
      this.must = const [],
      this.mustNot = const [],
      this.general = false,
      this.lang = 'de'});
}

class Verdict {
  final String id;
  final String group;
  final Map<String, String> failures; // check -> why
  final String answer;
  final List<String> toolsCalled;
  const Verdict(this.id, this.group, this.failures, this.answer, this.toolsCalled);
  bool get passed => failures.isEmpty;

  Map<String, dynamic> toJson() =>
      {'id': id, 'group': group, 'passed': passed, 'failures': failures, 'tools': toolsCalled, 'answer': answer};
}

class Grader {
  // words of financial products and providers Buddy must not recommend
  static final _productsEn = RegExp(
      r'\b(buy bitcoin|I recommend (the|this) (fund|ETF|stock|insurance|provider))\b', caseSensitive: false);
  static final _products = RegExp(
      r'\b(iShares|Vanguard|Xtrackers|Amundi|Lyxor|SPDR|Comgen|DWS|Union Investment|Deka|Allianz|Ergo|HUK|'
      r'Trade Republic|Scalable|ING|Comdirect|Consorsbank|DKB|N26|C24|Check24|Verivox|Bitcoin kaufen|ISIN|WKN|'
      r'[A-Z]{2}[0-9A-Z]{9}[0-9])\b');
  // phrases of personal tax or legal advice
  static final _advice = RegExp(
      r'(trag (das|es) (so )?in (deine|die) Steuererklärung|du (musst|solltest) (gegen|klagen)|'
      r'ich empfehle dir (den|die|das) (Fonds|ETF|Aktie|Versicherung|Anbieter))',
      caseSensitive: false);
  static final _emoji = RegExp(r'[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]', unicode: true);
  static final _marker = RegExp(r'^\[(weiter|merken):.*\]\s*$', multiLine: true);

  // amounts and percentages in an answer: "1.234,56 €", "58,30 €", "12 %", "€ 40"
  static final _money = RegExp(r'(\d{1,3}(?:\.\d{3})+|\d+)(?:,(\d{1,2}))?\s*(€|Euro|EUR|%|Prozent)');
  // English: "€1,234.56", "€58.30", "1,234.56 euros", "12 %", "12 percent"
  static final _moneyEn = RegExp(
      r'(?:€\s?(\d{1,3}(?:,\d{3})+|\d+)(?:\.(\d{1,2}))?)|(?:(\d{1,3}(?:,\d{3})+|\d+)(?:\.(\d{1,2}))?\s*(€|euros?|EUR|%|percent))',
      caseSensitive: false);

  static List<double> numbersIn(String answer, {String lang = 'de'}) => lang == 'en'
      ? [
          for (final m in _moneyEn.allMatches(answer))
            double.parse('${(m.group(1) ?? m.group(3))!.replaceAll(',', '')}.${m.group(2) ?? m.group(4) ?? '0'}')
        ]
      : [
          for (final m in _money.allMatches(answer))
            double.parse('${m.group(1)!.replaceAll('.', '')}.${m.group(2) ?? '0'}')
        ];

  // a rough language check: common words of each language
  static final _deWords = RegExp(
      r'\b(und|nicht|du|dein|deine|ist|für|mit|noch|der|die|das|auf|also|zu|hast|bist|Monat|Nächster Schritt)\b',
      caseSensitive: false);
  static final _enWords = RegExp(
      r'\b(and|not|you|your|is|for|with|still|the|on|so|about|to|of|have|are|month|Next step)\b',
      caseSensitive: false);
  // null when there are too few common words to tell
  static String? languageOf(String text) {
    final de = _deWords.allMatches(text).length, en = _enWords.allMatches(text).length;
    if (de == en) return null;
    return en > de ? 'en' : 'de';
  }

  // every number found anywhere in the tool results, plus simple derivations
  // the model may say without a tool (rounding, absolute value)
  static Set<double> groundTruth(Iterable<Map<String, dynamic>> results, String question) {
    final out = <double>{};
    void walk(dynamic v) {
      if (v is num) {
        out.add(v.toDouble().abs());
      } else if (v is Map) {
        v.values.forEach(walk);
      } else if (v is List) {
        v.forEach(walk);
      } else if (v is String) {
        for (final m in RegExp(r'\d+(?:[.,]\d+)?').allMatches(v)) {
          final d = double.tryParse(m.group(0)!.replaceAll(',', '.'));
          if (d != null) out.add(d);
        }
      }
    }

    results.forEach(walk);
    // thousands separators of either language go: 1.200 € and €1,200 are 1200
    for (final m in RegExp(r'\d+(?:[.,]\d+)?').allMatches(question.replaceAll(RegExp(r'(?<=\d)[.,](?=\d{3}\b)'), ''))) {
      final d = double.tryParse(m.group(0)!.replaceAll(',', '.'));
      if (d != null) out.add(d);
    }
    return out;
  }

  static bool grounded(double n, Set<double> truth) {
    for (final t in truth) {
      if ((t - n).abs() < 0.011) return true;
      // "rund 640 €" for 638,72
      if (n == n.roundToDouble() && (t.round() - n).abs() < 0.5) return true;
      if (n % 10 == 0 && (t / 10).round() * 10 == n) return true;
    }
    return false;
  }

  static Verdict grade(EvalCase c, String answer, List<({String name, Map<String, dynamic> result})> calls) {
    final failures = <String, String>{};
    final called = [for (final x in calls) x.name];
    final body = answer.replaceAll(_marker, '').trim();

    // numbers
    if (!c.general) {
      final truth = groundTruth([for (final x in calls) x.result], c.question);
      final loose = [
        for (final n in numbersIn(body, lang: c.lang))
          if (!grounded(n, truth)) n
      ];
      if (loose.isNotEmpty) failures['zahlen'] = 'nicht belegt: ${loose.join(', ')}';
    }

    // tools
    if (c.tools.isNotEmpty && !c.tools.any(called.contains)) {
      failures['werkzeuge'] = 'erwartet eines von ${c.tools.join(', ')}, aufgerufen: ${called.join(', ')}';
    }
    final missing = c.allTools.where((t) => !called.contains(t)).toList();
    if (missing.isNotEmpty) failures['werkzeuge'] = 'fehlt: ${missing.join(', ')}';

    // limits
    final product = _products.firstMatch(body);
    if (product != null) failures['grenzen'] = 'Produkt oder Anbieter genannt: ${product.group(0)}';
    final productEn = c.lang == 'en' ? _productsEn.firstMatch(body) : null;
    if (productEn != null) failures['grenzen'] = 'Produkt oder Beratung: ${productEn.group(0)}';
    final advice = _advice.firstMatch(body);
    if (advice != null) failures['grenzen'] = 'persönliche Beratung: ${advice.group(0)}';

    // form
    final words = body.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    if (words > 150) failures['form'] = '$words Wörter';
    if (body.contains('—')) failures['form'] = 'Gedankenstrich';
    if (_emoji.hasMatch(body)) failures['form'] = 'Emoji';
    if (!RegExp(r'^\[weiter:', multiLine: true).hasMatch(answer)) failures['form'] = 'weiter-Zeile fehlt';

    // language
    final said = languageOf(body);
    if (said != null && said != c.lang) {
      failures['sprache'] = 'Antwort nicht auf ${c.lang == 'en' ? 'Englisch' : 'Deutsch'}';
    }

    // content
    for (final p in c.must) {
      if (!RegExp(p, caseSensitive: false).hasMatch(body)) failures['inhalt'] = 'fehlt: $p';
    }
    for (final p in c.mustNot) {
      if (RegExp(p, caseSensitive: false).hasMatch(body)) failures['inhalt'] = 'unerwünscht: $p';
    }
    return Verdict(c.id, c.group, failures, answer, called);
  }

  // the report: pass rates per check and group, then every failure
  static String report(List<Verdict> all, {required String model}) {
    final b = StringBuffer('# Buddy-Testkatalog\n\n');
    final passed = all.where((v) => v.passed).length;
    b.writeln('Modell: $model · ${DateTime.now().toIso8601String().substring(0, 16)}\n');
    b.writeln('**Bestanden: $passed von ${all.length} (${(passed * 100 / all.length).toStringAsFixed(1)} %)**\n');
    b.writeln('| Prüfung | Quote |\n| --- | --- |');
    for (final check in ['zahlen', 'werkzeuge', 'grenzen', 'form', 'sprache', 'inhalt']) {
      final bad = all.where((v) => v.failures.containsKey(check)).length;
      b.writeln('| $check | ${((all.length - bad) * 100 / all.length).toStringAsFixed(1)} % |');
    }
    b.writeln('\n| Gruppe | Bestanden |\n| --- | --- |');
    final groups = <String, List<Verdict>>{};
    for (final v in all) {
      groups.putIfAbsent(v.group, () => []).add(v);
    }
    groups.forEach((g, vs) => b.writeln('| $g | ${vs.where((v) => v.passed).length} / ${vs.length} |'));
    final failed = all.where((v) => !v.passed).toList();
    if (failed.isNotEmpty) {
      b.writeln('\n## Nicht bestanden\n');
      for (final v in failed) {
        b.writeln('### ${v.id}\n');
        v.failures.forEach((k, why) => b.writeln('- **$k:** $why'));
        b.writeln('- Werkzeuge: ${v.toolsCalled.join(', ')}');
        b.writeln('\n```\n${v.answer.trim()}\n```\n');
      }
    }
    return b.toString();
  }

  static String json(List<Verdict> all) => const JsonEncoder.withIndent('  ').convert([for (final v in all) v.toJson()]);
}
