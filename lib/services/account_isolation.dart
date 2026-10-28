// Device cache model (like Trade Republic): the phone only holds the current
// session. Server owns the account's money, bank/depot consents and vault.
//
// - Logout / other account → wipe the local finance cache.
// - Login → empty cache, then load this account's vault from the server.
// - Register → empty cache, then optional StartChoice (demo / bank / empty).
// - Bank/depot tokens on device are a cache of server consents; unknown ones go.
import 'package:hive/hive.dart';
import 'backend_service.dart';
import 'bank_sync.dart';
import 'db.dart';
import 'depot_sync.dart';
import 'money_accounts.dart';
import 'plus_service.dart';
import 'settings_service.dart';

class AccountIsolation {
  static Box get _box => Hive.box('settings');

  // bumped on every wipe so in-flight bank/depot syncs abort before writing
  static int _epoch = 0;
  static int get epoch => _epoch;

  // keys that belong to one signed-in identity (not theme / app lock)
  static const financeSettingKeys = [
    'vaultOwner', 'vaultVersion', 'vaultDirty', 'vaultLoadFailed',
    'demoKeys', 'demoOpeningBefore',
    'categoryRules', 'budgetsStopped', 'cancellations', 'contractsHidden',
    'balanceSet', 'openingBalanceCents',
    'moneyAccounts', 'mainAccount',
    'plusSub', 'plusStore',
    'usage_aiQuestion', 'usage_receiptScan', 'usage_goal',
    'onboardingDone', 'onboardingHidden',
    'signedOutEmail',
    // dismissed bank booking ids must not block the next account's sync
    'bankDismissed',
    // AI consent belongs to the signed-in identity
    'aiConsent', 'aiConsentGoogle',
    // invite / news seen must not leak across accounts
    'pendingJoin', 'splitSeen',
    // wealth bridge + vorsorge + profile picture
    'wealthDebts', 'wealthPolicies', 'emergencyExtraCents', 'vorsorge', 'avatarBytes',
  ];

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

  static bool get isDemo => _box.get('demoKeys') != null;

  /// Wipe every booking, holding, bank/depot link and vault marker on device.
  static Future<void> wipeLocalFinance() async {
    _epoch++; // invalidate in-flight BankSync / DepotSync before clearing
    await DB.clearAll();
    await Settings.clearDepot();
    await Settings.clearBank();
    for (final k in financeSettingKeys) {
      await _box.delete(k);
    }
    for (final k in _box.keys.whereType<String>().where((k) => k.startsWith('usage_'))) {
      await _box.delete(k);
    }
    PlusService.load();
  }

  /// True while a bank/depot sync still belongs to this cache generation.
  static bool sameEpoch(int started) => _epoch == started;

  /// Stamp the (empty or just-restored) cache as belonging to [accountId].
  static Future<void> claimLocalFor(String accountId) async {
    await _box.put('vaultOwner', accountId);
    if (Settings.bankState.isNotEmpty || Settings.extraBanks.isNotEmpty) {
      await Settings.setBankOwner(accountId);
    } else {
      await Settings.clearBank();
      for (final t in DB.getTx().where((t) => t.id.startsWith(BankSync.prefix)).toList()) {
        await DB.deleteTx(t.id);
      }
    }
    if (Settings.depotState.isNotEmpty || Settings.extraDepots.isNotEmpty) {
      await Settings.setDepotOwner(accountId);
    } else {
      await Settings.clearDepot();
      // orphan sync rows must not outlive their link (other profile / failed wipe)
      for (final h in DB.getHoldings().toList()) {
        if (h.id.startsWith(DepotSync.prefix)) await DB.deleteHolding(h.id);
      }
    }
  }

  /// Drop bank/depot cache entries the server does not know for this session.
  /// All status checks run first so a mid-flight network error cannot leave a
  /// half-wiped primary with forgotten extras.
  static Future<void> reconcileLinksWithServer() async {
    try {
      final primaryBank = Settings.bankState;
      final primaryDepot = Settings.depotState;
      final extraBanks = Settings.extraBanks;
      final extraDepots = Settings.extraDepots;

      String? primaryBankStatus;
      if (primaryBank.isNotEmpty) {
        primaryBankStatus = (await BackendService.status(primaryBank)).status;
      }
      final bankStatuses = <String, String>{};
      for (final l in extraBanks) {
        bankStatuses[l.state] = (await BackendService.status(l.state)).status;
      }

      String? primaryDepotStatus;
      if (primaryDepot.isNotEmpty) {
        primaryDepotStatus = (await BackendService.depotStatus(primaryDepot)).status;
      }
      final depotStatuses = <String, String>{};
      for (final l in extraDepots) {
        depotStatuses[l.state] = (await BackendService.depotStatus(l.state)).status;
      }

      // --- apply bank ---
      if (primaryBank.isNotEmpty && primaryBankStatus != 'linked') {
        await _demoteOrStripPrimaryBank(extraBanks, bankStatuses);
      } else {
        final kept = [
          for (final l in extraBanks)
            if (bankStatuses[l.state] == 'linked') l,
        ];
        for (final l in extraBanks) {
          if (bankStatuses[l.state] != 'linked') {
            await deleteBankRowsForLink(l.state);
          }
        }
        if (kept.length != extraBanks.length) {
          await _box.put('bankLinks', [for (final l in kept) {'state': l.state, 'bank': l.bank}]);
        }
      }
      if (Settings.bankState.isEmpty && Settings.extraBanks.isEmpty) {
        await _stripAllBankData();
      }

      // --- apply depot ---
      if (primaryDepot.isNotEmpty && primaryDepotStatus != 'linked') {
        await _demoteOrStripPrimaryDepot(extraDepots, depotStatuses);
      } else {
        final kept = <({String state, String broker})>[];
        for (final l in extraDepots) {
          if (depotStatuses[l.state] == 'linked') {
            kept.add(l);
          } else {
            await _deleteSyncedHoldings(DepotSync.linkPrefix(l.state));
          }
        }
        if (kept.length != extraDepots.length) {
          await Settings.setExtraDepots(kept);
        }
      }

      if (Settings.depotState.isEmpty && Settings.extraDepots.isEmpty) {
        await _deletePrimaryDepotHoldings();
      }
    } catch (_) {
      // offline / mid-flight: leave cache untouched; next start retries
    }
  }

  /// Primary consent gone: promote first still-linked extra, else wipe primary only.
  static Future<void> _demoteOrStripPrimaryBank(
    List<({String state, String bank})> extras,
    Map<String, String> statuses,
  ) async {
    final survivors = [for (final l in extras) if (statuses[l.state] == 'linked') l];
    if (survivors.isEmpty) {
      await _stripAllBankData();
      return;
    }
    final oldPrimary = Settings.bankState;
    // drop the old primary's bookings before promoting — else they stay on main
    if (oldPrimary.isNotEmpty) await deleteBankRowsForLink(oldPrimary, includeMain: true);
    await _clearPrimaryBankKeysOnly();
    final first = survivors.first;
    await Settings.setBankState(first.state);
    await Settings.setBankInfo(name: first.bank);
    await _box.put('bankLinks', [
      for (final l in survivors.skip(1)) {'state': l.state, 'bank': l.bank},
    ]);
  }

  static Future<void> _demoteOrStripPrimaryDepot(
    List<({String state, String broker})> extras,
    Map<String, String> statuses,
  ) async {
    final survivors = [for (final l in extras) if (statuses[l.state] == 'linked') l];
    await _deletePrimaryDepotHoldings();
    await _clearPrimaryDepotKeysOnly();
    if (survivors.isEmpty) {
      await Settings.setExtraDepots([]);
      return;
    }
    final first = survivors.first;
    await Settings.setDepot(first.state, broker: first.broker);
    await Settings.setExtraDepots(survivors.skip(1).toList());
  }

  static Future<void> _stripAllBankData() async {
    for (final t in DB.getTx().where((t) => t.id.startsWith(BankSync.prefix)).toList()) {
      await DB.deleteTx(t.id);
    }
    await Settings.clearBank();
    await Settings.setOpeningBalanceCents(0);
  }

  /// Drop synced bookings/accounts that belonged only to this bank link.
  /// [includeMain]: also delete bank_* rows on the main account (primary giro).
  static Future<void> deleteBankRowsForLink(String state, {bool includeMain = false}) async {
    final legacyKey = '${BankSync.prefix}$state';
    // real sync uses bank_<accountUid> + MoneyAccount.link == state (not bank_<state>)
    final accountIds = <String>{
      legacyKey,
      for (final a in MoneyAccounts.others)
        if (a.link == state) a.id,
    };
    for (final t in DB.getTx().toList()) {
      final onLinked = t.accountId != null && accountIds.contains(t.accountId);
      final onMain = includeMain && t.accountId == null && t.id.startsWith(BankSync.prefix);
      final legacyId = t.id.startsWith(legacyKey);
      if (onLinked || onMain || legacyId) await DB.deleteTx(t.id);
    }
    await _box.put('moneyAccounts', [
      for (final a in MoneyAccounts.others)
        if (a.link != state && a.id != legacyKey) a.toMap(),
    ]);
  }

  static Future<void> _clearPrimaryBankKeysOnly() async {
    for (final k in [
      'bankState', 'bankOwner', 'bankName', 'bankIban', 'bankValidUntil',
      'bankBalanceCents', 'lastSync',
    ]) {
      await _box.delete(k);
    }
  }

  static Future<void> _clearPrimaryDepotKeysOnly() async {
    for (final k in ['depotState', 'depotBroker', 'depotSync', 'depotHistory', 'depotOwner']) {
      await _box.delete(k);
    }
  }

  /// First-link holdings use `depot_<isin>`; further links use `depot_x…`.
  static Future<void> _deletePrimaryDepotHoldings() async {
    for (final h in DB.getHoldings().toList()) {
      final id = h.id;
      if (id.startsWith(DepotSync.prefix) && !id.startsWith('${DepotSync.prefix}x')) {
        await DB.deleteHolding(id);
      }
    }
  }

  static Future<void> _deleteSyncedHoldings(String idPrefix) async {
    for (final h in DB.getHoldings().where((h) => h.id.startsWith(idPrefix)).toList()) {
      await DB.deleteHolding(h.id);
    }
  }
}
