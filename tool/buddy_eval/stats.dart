// How fast and how expensive Buddy is, from the server's metrics.jsonl.
//
//   ssh root@SERVER "cd /opt/ahead/deploy && docker compose exec -T server cat /app/.data/metrics.jsonl" > metrics.jsonl
//   dart run tool/buddy_eval/stats.dart metrics.jsonl
//
// Goals from the plan: first word under 1.5 s (median), under 4 s (p90);
// a free user (30 questions) costs well under 0.30 $ a month.
import 'dart:convert';
import 'dart:io';

double _pct(List<num> xs, double p) {
  if (xs.isEmpty) return 0;
  final s = [...xs]..sort();
  return s[((s.length - 1) * p).round()].toDouble();
}

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('Pfad zu metrics.jsonl fehlt');
    exit(64);
  }
  final rows = <Map<String, dynamic>>[];
  for (final l in File(args.first).readAsLinesSync()) {
    try {
      rows.add(jsonDecode(l) as Map<String, dynamic>);
    } catch (_) {}
  }
  if (rows.isEmpty) {
    stdout.writeln('Keine Messwerte.');
    return;
  }
  // one answer = all steps with the same turn id
  final turns = <String, List<Map<String, dynamic>>>{};
  for (final r in rows) {
    turns.putIfAbsent('${r['turn']}', () => []).add(r);
  }
  final first = [for (final r in rows) if (r['bisErstesWort'] is num) r['bisErstesWort'] as num];
  final cost = {for (final t in turns.entries) t.key: t.value.fold<double>(0, (a, r) => a + ((r['kostenUsd'] as num?) ?? 0))};
  final steps = [for (final t in turns.values) t.length];
  final users = <String, double>{};
  for (final r in rows) {
    users['${r['who']}'] = (users['${r['who']}'] ?? 0) + ((r['kostenUsd'] as num?) ?? 0);
  }
  final models = <String, int>{};
  for (final t in turns.values) {
    final m = '${t.first['model']}';
    models[m] = (models[m] ?? 0) + 1;
  }
  final tools = <String, int>{};
  for (final r in rows) {
    for (final t in (r['tools'] as List? ?? const [])) {
      tools['$t'] = (tools['$t'] ?? 0) + 1;
    }
  }
  final cacheRead = rows.fold<num>(0, (a, r) => a + ((r['cacheRead'] as num?) ?? 0));
  final input = rows.fold<num>(0, (a, r) => a + ((r['input'] as num?) ?? 0) + ((r['cacheRead'] as num?) ?? 0));
  final costs = cost.values.toList();
  String s(num ms) => '${(ms / 1000).toStringAsFixed(2)} s';
  String usd(num x) => '${x.toStringAsFixed(4)} \$';

  stdout.writeln('# Buddy in Zahlen\n');
  stdout.writeln('${turns.length} Antworten, ${rows.length} Schritte, ${users.length} Konten\n');
  stdout.writeln('| | Median | p90 |\n| --- | --- | --- |');
  stdout.writeln('| bis zum ersten Wort | ${s(_pct(first, .5))} | ${s(_pct(first, .9))} |');
  stdout.writeln('| Schritte pro Antwort | ${_pct(steps, .5).toInt()} | ${_pct(steps, .9).toInt()} |');
  stdout.writeln('| Kosten pro Antwort | ${usd(_pct(costs, .5))} | ${usd(_pct(costs, .9))} |');
  final avg = costs.fold<double>(0, (a, b) => a + b) / costs.length;
  stdout.writeln('\nDurchschnitt pro Antwort: ${usd(avg)}, also 30 Gratisfragen etwa ${usd(avg * 30)} im Monat.');
  stdout.writeln('Aus dem Cache gelesen: ${input == 0 ? 0 : (cacheRead * 100 / input).round()} % der Eingabe.\n');
  stdout.writeln('Modelle: ${models.entries.map((e) => '${e.key} ${e.value}').join(', ')}');
  final top = tools.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  stdout.writeln('Werkzeuge: ${top.take(8).map((e) => '${e.key} ${e.value}').join(', ')}');
  final heavy = users.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  stdout.writeln('Teuerste Konten: ${heavy.take(3).map((e) => '${e.key} ${usd(e.value)}').join(', ')}');
  if (_pct(first, .5) > 1500) {
    stdout.writeln('\n**Erstes Wort im Median über 1,5 s.** Prüfen: Modellwahl, Zahl der Schritte, Cache-Quote.');
  }
}
