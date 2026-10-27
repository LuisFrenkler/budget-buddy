// Brings the positions of a linked depot (Trade Republic and others through
// Parqet Connect) into the app.
//
// - Every position gets the stable id "depot_<ISIN or symbol>", so syncing
//   again updates shares and prices instead of adding a copy.
// - A position that is gone from the depot (sold) is removed. Positions the
//   user added by hand or imported are never touched.
import '../models/holding.dart';
import 'backend_service.dart';
import 'db.dart';
import 'settings_service.dart';

class DepotSyncResult {
  final List<Holding> keep; // the synced positions after this sync
  final List<String> remove; // ids of synced positions that were sold
  final int added; // positions new in the app
  const DepotSyncResult(this.keep, this.remove, this.added);
}

class DepotSync {
  static const prefix = 'depot_';

  // pure merge step, separate from storage so it can be tested
  static DepotSyncResult merge({required List<Holding> existing, required List<DepotPosition> incoming}) {
    final before = {for (final h in existing.where((h) => h.id.startsWith(prefix))) h.id};
    final keep = [
      for (final p in incoming)
        if (p.shares > 0)
          Holding(
            id: '$prefix${p.id}',
            name: p.name,
            symbol: p.symbol,
            type: p.type,
            shares: p.shares,
            buyPriceCents: p.buyPriceCents,
            currentPriceCents: p.priceCents,
            depot: p.depot.isNotEmpty ? p.depot : (p.broker.isNotEmpty ? p.broker : null),
          ),
    ];
    final ids = {for (final h in keep) h.id};
    return DepotSyncResult(
      keep,
      [for (final id in before) if (!ids.contains(id)) id],
      ids.where((id) => !before.contains(id)).length,
    );
  }

  // syncs the linked depot now; returns the number of positions
  static Future<int> run() async {
    final data = await BackendService.depotSync(Settings.depotState);
    final positions = data.positions;
    await Settings.setDepotHistory(data.history);
    final result = merge(existing: DB.getHoldings(), incoming: positions);
    for (final h in result.keep) {
      await DB.addHolding(h);
    }
    for (final id in result.remove) {
      await DB.deleteHolding(id);
    }
    final brokers = {for (final p in positions) if (p.broker.isNotEmpty) p.broker};
    await Settings.setDepot(Settings.depotState, broker: brokers.join(', '));
    await Settings.setDepotSync(DateTime.now());
    return result.keep.length;
  }

  // syncs quietly when linked and the last sync is older than [maxAge], or
  // when the depot's value history is still missing (no chart without it)
  static Future<void> refreshIfStale({Duration maxAge = const Duration(hours: 4)}) async {
    if (Settings.depotState.isEmpty) return;
    final last = Settings.depotSync;
    final complete = Settings.depotHistory.isNotEmpty;
    if (complete && last != null && DateTime.now().difference(last) < maxAge) return;
    try {
      await run();
    } catch (_) {
      // offline or server not running: try again next start
    }
  }
}
