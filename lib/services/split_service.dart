// Groups for shared spending, kept in the 'splits' Hive box.
import 'package:hive/hive.dart';
import '../models/split.dart';
import 'account_service.dart';

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
  static int myTotal() => all().fold(0, (s, g) => s + SplitMath.balances(g)[g.me]);

  // --- shared through the server ---

  // the server's state, keeping who the user is on this device
  static Future<SplitGroup> _store(Map<String, dynamic> view) async {
    final g = SplitGroup.fromMap(view['group'] as Map)
      ..me = (view['me'] as num? ?? 0).toInt()
      ..code = view['code'] as String?
      ..version = (view['version'] as num? ?? 0).toInt();
    await save(g);
    return g;
  }

  // uploads the group; the user's name replaces "Ich" so others know who it is
  static Future<SplitGroup> share(SplitGroup g, String myName) async {
    if (g.members[g.me] == 'Ich' && myName.trim().isNotEmpty) g.members[g.me] = myName.trim();
    return _store(await AccountService.api('/splits/share', body: {'group': g.toShared(), 'me': g.me}));
  }

  static Future<Map<String, dynamic>> preview(String code) =>
      AccountService.api('/splits/preview?code=${Uri.encodeQueryComponent(code)}');

  static Future<SplitGroup> join(String code, int member) async =>
      _store(await AccountService.api('/splits/join', body: {'code': code, 'member': member}));

  // newest state from the server; local groups stay as they are
  static Future<SplitGroup> refresh(SplitGroup g) async {
    if (!g.shared) return g;
    return _store(await AccountService.api('/splits/get?id=${Uri.encodeQueryComponent(g.id)}'));
  }

  // every change goes through here: on the server for shared groups, else local
  static Future<SplitGroup> _change(SplitGroup g, Map<String, dynamic> op, void Function() local) async {
    if (g.shared) return _store(await AccountService.api('/splits/op', body: {'id': g.id, 'op': op}));
    local();
    await save(g);
    return g;
  }

  static Future<SplitGroup> addExpense(SplitGroup g, SplitExpense e) =>
      _change(g, {'type': 'addExpense', 'expense': e.toMap()}, () => g.expenses.add(e));

  static Future<SplitGroup> removeExpense(SplitGroup g, String id) =>
      _change(g, {'type': 'removeExpense', 'id': id}, () => g.expenses.removeWhere((x) => x.id == id));

  static Future<SplitGroup> settle(SplitGroup g, Settlement s) =>
      _change(g, {'type': 'settle', 'settlement': s.toMap()}, () => g.settlements.add(s));

  // shared: the creator deletes it for all, others leave; local: just delete
  static Future<void> remove(SplitGroup g) async {
    if (g.shared) {
      try {
        await AccountService.api('/splits/leave', body: {'id': g.id});
      } catch (_) {}
    }
    await delete(g.id);
  }

  // a booking already shared in a group
  static bool isShared(String txId) =>
      all().any((g) => g.expenses.any((e) => e.txId == txId));
}
