// Per tool: in how many answers it was used, what such an answer costs on
// average, how many steps it takes and how long until the first word. Tools
// run on the phone between two steps, so the time shows up as the wait for
// the next step; the slowest and the most expensive come first.
String toolReport(List<Map<String, dynamic>> rows) {
  final turns = <String, List<Map<String, dynamic>>>{};
  for (final r in rows) {
    turns.putIfAbsent('${r['turn']}', () => []).add(r);
  }
  final stats = <String, ({int n, double cost, int steps, List<num> first})>{};
  for (final t in turns.values) {
    final tools = {for (final r in t) ...(r['tools'] as List? ?? const []).map((x) => '$x')};
    final cost = t.fold<double>(0, (a, r) => a + ((r['kostenUsd'] as num?) ?? 0));
    final first = t.map((r) => r['bisErstesWort']).whereType<num>().firstOrNull;
    for (final name in tools) {
      final s = stats[name] ?? (n: 0, cost: 0.0, steps: 0, first: <num>[]);
      stats[name] = (n: s.n + 1, cost: s.cost + cost, steps: s.steps + t.length, first: [...s.first, if (first != null) first]);
    }
  }
  if (stats.isEmpty) return 'Noch keine Werkzeug-Aufrufe.\n';
  num median(List<num> xs) {
    if (xs.isEmpty) return 0;
    final s = [...xs]..sort();
    return s[(s.length - 1) ~/ 2];
  }

  final list = stats.entries.toList()
    ..sort((a, b) {
      final ma = median(a.value.first), mb = median(b.value.first);
      return mb != ma ? mb.compareTo(ma) : (b.value.cost / b.value.n).compareTo(a.value.cost / a.value.n);
    });
  final b = StringBuffer()
    ..writeln('## Werkzeuge\n')
    ..writeln('| Werkzeug | Antworten | Kosten je Antwort | Schritte | erstes Wort (Median) |')
    ..writeln('| --- | --- | --- | --- | --- |');
  for (final e in list) {
    final s = e.value;
    b.writeln('| ${e.key} | ${s.n} | ${(s.cost / s.n).toStringAsFixed(4)} \$ | '
        '${(s.steps / s.n).toStringAsFixed(1)} | ${(median(s.first) / 1000).toStringAsFixed(2)} s |');
  }
  return b.toString();
}
