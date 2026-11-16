// What Buddy and the person talked about before: one short line per answered
// question, with the next step Buddy gave. It stays on the device, goes to
// Buddy as context, and lets him pick up where you left off ("Last week you
// wanted to cancel the gym. Did it work?") even after "New chat".
import 'package:hive/hive.dart';

class BuddyJournal {
  static const _key = 'buddyJournal';
  static const keepDays = 60;
  static const maxKept = 30;

  static Box? get _box => Hive.isBoxOpen('settings') ? Hive.box('settings') : null;

  static List<Map<String, dynamic>> _all() =>
      [for (final e in (_box?.get(_key) as List? ?? const [])) (e as Map).cast<String, dynamic>()];

  static String _short(String s, int n) {
    final t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t.length <= n ? t : '${t.substring(0, n - 1)}…';
  }

  // the "Next step:" line of an answer, without markdown
  static String? stepOf(String answer) {
    final m = RegExp(r'^\**(?:Nächster Schritt|Next step):\**\s*(.+)$', multiLine: true).firstMatch(answer);
    return m == null ? null : _short(m.group(1)!.replaceAll('**', ''), 160);
  }

  static Future<void> add(String question, String answer, {DateTime? now}) async {
    final box = _box;
    if (box == null || question.trim().isEmpty) return;
    final at = now ?? DateTime.now();
    final list = _all();
    final step = stepOf(answer);
    list.insert(0, {
      'am': at.toIso8601String().substring(0, 10),
      'frage': _short(question, 140),
      if (step != null) 'schritt': step,
    });
    await box.put(_key, list.take(maxKept).toList());
  }

  // for Buddy: earlier conversations, newest first, without what is on screen now
  static List<Map<String, dynamic>> forAgent({Iterable<String> current = const [], DateTime? now}) {
    final today = now ?? DateTime.now();
    final here = {for (final q in current) _short(q, 140)};
    return [
      for (final e in _all())
        if (!here.contains(e['frage']) &&
            today.difference(DateTime.tryParse('${e['am']}') ?? today).inDays <= keepDays)
          e
    ].take(8).toList();
  }

  static Future<void> clear() async => _box?.delete(_key);
}
