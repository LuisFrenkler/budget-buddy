// What is still open between the person and Buddy: the "Nächster Schritt"
// of an answer, or a reminder they asked for. Buddy sees the open ones and
// picks them up again ("Hast du bei der Personalabteilung nachgefragt?"),
// the start screen shows the most recent, and a reminder with a date can
// become a notification. Kept small: at most 8 open, gone after 30 days.
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

class BuddyTask {
  final String id;
  final String text;
  final DateTime created;
  final DateTime? due;
  final bool done;
  const BuddyTask(this.id, this.text, this.created, {this.due, this.done = false});

  Map<String, dynamic> toMap() => {
        'id': id,
        'text': text,
        'created': created.toIso8601String(),
        if (due != null) 'due': due!.toIso8601String(),
        'done': done,
      };

  static BuddyTask? fromMap(dynamic m) {
    if (m is! Map) return null;
    final created = DateTime.tryParse('${m['created']}');
    if (created == null || '${m['text'] ?? ''}'.isEmpty) return null;
    return BuddyTask('${m['id']}', '${m['text']}', created,
        due: DateTime.tryParse('${m['due'] ?? ''}'), done: m['done'] == true);
  }
}

class BuddyTasks {
  static const _key = 'buddyTasks';
  static const maxOpen = 8;
  static const keepDays = 30;
  static final changed = ValueNotifier<int>(0);
  static int _seq = 0;

  static Box? get _box => Hive.isBoxOpen('settings') ? Hive.box('settings') : null;

  static List<BuddyTask> all({DateTime? now}) {
    final today = now ?? DateTime.now();
    final raw = (_box?.get(_key) as List?) ?? const [];
    return [
      for (final m in raw)
        if (BuddyTask.fromMap(m) case final t?)
          // a dated reminder stays until done; the rest fades after 30 days
          if (t.due != null || today.difference(t.created).inDays <= keepDays) t
    ];
  }

  static List<BuddyTask> open({DateTime? now}) =>
      [for (final t in all(now: now)) if (!t.done) t]..sort((a, b) => b.created.compareTo(a.created));

  static String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-zäöüß0-9]+'), ' ').trim();

  // the same step twice is one task
  static Future<String?> add(String text, {DateTime? due, DateTime? now}) async {
    final box = _box;
    final clean = text.replaceAll(RegExp(r'\*\*'), '').trim();
    if (box == null || clean.isEmpty) return null;
    final today = now ?? DateTime.now();
    final list = all(now: today);
    for (final t in list) {
      if (!t.done && _norm(t.text) == _norm(clean)) return t.id;
    }
    final task = BuddyTask('${DateTime.now().microsecondsSinceEpoch}-${_seq++}', clean.length > 160 ? clean.substring(0, 160) : clean,
        today,
        due: due);
    final openOnes = [task, ...list.where((t) => !t.done)];
    final kept = [...openOnes.take(maxOpen), ...list.where((t) => t.done).take(20)];
    await box.put(_key, [for (final t in kept) t.toMap()]);
    changed.value++;
    if (due != null) onDated?.call();
    return task.id;
  }

  // set by the app: plan notifications again when a dated reminder is added
  static void Function()? onDated;

  static Future<void> done(String id, {bool done = true}) async {
    final box = _box;
    if (box == null) return;
    await box.put(_key, [
      for (final t in all())
        (t.id == id ? BuddyTask(t.id, t.text, t.created, due: t.due, done: done) : t).toMap()
    ]);
    changed.value++;
  }

  static Future<void> remove(String id) async {
    final box = _box;
    if (box == null) return;
    await box.put(_key, [
      for (final t in all())
        if (t.id != id) t.toMap()
    ]);
    changed.value++;
  }

  static Future<void> doneByText(String text) async {
    for (final t in open()) {
      if (_norm(t.text) == _norm(text)) await done(t.id);
    }
  }

  // for Buddy: what is open and how long ago it came up
  static List<Map<String, dynamic>> forAgent({DateTime? now}) {
    final today = now ?? DateTime.now();
    return [
      for (final t in open(now: today).take(5))
        {
          'aufgabe': t.text,
          'vorTagen': today.difference(t.created).inDays,
          if (t.due != null) 'faellig': t.due!.toIso8601String().substring(0, 10),
        }
    ];
  }
}
