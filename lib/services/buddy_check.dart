// Buddy checks his own numbers before the answer stays on screen: every euro
// amount has to come from what he looked up (tool results, the short summary),
// from the question, from earlier in the chat, or from a simple step on those
// (rounding, sum, difference, month <-> year). An amount that comes from
// nowhere goes back to him once, to look it up or drop it.
//
// The test catalog's grader uses the same rules, so what counts as "made up"
// is the same live and in the tests.

class BuddyCheck {
  // German: 1.234,56 € · 58 Euro · 12 %. English: €1,234.56 · 58 euros · 12 %
  static final _de = RegExp(r'(\d{1,3}(?:\.\d{3})+|\d+)(?:,(\d{1,2}))?\s*(€|Euro|EUR|%|Prozent)');
  static final _en = RegExp(
      r'(?:€\s?(\d{1,3}(?:,\d{3})+|\d+)(?:\.(\d{1,2}))?)|(?:(\d{1,3}(?:,\d{3})+|\d+)(?:\.(\d{1,2}))?\s*(€|euros?|EUR|%|percent))',
      caseSensitive: false);
  static final _euroDe = RegExp(r'(\d{1,3}(?:\.\d{3})+|\d+)(?:,(\d{1,2}))?\s*(€|Euro|EUR)');
  static final _euroEn = RegExp(
      r'(?:€\s?(\d{1,3}(?:,\d{3})+|\d+)(?:\.(\d{1,2}))?)|(?:(\d{1,3}(?:,\d{3})+|\d+)(?:\.(\d{1,2}))?\s*(€|euros?|EUR))',
      caseSensitive: false);

  // amounts and percentages in a text, as numbers
  static List<double> numbersIn(String text, {String lang = 'de', bool euroOnly = false}) {
    if (lang == 'en') {
      return [
        for (final m in (euroOnly ? _euroEn : _en).allMatches(text))
          double.parse('${(m.group(1) ?? m.group(3))!.replaceAll(',', '')}.${m.group(2) ?? m.group(4) ?? '0'}')
      ];
    }
    return [
      for (final m in (euroOnly ? _euroDe : _de).allMatches(text))
        double.parse('${m.group(1)!.replaceAll('.', '')}.${m.group(2) ?? '0'}')
    ];
  }

  // every number in the data Buddy looked at, plus numbers the person wrote
  static Set<double> truth(Iterable<Object?> data, Iterable<String> texts) {
    final out = <double>{};
    void walk(Object? v) {
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

    data.forEach(walk);
    for (final t in texts) {
      // thousands separators of either language go: 1.200 € and €1,200 are 1200
      final plain = t.replaceAll(RegExp(r'(?<=\d)[.,](?=\d{3}\b)'), '');
      for (final m in RegExp(r'\d+(?:[.,]\d+)?').allMatches(plain)) {
        final d = double.tryParse(m.group(0)!.replaceAll(',', '.'));
        if (d != null) out.add(d);
      }
    }
    return out;
  }

  // the simple steps a person would do in their head: sum and difference of
  // two known amounts, a month as a year and back
  static Set<double> derived(Set<double> truth) {
    final base = truth.where((t) => t >= 1).toList()..sort();
    final small = base.length > 80 ? base.sublist(base.length - 80) : base;
    final out = {...truth};
    for (final a in small) {
      out
        ..add(a * 12)
        ..add(a / 12);
      for (final b in small) {
        out
          ..add(a + b)
          ..add((a - b).abs());
      }
    }
    return out;
  }

  static bool grounded(double n, Set<double> truth) {
    for (final t in truth) {
      if ((t - n).abs() < 0.011) return true;
      // "rund 640 €" for 638,72
      if (n == n.roundToDouble() && (t.round() - n).abs() < 0.5) return true;
      if (n % 10 == 0 && (t / 10).round() * 10 == n) return true;
      if (n % 50 == 0 && n >= 100 && (t / 50).round() * 50 == n) return true;
    }
    return false;
  }

  // euro amounts in [answer] that Buddy can't have taken from anywhere
  static List<double> loose(String answer,
      {required Iterable<Object?> data, required Iterable<String> texts, String lang = 'de'}) {
    final amounts = numbersIn(answer, lang: lang, euroOnly: true);
    if (amounts.isEmpty) return const [];
    final known = derived(truth(data, texts));
    return [
      for (final n in amounts)
        if (!grounded(n, known)) n
    ];
  }

  // what goes back to Buddy when an amount is loose
  static String recheck(List<double> amounts, {String lang = 'de'}) {
    final list = amounts.map((n) => n == n.roundToDouble() ? '${n.round()}' : n.toStringAsFixed(2)).join(', ');
    return 'Prüfhinweis der App, nicht von der Person: Diese Beträge in deiner Antwort stehen in keinem '
        'Werkzeugergebnis und nicht in der Kurzinfo: $list. Wenn es Zahlen der Person sind, hol sie mit dem '
        'passenden Werkzeug oder rechne sie mit dem Rechner. Wenn es allgemeine Regeln sind (etwa ein '
        'Freibetrag), dürfen sie bleiben. Schreib dann die ganze Antwort noch einmal, vollständig und '
        '${lang == 'en' ? 'auf Englisch' : 'auf Deutsch'}, ohne diesen Hinweis zu erwähnen.';
  }
}
