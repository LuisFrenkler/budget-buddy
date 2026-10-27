// Brings the positions of a linked depot (Trade Republic and others through
// Parqet Connect) into the app.
//
// - Every position gets the stable id "depot_<ISIN or symbol>", so syncing
//   again updates shares and prices instead of adding a copy.
// - A position that is gone from the depot (sold) is removed. Positions the
//   user added by hand or imported are never touched.
// - A further depot link (another Parqet login) keeps its positions apart
//   under "depot_x<link>_", so each link only ever removes its own.
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
  static DepotSyncResult merge(
      {required List<Holding> existing, required List<DepotPosition> incoming, String link = ''}) {
    final own = linkPrefix(link);
    // the first link owns every "depot_" position except those of further links
    bool mine(String id) => link.isEmpty ? id.startsWith(prefix) && !id.startsWith('${prefix}x') : id.startsWith(own);
    final before = {for (final h in existing.where((h) => mine(h.id))) h.id};
    final keep = [
      for (final p in incoming)
        if (p.shares > 0)
          Holding(
            id: '$own${p.id}',
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

  // ids of a further link start with this; '' = the first link
  static String linkPrefix(String link) => link.isEmpty ? prefix : '${prefix}x${link.substring(0, link.length.clamp(0, 8))}_';

  // syncs every linked depot now; returns the number of positions
  static Future<int> run() async {
    var count = 0;
    final history = <DateTime, int>{};
    final links = [
      if (Settings.depotState.isNotEmpty) (state: Settings.depotState, key: ''),
      for (final l in Settings.extraDepots) (state: l.state, key: l.state),
    ];
    final extras = Settings.extraDepots;
    for (final l in links) {
      final data = await BackendService.depotSync(l.state);
      final positions = data.positions;
      // the value of all depots per day
      for (final (d, c) in data.history) {
        history[d] = (history[d] ?? 0) + c;
      }
      final result = merge(existing: DB.getHoldings(), incoming: positions, link: l.key);
      for (final h in result.keep) {
        await DB.addHolding(h);
      }
      for (final id in result.remove) {
        await DB.deleteHolding(id);
      }
      final brokers = {for (final p in positions) if (p.broker.isNotEmpty) p.broker}.join(', ');
      if (l.key.isEmpty) {
        await Settings.setDepot(Settings.depotState, broker: brokers);
      } else {
        await Settings.setExtraDepots(
            [for (final e in extras) e.state == l.state ? (state: e.state, broker: brokers) : e]);
      }
      count += result.keep.length;
    }
    await Settings.setDepotHistory((history.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))
        .map((e) => (e.key, e.value))
        .toList());
    await Settings.setDepotSync(DateTime.now());
    return count;
  }

  // syncs quietly when linked and the last sync is older than [maxAge], or
  // when the depot's value history is still missing (no chart without it)
  static Future<void> refreshIfStale({Duration maxAge = const Duration(hours: 4)}) async {
    if (Settings.depotState.isEmpty && Settings.extraDepots.isEmpty) return;
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
