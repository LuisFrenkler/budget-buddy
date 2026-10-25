// BudgetBuddy Plus: who has it and how much of the free tier is used.
//
// Free: 5 AI questions and 3 receipt scans per month, 1 savings goal.
// Plus: everything without limits.
//
// Buying runs through the stores' in-app purchases. Until the store
// integration (e.g. RevenueCat) is connected, [activateTest] switches Plus
// on in a clearly labelled test mode without any payment.
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

enum PlusFeature { aiQuestion, receiptScan, goal }

class PlusService {
  static const freeAiQuestions = 5;
  static const freeReceiptScans = 3;
  static const freeGoals = 1;

  // monthly and yearly price as shown on the paywall
  static const monthlyPrice = '4,99 €';
  static const yearlyPrice = '39,99 €';
  static const yearlyPerMonth = '3,33 €';

  static Box get _box => Hive.box('settings');

  // a notifier so badges and limits update everywhere at once
  static final active = ValueNotifier<bool>(false);

  static void load() => active.value = _box.get('plusActive', defaultValue: false) as bool;

  static Future<void> activateTest() async {
    active.value = true;
    await _box.put('plusActive', true);
  }

  static Future<void> cancelTest() async {
    active.value = false;
    await _box.put('plusActive', false);
  }

  static String _monthKey(DateTime now) => '${now.year}-${now.month}';

  static String _counterKey(PlusFeature f) => 'usage_${f.name}';

  // how often a feature was used this month
  static int used(PlusFeature f, {DateTime? now}) {
    final raw = _box.get(_counterKey(f)) as Map?;
    if (raw == null || raw['month'] != _monthKey(now ?? DateTime.now())) return 0;
    return (raw['count'] as num).toInt();
  }

  static int limit(PlusFeature f) => switch (f) {
        PlusFeature.aiQuestion => freeAiQuestions,
        PlusFeature.receiptScan => freeReceiptScans,
        PlusFeature.goal => freeGoals,
      };

  // left in the free tier this month (goals: in total, counted by the caller)
  static int left(PlusFeature f, {DateTime? now}) => (limit(f) - used(f, now: now)).clamp(0, limit(f));

  static bool allowed(PlusFeature f, {int current = 0, DateTime? now}) {
    if (active.value) return true;
    if (f == PlusFeature.goal) return current < freeGoals;
    return used(f, now: now) < limit(f);
  }

  static Future<void> count(PlusFeature f, {DateTime? now}) async {
    if (active.value) return;
    final today = now ?? DateTime.now();
    await _box.put(_counterKey(f), {'month': _monthKey(today), 'count': used(f, now: today) + 1});
  }
}
