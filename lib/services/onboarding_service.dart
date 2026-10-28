// "Erste Schritte": the few things that make BudgetBuddy useful from day one.
// Every step ticks itself off when it is done, wherever the user did it.
import '../models/money_account.dart';
import 'money_accounts.dart';
import 'package:hive/hive.dart';
import 'db.dart';
import 'settings_service.dart';

// booking → balance → first budget (habit after trust)
enum OnboardingStep { booking, balance, budget }

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
      };

  static int get doneCount => OnboardingStep.values.where(done).length;

  static bool get complete => doneCount == OnboardingStep.values.length;

  // sets the starting balance so that the app shows [cents] as today's balance
  static Future<void> setCurrentBalance(int cents, {MoneyAccount? account}) async {
    await MoneyAccounts.setBalance(account ?? MoneyAccounts.main, cents, DB.getTx());
    await markBalanceSet();
  }
}
