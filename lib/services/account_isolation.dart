// Keeps one account's money, bank links and vault off another account on the
// same device. Finance apps must never show the previous user's connections.
import 'package:hive/hive.dart';
import 'db.dart';
import 'plus_service.dart';
import 'settings_service.dart';

class AccountIsolation {
  static Box get _box => Hive.box('settings');

  // keys that belong to one signed-in identity (not theme / app lock)
  static const financeSettingKeys = [
    'vaultOwner', 'vaultVersion', 'vaultDirty',
    'demoKeys', 'demoOpeningBefore',
    'categoryRules', 'budgetsStopped', 'cancellations', 'contractsHidden',
    'balanceSet', 'openingBalanceCents',
    'moneyAccounts', 'mainAccount',
    'plusSub', 'plusStore',
    'usage_aiQuestion', 'usage_receiptScan', 'usage_goal',
  ];

  /// Whether local finance may stay when [accountId] signs in or registers.
  static bool mayKeepLocal({
    required String accountId,
    required String vaultOwner,
    required String bankOwner,
    required String depotOwner,
    required bool hasBankOrDepotLinks,
    required bool hasFinanceData,
    required bool wasGuest,
  }) {
    final owner = _owner(vaultOwner: vaultOwner, bankOwner: bankOwner, depotOwner: depotOwner);
    if (owner == accountId) return true;
    if (owner != null) return false; // another account's data
    // no known owner: orphaned bank/depot tokens must never attach to anyone
    if (hasBankOrDepotLinks) return false;
    if (!hasFinanceData) return true;
    // only a guest upgrading may keep unowned bookings they just typed
    return wasGuest;
  }

  static String? _owner({
    required String vaultOwner,
    required String bankOwner,
    required String depotOwner,
  }) {
    if (vaultOwner.isNotEmpty) return vaultOwner;
    if (bankOwner.isNotEmpty) return bankOwner;
    if (depotOwner.isNotEmpty) return depotOwner;
    return null;
  }

  static bool get hasBankOrDepotLinks =>
      Settings.bankState.isNotEmpty ||
      Settings.depotState.isNotEmpty ||
      Settings.extraBanks.isNotEmpty ||
      Settings.extraDepots.isNotEmpty;

  static bool get hasFinanceData =>
      DB.getTx().isNotEmpty ||
      DB.getHoldings().isNotEmpty ||
      DB.getBudgets().isNotEmpty ||
      (Hive.isBoxOpen('goals') && Hive.box('goals').isNotEmpty) ||
      (Hive.isBoxOpen('splits') && Hive.box('splits').isNotEmpty);

  /// Wipe every booking, holding, bank/depot link and vault marker on device.
  static Future<void> wipeLocalFinance() async {
    await DB.clearAll();
    await Settings.clearDepot();
    for (final k in financeSettingKeys) {
      await _box.delete(k);
    }
    for (final k in _box.keys.whereType<String>().where((k) => k.startsWith('usage_'))) {
      await _box.delete(k);
    }
    PlusService.load();
  }

  /// After a keep-or-wipe decision: claim remaining links for this account.
  static Future<void> claimLocalFor(String accountId) async {
    await _box.put('vaultOwner', accountId);
    if (Settings.bankState.isNotEmpty || Settings.extraBanks.isNotEmpty) {
      await Settings.setBankOwner(accountId);
    }
    if (Settings.depotState.isNotEmpty || Settings.extraDepots.isNotEmpty) {
      await Settings.setDepotOwner(accountId);
    }
  }
}
