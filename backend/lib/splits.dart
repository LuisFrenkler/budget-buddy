// Shared groups for splitting expenses, so everyone in a flat share sees the
// same balance. A group is uploaded once by its creator and joined by others
// with a short invite code. Changes arrive as single operations (add an
// expense, remove one, record a payment) and are applied here in order, so
// two people adding at the same time never overwrite each other.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'accounts.dart';
import 'json_store.dart';

class SharedSplits {
  // no 0/O or 1/I/L: codes are read aloud and typed by hand
  static const _alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

  final File _store;
  final _groups = <String, Map<String, dynamic>>{}; // id -> {group, code, participants, version}

  SharedSplits(this._store);

  Future<void> load() async {
    if (!await _store.exists()) return;
    final map = jsonDecode(await _store.readAsString()) as Map<String, dynamic>;
    map.forEach((k, v) => _groups[k] = (v as Map).cast<String, dynamic>());
  }

  Future<void> _save() => writeJsonAtomic(_store, _groups);

  String _newCode() {
    final rnd = math.Random.secure();
    while (true) {
      final code = List.generate(6, (_) => _alphabet[rnd.nextInt(_alphabet.length)]).join();
      if (!_groups.values.any((g) => g['code'] == code)) return code;
    }
  }

  Map<String, dynamic> _entry(String id) {
    final e = _groups[id];
    if (e == null) throw const AuthError(404, 'Diese Gruppe gibt es nicht mehr.');
    return e;
  }

  Map<String, int> _participants(Map<String, dynamic> e) =>
      (e['participants'] as Map).map((k, v) => MapEntry('$k', (v as num).toInt()));

  // what a participant gets back: the group, its code, who is taken and their own place
  Map<String, dynamic> _view(Map<String, dynamic> e, String userId) => {
        'group': e['group'],
        'code': e['code'],
        'version': e['version'],
        'me': _participants(e)[userId],
        'taken': _participants(e).values.toList(),
      };

  Map<String, dynamic> _member(String userId, String id) {
    final e = _entry(id);
    if (!_participants(e).containsKey(userId)) throw const AuthError(403, 'Du bist nicht in dieser Gruppe.');
    return e;
  }

  static void _check(Map group) {
    final members = group['members'];
    if (members is! List || members.length < 2 || members.length > 20) {
      throw const AuthError(400, 'Eine Gruppe braucht 2 bis 20 Personen.');
    }
  }

  // uploads a group; the creator is the member at [me]
  Future<Map<String, dynamic>> share(String userId, Map<String, dynamic> group, int me) async {
    _check(group);
    final id = '${group['id'] ?? ''}';
    if (id.isEmpty) throw const AuthError(400, 'Gruppe ohne ID.');
    final existing = _groups[id];
    if (existing != null) {
      if (!_participants(existing).containsKey(userId)) throw const AuthError(409, 'Diese Gruppe gehört jemand anderem.');
      return _view(existing, userId);
    }
    _groups[id] = {
      'group': group,
      'code': _newCode(),
      'participants': {userId: me},
      'owner': userId,
      'version': 1,
    };
    await _save();
    return _view(_groups[id]!, userId);
  }

  // what someone with the code sees before choosing who they are
  Map<String, dynamic> preview(String code) {
    final clean = code.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    for (final e in _groups.values) {
      if (e['code'] == clean) {
        final g = e['group'] as Map;
        return {
          'id': g['id'],
          'name': g['name'],
          'emoji': g['emoji'],
          'members': g['members'],
          'taken': _participants(e).values.toList(),
        };
      }
    }
    throw const AuthError(404, 'Diesen Code gibt es nicht. Prüf ihn noch einmal.');
  }

  Future<Map<String, dynamic>> join(String userId, String code, int member) async {
    final p = preview(code);
    final e = _entry('${p['id']}');
    final parts = _participants(e);
    if (parts.containsKey(userId)) return _view(e, userId);
    if (member < 0 || member >= (p['members'] as List).length) throw const AuthError(400, 'Unbekannte Person.');
    if (parts.values.contains(member)) throw const AuthError(409, 'Diese Person ist schon vergeben.');
    (e['participants'] as Map)[userId] = member;
    await _save();
    return _view(e, userId);
  }

  Map<String, dynamic> get(String userId, String id) => _view(_member(userId, id), userId);

  // applies one change and returns the new state
  Future<Map<String, dynamic>> apply(String userId, String id, Map<String, dynamic> op) async {
    final e = _member(userId, id);
    final g = e['group'] as Map;
    final members = (g['members'] as List).length;
    final expenses = (g['expenses'] as List?) ?? [];
    final settlements = (g['settlements'] as List?) ?? [];
    switch (op['type']) {
      case 'addExpense':
        final x = (op['expense'] as Map).cast<String, dynamic>();
        final paidBy = (x['paidBy'] as num).toInt();
        final shares = (x['shares'] as Map).map((k, v) => MapEntry(int.parse('$k'), (v as num).toInt()));
        final cents = (x['cents'] as num).toInt();
        if (paidBy < 0 || paidBy >= members || shares.keys.any((k) => k < 0 || k >= members)) {
          throw const AuthError(400, 'Ungültige Person in der Ausgabe.');
        }
        if (cents <= 0 || shares.values.fold<int>(0, (s, v) => s + v) != cents) {
          throw const AuthError(400, 'Die Anteile ergeben nicht den Betrag.');
        }
        if (!expenses.any((y) => y['id'] == x['id'])) expenses.add(x);
      case 'removeExpense':
        expenses.removeWhere((y) => y['id'] == op['id']);
      // someone joins the flat later; members keep their places, so old
      // expenses still point at the right person
      case 'addMember':
        final name = '${op['name'] ?? ''}'.trim();
        if (name.isEmpty || name.length > 40) throw const AuthError(400, 'Ungültiger Name.');
        (g['members'] as List).add(name);
      case 'renameMember':
        final i = (op['index'] as num?)?.toInt() ?? -1;
        final name = '${op['name'] ?? ''}'.trim();
        if (i < 0 || i >= members || name.isEmpty || name.length > 40) {
          throw const AuthError(400, 'Ungültiger Name.');
        }
        (g['members'] as List)[i] = name;
      case 'settle':
        final s = (op['settlement'] as Map).cast<String, dynamic>();
        final from = (s['from'] as num).toInt(), to = (s['to'] as num).toInt();
        if (from < 0 || from >= members || to < 0 || to >= members || (s['cents'] as num) <= 0) {
          throw const AuthError(400, 'Ungültiger Ausgleich.');
        }
        settlements.add(s);
      default:
        throw const AuthError(400, 'Unbekannte Änderung.');
    }
    g['expenses'] = expenses;
    g['settlements'] = settlements;
    e['version'] = ((e['version'] as num?) ?? 0).toInt() + 1;
    await _save();
    return _view(e, userId);
  }

  // the owner deletes the group for everyone; others just leave
  Future<void> leave(String userId, String id) async {
    final e = _member(userId, id);
    if (e['owner'] == userId) {
      _groups.remove(id);
    } else {
      (e['participants'] as Map).remove(userId);
    }
    await _save();
  }

  // when an account is deleted
  Future<void> forget(String userId) async {
    _groups.removeWhere((_, e) => e['owner'] == userId);
    for (final e in _groups.values) {
      (e['participants'] as Map).remove(userId);
    }
    await _save();
  }
}
