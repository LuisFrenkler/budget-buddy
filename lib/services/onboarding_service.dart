// "Erste Schritte": the few things that make BudgetBuddy useful from day one.
// Every step ticks itself off when it is done, wherever the user did it.
import 'package:hive/hive.dart';
import 'db.dart';
import 'goals_service.dart';
import 'notification_service.dart';
import 'settings_service.dart';

enum OnboardingStep { booking, balance, budget, goal, notifications }

class OnboardingService {
  static Box get _box => Hive.box('settings');

  // hidden by the user, or someone who already uses the app a lot
  static bool get hidden =>
      (_box.get('onboardingHidden', defaultValue: false) as bool) || DB.getTx().length >= 30;

  static Future<void> hide() => _box.put('onboardingHidden', true);

  // the real balance was entered by hand or comes from the bank
  static bool get balanceKnown =>
      Settings.bankState.isNotEmpty ||
      Settings.openingBalanceCents != 0 ||
      (_box.get('balanceSet', defaultValue: false) as bool);

  static Future<void> markBalanceSet() => _box.put('balanceSet', true);

  static bool done(OnboardingStep s) => switch (s) {
        OnboardingStep.booking => DB.getTx().isNotEmpty,
        OnboardingStep.balance => balanceKnown,
        OnboardingStep.budget => DB.getBudgets().isNotEmpty,
        OnboardingStep.goal => GoalsService.all().isNotEmpty,
        OnboardingStep.notifications => NotificationService.enabled.value,
      };

  static int get doneCount => OnboardingStep.values.where(done).length;

  static bool get complete => doneCount == OnboardingStep.values.length;

  // sets the starting balance so that the app shows [cents] as today's balance
  static Future<void> setCurrentBalance(int cents) async {
    var sum = 0;
    for (final t in DB.getTx()) {
      sum += t.isIncome ? t.amountCents : -t.amountCents;
    }
    await Settings.setOpeningBalanceCents(cents - sum);
    await markBalanceSet();
  }
}
