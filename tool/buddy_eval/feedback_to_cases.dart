// Turns thumbs-down feedback into test cases for the catalog: the learning
// loop. Every bad answer becomes a case, so it can't come back unnoticed.
//
//   tool/buddy_eval/learn.sh root@SERVER        # fetch, convert, report
//   dart run tool/buddy_eval/feedback_to_cases.dart feedback.jsonl [--write]
//
// Prints one EvalCase per new bad answer (questions already in the catalog
// are skipped), in the question's language, with the tools that answer used
// and a hint from the reason. With --write they go to cases_feedback.dart,
// which the catalog includes. Review them: sharpen must / mustNot for what
// went wrong, then run the catalog.
import 'dart:convert';
import 'dart:io';

import 'cases.dart';

// what each reason in the app's sheet usually needs as a check
const _hints = {
  'Zahl stimmt nicht': 'die Zahlen prüft der Katalog schon; Werkzeug angeben, das sie liefert',
  'Hilft mir nicht': "must: [r'Nächster Schritt'] oder ein konkretes Stichwort",
  'Zu lang': 'Wörtergrenze greift ab 150; strenger: mustNot langer Einleitung',
  'Falscher Ton': "mustNot: [r'Gute Frage', ...] für das, was gestört hat",
};

String _quote(String s) => "'${s.replaceAll(r'\', r'\\').replaceAll("'", r"\'").replaceAll(r'$', r'\$')}'";

void main(List<String> args) {
  final path = args.where((a) => !a.startsWith('--')).firstOrNull;
  if (path == null) {
    stderr.writeln('Pfad zu feedback.jsonl fehlt');
    exit(64);
  }
  final known = {for (final c in evalCases) c.question.toLowerCase().trim()};
  final lines = File(path).readAsLinesSync().where((l) => l.trim().isNotEmpty);
  var up = 0, down = 0, n = 0;
  final reasons = <String, int>{};
  final out = StringBuffer();
  final seen = <String>{};
  for (final line in lines) {
    final Map<String, dynamic> e;
    try {
      e = jsonDecode(line) as Map<String, dynamic>;
    } catch (_) {
      continue;
    }
    if (e['rating'] == 'up') {
      up++;
      continue;
    }
    down++;
    final reason = '${e['reason'] ?? ''}';
    reasons[reason] = (reasons[reason] ?? 0) + 1;
    final q = '${e['question'] ?? ''}'.trim();
    if (q.isEmpty || known.contains(q.toLowerCase()) || !seen.add(q.toLowerCase())) continue;
    n++;
    final lang = e['lang'] == 'en' ? 'en' : 'de';
    final tools = (e['tools'] as List? ?? const []).map((t) => _quote('$t')).toSet().join(', ');
    final note = '${e['note'] ?? ''}'.replaceAll('\n', ' ');
    out.writeln('  // ${e['at']}: $reason${note.isEmpty ? '' : ' · $note'}');
    if (_hints.containsKey(reason)) out.writeln('  // Idee: ${_hints[reason]}');
    out.writeln("  EvalCase('f${n.toString().padLeft(3, '0')}', 'feedback', ${_quote(q)}"
        "${tools.isEmpty ? ', general: true' : ', tools: {$tools}'}${lang == 'en' ? ", lang: 'en'" : ''}),");
  }
  if (args.contains('--write')) {
    File('tool/buddy_eval/cases_feedback.dart').writeAsStringSync('''// Generated from thumbs-down feedback by feedback_to_cases.dart --write.
// Review every case: what exactly went wrong? Add must / mustNot for it.
import 'grader.dart';

const evalCasesFeedback = <EvalCase>[
$out];
''');
    stderr.writeln('$n neue Fälle in tool/buddy_eval/cases_feedback.dart');
  } else {
    stdout.write(out);
  }
  stderr.writeln('$up Daumen hoch, $down runter (${up + down == 0 ? 0 : (up * 100 / (up + down)).round()} % gut)');
  reasons.forEach((r, c) => stderr.writeln('  $r: $c'));
}
