// Life stage steps tick themselves off when the app sees them done: a checked
// payslip, an emergency fund goal, a monthly savings amount, the tax profile,
// the pension estimate, a shared group. The person can still untick anything.
import 'dart:async';

import 'package:hive/hive.dart';

import 'goals_service.dart';
import 'life_stages.dart';
import 'split_service.dart';
import 'tax_estimate.dart';
import 'vorsorge.dart';

class LifeProgress {
  static Box? get _box => Hive.isBoxOpen('settings') ? Hive.box('settings') : null;

  // a payslip went through Buddy's check without anything to look at
  static Future<void> payslipChecked() async => _box?.put('payslipChecked', true);

  // which step ids are done, from what the app knows
  static Set<String> seen() {
    final out = <String>{};
    if (_box?.get('payslipChecked') == true) out.add('gehalt');
    try {
      final goals = GoalsService.all();
      if (goals.any((g) => RegExp(r'notgroschen|notfall|puffer|reserve|emergency', caseSensitive: false).hasMatch(g.name))) {
        out.add('notgroschen');
      }
      if (goals.any((g) => g.monthlyCents > 0)) out.add('sparrate');
    } catch (_) {}
    if (TaxEstimate.profile().grossMonth > 0) out.add('steuer');
    try {
      if (Vorsorge.load().statutoryCents > 0) out.add('luecke');
    } catch (_) {}
    try {
      if (Hive.isBoxOpen('splits') && SplitService.all().isNotEmpty) out.add('teilen');
    } catch (_) {}
    return out;
  }

  // ticks what is seen and not yet done (once: an untick by hand stays)
  static Future<List<String>> sync() async {
    final box = _box;
    if (box == null) return const [];
    final ticked = ((box.get('lifeAutoTicked') as List?) ?? const []).cast<String>().toSet();
    final now = seen();
    final fresh = <String>[];
    for (final stage in LifeStages.all) {
      for (final step in stage.steps) {
        final key = '${stage.id}/${step.id}';
        if (now.contains(step.id) && !ticked.contains(key) && !LifeStages.isDone(stage, step)) {
          unawaited(LifeStages.setDone(stage, step, true));
          ticked.add(key);
          fresh.add(step.title);
        }
      }
    }
    if (fresh.isNotEmpty) unawaited(box.put('lifeAutoTicked', ticked.toList()));
    return fresh;
  }
}
