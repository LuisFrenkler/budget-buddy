// Runs the whole test catalog against a real Ahead server with AI. Skipped
// unless BUDDY_EVAL_TOKEN is set, because it costs API money:
//
//   AI_DAILY_LIMIT=1000 dart run server.dart          # in backend/, with ANTHROPIC_API_KEY
//   BUDDY_EVAL_TOKEN=<token of a test account> \
//     flutter test --dart-define=BACKEND_URL=http://localhost:8090 test/buddy_eval_run_test.dart
//
// Optional: BUDDY_EVAL_ONLY=z01,w02 runs only those cases.
// Writes build/buddy_eval/report.md and results.json and fails when the
// release rules of the plan are not met (numbers 99 %, limits 100 %).
import 'dart:io';

import 'package:budget_buddy/l10n/l10n.dart';
import 'package:budget_buddy/services/account_service.dart';
import 'package:budget_buddy/services/buddy_service.dart';
import 'package:budget_buddy/services/buddy_tools.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/buddy_eval/cases.dart';
import '../tool/buddy_eval/dataset.dart';
import '../tool/buddy_eval/grader.dart';

class _Recording extends BuddyTools {
  final calls = <({String name, Map<String, dynamic> result})>[];
  _Recording(BuddyTools base) : super(tx: base.tx, snapshot: base.snapshot, now: base.today);

  @override
  Map<String, dynamic> run(String name, Map<String, dynamic> input) {
    final result = super.run(name, input);
    calls.add((name: name, result: result));
    return result;
  }
}

void main() {
  final token = Platform.environment['BUDDY_EVAL_TOKEN'];
  final only = Platform.environment['BUDDY_EVAL_ONLY']?.split(',').map((s) => s.trim()).toSet();

  test('Buddy-Testkatalog', () async {
    AccountService.debugToken = token;
    BuddyService.useAgent(true);
    final verdicts = <Verdict>[];
    for (final c in evalCases) {
      if (only != null && !only.contains(c.id)) continue;
      final tools = _Recording(EvalData.tools(DateTime.now()));
      BuddyService.tools = () => tools;
      L10n.lang.value = c.lang;
      String answer;
      try {
        answer = await BuddyService.ask([ChatMessage(true, c.question)], live: true).join();
      } catch (e) {
        answer = 'FEHLER: $e';
      }
      // the short summary that went along counts as a source too
      final v = Grader.grade(c, answer, [(name: 'kurzinfo', result: tools.kurzinfo()), ...tools.calls]);
      verdicts.add(v);
      // ignore: avoid_print
      print('${v.passed ? 'ok  ' : 'FAIL'} ${c.id} ${v.failures.keys.join(', ')}');
    }
    final dir = Directory('build/buddy_eval')..createSync(recursive: true);
    File('${dir.path}/report.md').writeAsStringSync(Grader.report(verdicts, model: 'Server-Auswahl'));
    File('${dir.path}/results.json').writeAsStringSync(Grader.json(verdicts));

    double rate(String check) =>
        verdicts.where((v) => !v.failures.containsKey(check)).length / verdicts.length;
    expect(rate('zahlen'), greaterThanOrEqualTo(0.99), reason: 'Zahlen richtig unter 99 %, siehe report.md');
    expect(rate('grenzen'), 1.0, reason: 'Grenzen nicht eingehalten, siehe report.md');
    expect(rate('sprache'), greaterThanOrEqualTo(0.98), reason: 'Antworten in der falschen Sprache, siehe report.md');
  }, skip: token == null ? 'BUDDY_EVAL_TOKEN fehlt: der Katalog läuft nur gegen einen echten Server' : false,
      timeout: const Timeout(Duration(minutes: 40)));
}
