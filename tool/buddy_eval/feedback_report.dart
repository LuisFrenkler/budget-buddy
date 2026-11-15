// What people say about Buddy's answers, from the server's feedback.jsonl:
// how many thumbs up, which reasons come with a thumbs down, and which tools
// sit in the answers that miss most often. Used by stats.dart.
String feedbackReport(List<Map<String, dynamic>> rows) {
  if (rows.isEmpty) return 'Noch kein Feedback.\n';
  final up = rows.where((r) => r['rating'] == 'up').length;
  final down = rows.length - up;
  final b = StringBuffer()
    ..writeln('## Feedback\n')
    ..writeln('${rows.length} Bewertungen: $up gut, $down schlecht '
        '(${(up * 100 / rows.length).round()} % gut)\n');

  // reasons of the thumbs down, most frequent first
  final reasons = <String, int>{};
  for (final r in rows.where((r) => r['rating'] != 'up')) {
    final k = '${r['reason'] ?? ''}'.trim().isEmpty ? 'ohne Grund' : '${r['reason']}';
    reasons[k] = (reasons[k] ?? 0) + 1;
  }
  if (reasons.isNotEmpty) {
    b.writeln('| Grund | Anzahl |\n| --- | --- |');
    for (final e in reasons.entries.toList()..sort((a, c) => c.value.compareTo(a.value))) {
      b.writeln('| ${e.key} | ${e.value} |');
    }
    b.writeln();
  }

  // per tool: in how many rated answers, how many of them bad
  final used = <String, int>{}, bad = <String, int>{};
  for (final r in rows) {
    for (final t in {...(r['tools'] as List? ?? const []).map((x) => '$x')}) {
      used[t] = (used[t] ?? 0) + 1;
      if (r['rating'] != 'up') bad[t] = (bad[t] ?? 0) + 1;
    }
  }
  if (used.isNotEmpty) {
    final list = used.keys.toList()
      ..sort((a, c) {
        final ra = (bad[a] ?? 0) / used[a]!, rc = (bad[c] ?? 0) / used[c]!;
        return rc != ra ? rc.compareTo(ra) : used[c]!.compareTo(used[a]!);
      });
    b.writeln('| Werkzeug | Antworten | davon schlecht |\n| --- | --- | --- |');
    for (final t in list) {
      b.writeln('| $t | ${used[t]} | ${((bad[t] ?? 0) * 100 / used[t]!).round()} % |');
    }
    b.writeln();
  }

  // per language
  final langs = <String, List<int>>{};
  for (final r in rows) {
    final l = '${r['lang'] ?? ''}'.isEmpty ? 'de' : '${r['lang']}';
    final v = langs.putIfAbsent(l, () => [0, 0]);
    v[0]++;
    if (r['rating'] != 'up') v[1]++;
  }
  b.writeln('Sprachen: ${langs.entries.map((e) => '${e.key} ${e.value[0]} (${(e.value[1] * 100 / e.value[0]).round()} % schlecht)').join(', ')}\n');

  // the latest bad answers to read first
  final latest = rows.where((r) => r['rating'] != 'up').toList()
    ..sort((a, c) => '${c['at']}'.compareTo('${a['at']}'));
  if (latest.isNotEmpty) {
    b.writeln('Zuletzt schlecht bewertet:');
    for (final r in latest.take(5)) {
      final why = '${r['reason'] ?? ''}'.isEmpty ? '' : ' (${r['reason']})';
      b.writeln('- „${r['question']}“$why');
    }
  }
  return b.toString();
}
