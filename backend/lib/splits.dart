// Shared groups for splitting expenses, so everyone in a flat share sees the
// same balance. A group is uploaded once by its creator and joined by others
// with a short invite code. Changes arrive as single operations (add an
// expense, remove one, record a payment) and are applied here in order, so
// two people adding at the same time never overwrite each other.
import 'dart:async';
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
  // one mutation at a time per group (and for the whole store on share/create)
  final _locks = <String, Future<void>>{};

  SharedSplits(this._store);

  Future<T> _withLock<T>(String key, Future<T> Function() fn) async {
    final previous = _locks[key] ?? Future<void>.value();
    final gate = Completer<void>();
    _locks[key] = gate.future;
    await previous.catchError((_) {});
    try {
      return await fn();
    } finally {
      gate.complete();
      if (identical(_locks[key], gate.future)) _locks.remove(key);
    }
  }

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
  Future<Map<String, dynamic>> share(String userId, Map<String, dynamic> group, int me) {
    _check(group);
    if (me < 0 || me >= (group['members'] as List).length) throw const AuthError(400, 'Unbekannte Person.');
    final id = '${group['id'] ?? ''}';
    if (id.isEmpty) throw const AuthError(400, 'Gruppe ohne ID.');
    return _withLock(id, () async {
      final existing = _groups[id];
      if (existing != null) {
        if (!_participants(existing).containsKey(userId)) {
          throw const AuthError(409, 'Diese Gruppe gehört jemand anderem.');
        }
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
    });
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
    final id = '${p['id']}';
    return _withLock(id, () async {
      final e = _entry(id);
      final parts = _participants(e);
      if (parts.containsKey(userId)) return _view(e, userId);
      if (member < 0 || member >= (p['members'] as List).length) throw const AuthError(400, 'Unbekannte Person.');
      if (parts.values.contains(member)) throw const AuthError(409, 'Diese Person ist schon vergeben.');
      (e['participants'] as Map)[userId] = member;
      await _save();
      return _view(e, userId);
    });
  }

  Map<String, dynamic> get(String userId, String id) => _view(_member(userId, id), userId);

  // applies one change and returns the new state
  Future<Map<String, dynamic>> apply(String userId, String id, Map<String, dynamic> op) => _withLock(id, () async {
    final e = _member(userId, id);
    final g = e['group'] as Map;
    final members = (g['members'] as List).length;
    final expenses = (g['expenses'] as List?) ?? [];
    final settlements = (g['settlements'] as List?) ?? [];
    switch (op['type']) {
      case 'addExpense':
      case 'updateExpense':
        final x = (op['expense'] as Map).cast<String, dynamic>();
        final paidBy = (x['paidBy'] as num).toInt();
        final shares = (x['shares'] as Map).map((k, v) => MapEntry(int.parse('$k'), (v as num).toInt()));
        final cents = (x['cents'] as num).toInt();
        if (paidBy < 0 || paidBy >= members || shares.keys.any((k) => k < 0 || k >= members)) {
          throw const AuthError(400, 'Ungültige Person in der Ausgabe.');
        }
        if (cents <= 0 || shares.values.any((v) => v < 0) || shares.values.fold<int>(0, (s, v) => s + v) != cents) {
          throw const AuthError(400, 'Die Anteile ergeben nicht den Betrag.');
        }
        final xid = '${x['id']}';
        final existing = expenses.indexWhere((y) => y['id'] == xid);
        if (op['type'] == 'updateExpense') {
          if (existing < 0) throw const AuthError(404, 'Diese Ausgabe gibt es nicht mehr.');
          expenses[existing] = x;
        } else if (existing < 0) {
          expenses.add(x);
        }
      case 'removeExpense':
        expenses.removeWhere((y) => y['id'] == op['id']);
      // someone joins the flat later; members keep their places, so old
      // expenses still point at the right person
      case 'addMember':
        final name = '${op['name'] ?? ''}'.trim();
        if (name.isEmpty || name.length > 40) throw const AuthError(400, 'Ungültiger Name.');
        if (members >= 20) throw const AuthError(400, 'Eine Gruppe hat höchstens 20 Personen.');
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
        final cents = (s['cents'] as num).toInt();
        if (from < 0 || from >= members || to < 0 || to >= members || cents <= 0) {
          throw const AuthError(400, 'Ungültiger Ausgleich.');
        }
        // idempotent: same id, or same from/to/cents within ~2 minutes = already booked
        DateTime? parseDate(Object? raw) {
          if (raw is num) return DateTime.fromMillisecondsSinceEpoch(raw.toInt());
          return DateTime.tryParse('$raw');
        }
        final sid = '${s['id'] ?? ''}';
        final when = parseDate(s['date']);
        final dup = settlements.any((x) {
          if (sid.isNotEmpty && '${x['id'] ?? ''}' == sid) return true;
          if ((x['from'] as num?)?.toInt() != from || (x['to'] as num?)?.toInt() != to) return false;
          if ((x['cents'] as num?)?.toInt() != cents) return false;
          final xd = parseDate(x['date']);
          if (when == null || xd == null) return false;
          return when.difference(xd).abs() < const Duration(minutes: 2);
        });
        if (!dup) settlements.add(s);
      default:
        throw const AuthError(400, 'Unbekannte Änderung.');
    }
    g['expenses'] = expenses;
    g['settlements'] = settlements;
    e['version'] = ((e['version'] as num?) ?? 0).toInt() + 1;
    await _save();
    return _view(e, userId);
  });

  // the owner deletes the group for everyone; others just leave
  Future<void> leave(String userId, String id) => _withLock(id, () async {
    final e = _member(userId, id);
    if (e['owner'] == userId) {
      _groups.remove(id);
    } else {
      (e['participants'] as Map).remove(userId);
    }
    await _save();
  });

  // when an account is deleted
  Future<void> forget(String userId) => _withLock('_all', () async {
    _groups.removeWhere((_, e) => e['owner'] == userId);
    for (final e in _groups.values) {
      (e['participants'] as Map).remove(userId);
    }
    await _save();
  });
}
