// Turns thumbs-down feedback into test cases for the catalog.
//
//   scp root@SERVER:/opt/ahead/backend/.data/feedback.jsonl .
//   dart run tool/buddy_eval/feedback_to_cases.dart feedback.jsonl > neue_faelle.txt
//
// Prints one EvalCase per bad answer, with the tools that answer used as the
// expectation and the reason as a comment. Review each one, add must / mustNot
// patterns for what went wrong, then paste them into cases.dart.
import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('Pfad zu feedback.jsonl fehlt');
    exit(64);
  }
  final lines = File(args.first).readAsLinesSync().where((l) => l.trim().isNotEmpty);
  var n = 0, up = 0, down = 0;
  final reasons = <String, int>{};
  final seen = <String>{};
  for (final line in lines) {
    final e = jsonDecode(line) as Map<String, dynamic>;
    if (e['rating'] == 'up') {
      up++;
      continue;
    }
    down++;
    final reason = '${e['reason'] ?? ''}';
    reasons[reason] = (reasons[reason] ?? 0) + 1;
    final q = '${e['question'] ?? ''}'.trim();
    if (q.isEmpty || !seen.add(q.toLowerCase())) continue;
    n++;
    final tools = (e['tools'] as List? ?? const []).map((t) => "'$t'").toSet().join(', ');
    final note = '${e['note'] ?? ''}'.replaceAll('\n', ' ');
    stdout.writeln("  // Feedback ${e['at']}: $reason${note.isEmpty ? '' : ' · $note'}");
    stdout.writeln("  EvalCase('f${n.toString().padLeft(3, '0')}', 'feedback', '${q.replaceAll("'", "\\'")}'"
        "${tools.isEmpty ? '' : ', tools: {$tools}'}),");
  }
  stderr.writeln('$up Daumen hoch, $down runter (${up + down == 0 ? 0 : (up * 100 / (up + down)).round()} % gut)');
  reasons.forEach((r, c) => stderr.writeln('  $r: $c'));
}
