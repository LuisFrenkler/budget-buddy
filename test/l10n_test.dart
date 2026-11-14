// Every German text the app shows through tr('…') needs an English entry,
// with the same {placeholders}. tool/l10n/extract.py --missing lists gaps,
// tool/l10n/build_en.py fills them.
import 'dart:io';

import 'package:budget_buddy/l10n/en.dart';
import 'package:budget_buddy/l10n/l10n.dart';
import 'package:budget_buddy/services/glossary.dart';
import 'package:budget_buddy/services/life_stages.dart';
import 'package:flutter_test/flutter_test.dart';

// one or more adjacent single-quoted literals right after tr(
final _call = RegExp(r"""\btr\(\s*((?:'(?:[^'\\\n]|\\.)*'\s*)+)""");
final _literal = RegExp(r"""'((?:[^'\\\n]|\\.)*)'""");

String _unescape(String s) => s.replaceAllMapped(RegExp(r'\\(.)'), (m) {
      switch (m[1]) {
        case 'n':
          return '\n';
        case 't':
          return '\t';
        default:
          return m[1]!;
      }
    });

Set<String> _placeholders(String s) => RegExp(r'\{\w+\}').allMatches(s).map((m) => m[0]!).toSet();

void main() {
  final keys = <String, String>{};
  for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
    if (!f.path.endsWith('.dart') || f.path.contains('/l10n/')) continue;
    for (final call in _call.allMatches(f.readAsStringSync())) {
      final key = _literal.allMatches(call[1]!).map((m) => _unescape(m[1]!)).join();
      keys.putIfAbsent(key, () => f.path);
    }
  }

  test('the scan finds the app texts', () {
    expect(keys.length, greaterThan(1500));
  });

  test('every tr() text has an English entry', () {
    final missing = [
      for (final e in keys.entries)
        if (!en.containsKey(e.key)) '${e.value}: ${e.key}'
    ];
    expect(missing, isEmpty, reason: 'run tool/l10n/extract.py --missing');
  });

  test('translations keep the placeholders', () {
    final wrong = [
      for (final e in en.entries)
        if (!_placeholders(e.key).containsAll(_placeholders(e.value)) ||
            !_placeholders(e.value).containsAll(_placeholders(e.key)))
          e.key
    ];
    expect(wrong, isEmpty);
  });

  test('life stages and glossary are translated too', () {
    for (final stage in LifeStages.all) {
      for (final s in [stage.name, stage.tagline]) {
        expect(en.containsKey(s), isTrue, reason: s);
      }
      for (final step in stage.steps) {
        for (final s in [step.title, step.subtitle, step.prompt, step.offline]) {
          expect(en.containsKey(s), isTrue, reason: s);
        }
      }
    }
    for (final t in Glossary.terms) {
      expect(en.containsKey(t.term), isTrue, reason: t.term);
      expect(en.containsKey(t.text), isTrue, reason: t.term);
    }
  });

  test('tr fills placeholders in either language', () {
    L10n.lang.value = 'en';
    expect(tr('{x} im Monat', {'x': '5 €'}), '5 € a month');
    expect(tr('Glossary.terms'), 'Glossary.terms'); // unknown text stays
    L10n.lang.value = 'de';
    expect(tr('{x} im Monat', {'x': '5 €'}), '5 € im Monat');
  });
}
