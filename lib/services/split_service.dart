// Groups for shared spending, kept in the 'splits' Hive box.
import 'package:hive/hive.dart';
import '../models/split.dart';

class SplitService {
  static Box get _box => Hive.box('splits');

  static List<SplitGroup> all() {
    final list = <SplitGroup>[];
    for (final v in _box.values) {
      try {
        list.add(SplitGroup.fromMap(v as Map));
      } catch (_) {}
    }
    list.sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  static SplitGroup? byId(String id) {
    final raw = _box.get(id);
    return raw == null ? null : SplitGroup.fromMap(raw as Map);
  }

  static Future<void> save(SplitGroup g) => _box.put(g.id, g.toMap());
  static Future<void> delete(String id) => _box.delete(id);

  // the user's balance over all groups: positive = others owe the user
  static int myTotal() => all().fold(0, (s, g) => s + SplitMath.balances(g)[0]);

  // a booking already shared in a group
  static bool isShared(String txId) =>
      all().any((g) => g.expenses.any((e) => e.txId == txId));
}
