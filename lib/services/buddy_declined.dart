// What the person waved away: Buddy's cards they dismissed. Buddy sees the
// list and doesn't bring the same thing up again for a while, unless asked.
import 'package:hive/hive.dart';

class BuddyDeclined {
  static const _key = 'buddyDeclined';
  static const keepDays = 45;
  static const maxKept = 20;

  static Box get _box => Hive.box('settings');

  static List<Map<String, dynamic>> _all() =>
      [for (final e in (_box.get(_key) as List? ?? const [])) (e as Map).cast<String, dynamic>()];

  static Future<void> add(String kind, String what, {DateTime? now}) async {
    final at = now ?? DateTime.now();
    final list = _all()..removeWhere((e) => e['was'] == what);
    list.insert(0, {'art': kind, 'was': what, 'am': at.toIso8601String().substring(0, 10)});
    await _box.put(_key, list.take(maxKept).toList());
  }

  // for Buddy's context: the recent ones, newest first
  static List<Map<String, dynamic>> forAgent({DateTime? now}) {
    final today = now ?? DateTime.now();
    return [
      for (final e in _all())
        if (today.difference(DateTime.tryParse('${e['am']}') ?? today).inDays <= keepDays) e
    ].take(8).toList();
  }
}
