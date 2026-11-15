// Growth without ad money, the way chat-first products grew: a waitlist on the
// landing page where each friend you bring moves you up, invite codes for
// people who already use the app, and a few free questions to Buddy before
// anyone has to sign up.
//
// One code namespace for both: a code on the landing page (?ref=CODE) can
// belong to a waitlist entry or to an app user. Whoever owns it gets the credit.
import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;

import 'json_store.dart';

class GrowthError implements Exception {
  final int status;
  final String message;
  const GrowthError(this.status, this.message);
  @override
  String toString() => message;
}

class Growth {
  final File file;
  Growth(this.file);

  // each friend moves you this many places up the waitlist
  static const placesPerFriend = 5;
  // friends that count for the in-app reward
  static const rewardedFriends = 3;
  // extra free Buddy questions per counted friend
  static const bonusPerFriend = 5;

  // waitlist: code -> {code, email, seq, joinedAt, ref?}
  final _waitlist = <String, Map<String, dynamic>>{};
  // app users: code -> userId, and userId -> code
  final _userCodes = <String, String>{};
  final _codeOfUser = <String, String>{};
  // who brought whom: owner code -> list of codes / user ids that joined through it
  final _joined = <String, List<String>>{};
  var _seq = 0;

  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  static const _alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final _rand = math.Random.secure();

  Future<void> load() async {
    if (!await file.exists()) return;
    final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    for (final e in (data['waitlist'] as List? ?? const [])) {
      final m = (e as Map).cast<String, dynamic>();
      _waitlist[m['code'] as String] = m;
    }
    (data['userCodes'] as Map? ?? const {}).forEach((code, user) {
      _userCodes['$code'] = '$user';
      _codeOfUser['$user'] = '$code';
    });
    (data['joined'] as Map? ?? const {}).forEach((code, list) {
      _joined['$code'] = [for (final x in list as List) '$x'];
    });
    _seq = (data['seq'] as num?)?.toInt() ?? _waitlist.length;
  }

  Future<void> _save() => writeJsonAtomic(file, {
        'seq': _seq,
        'waitlist': _waitlist.values.toList(),
        'userCodes': _userCodes,
        'joined': _joined,
      });

  String _newCode() {
    while (true) {
      final c = List.generate(6, (_) => _alphabet[_rand.nextInt(_alphabet.length)]).join();
      if (!_waitlist.containsKey(c) && !_userCodes.containsKey(c)) return c;
    }
  }

  static String normalize(String code) => code.trim().toUpperCase();

  bool exists(String code) {
    final c = normalize(code);
    return _waitlist.containsKey(c) || _userCodes.containsKey(c);
  }

  int friendsOf(String code) => _joined[normalize(code)]?.length ?? 0;

  // lower is better: the order you joined, minus a few places per friend
  num _score(Map<String, dynamic> e) => (e['seq'] as num) - placesPerFriend * friendsOf(e['code'] as String);

  int positionOf(String code) {
    final me = _waitlist[normalize(code)];
    if (me == null) throw const GrowthError(404, 'Diesen Platz gibt es nicht.');
    final mine = _score(me);
    final myFriends = friendsOf(me['code'] as String);
    var ahead = 0;
    for (final e in _waitlist.values) {
      if (identical(e, me)) continue;
      final s = _score(e);
      if (s < mine) {
        ahead++;
      } else if (s == mine) {
        // a tie: whoever brought friends moved up to it, so goes first
        final f = friendsOf(e['code'] as String);
        if (f > myFriends || (f == myFriends && (e['seq'] as num) < (me['seq'] as num))) ahead++;
      }
    }
    return ahead + 1;
  }

  Map<String, dynamic> _public(Map<String, dynamic> e) => {
        'code': e['code'],
        'position': positionOf(e['code'] as String),
        'total': _waitlist.length,
        'friends': friendsOf(e['code'] as String),
        'placesPerFriend': placesPerFriend,
      };

  // the landing page: email in, a place and a personal link out. The same
  // email again gets its existing place back.
  // the first [n] people of the waitlist, best place first: who gets the test
  // version. Each with email, language, place and how many friends came.
  List<Map<String, dynamic>> front(int n) {
    final all = [
      for (final e in _waitlist.values)
        {
          'email': e['email'],
          'lang': e['lang'] ?? 'de',
          'position': positionOf(e['code'] as String),
          'friends': friendsOf(e['code'] as String),
          'code': e['code'],
        }
    ]..sort((a, b) => (a['position'] as int).compareTo(b['position'] as int));
    return all.take(n).toList();
  }

  Future<Map<String, dynamic>> join(String email, {String? ref, DateTime? now, String? lang}) async {
    final mail = email.trim().toLowerCase();
    if (mail.length > 200 || !_emailPattern.hasMatch(mail)) {
      throw const GrowthError(400, 'Bitte gib eine gültige E-Mail-Adresse ein.');
    }
    for (final e in _waitlist.values) {
      if (e['email'] == mail) return {..._public(e), 'already': true};
    }
    final code = _newCode();
    final entry = <String, dynamic>{
      'code': code,
      'email': mail,
      'seq': ++_seq,
      'joinedAt': (now ?? DateTime.now()).toIso8601String(),
      if (lang == 'en') 'lang': 'en',
    };
    final r = ref == null ? '' : normalize(ref);
    if (r.isNotEmpty && exists(r)) {
      entry['ref'] = r;
      (_joined[r] ??= []).add(code);
    }
    _waitlist[code] = entry;
    await _save();
    return {..._public(entry), 'already': false};
  }

  Map<String, dynamic> status(String code) {
    final e = _waitlist[normalize(code)];
    if (e == null) throw const GrowthError(404, 'Diesen Platz gibt es nicht.');
    return _public(e);
  }

  // the app user's own code, made on first use
  Future<String> codeFor(String userId) async {
    final have = _codeOfUser[userId];
    if (have != null) return have;
    final code = _newCode();
    _userCodes[code] = userId;
    _codeOfUser[userId] = code;
    await _save();
    return code;
  }

  // a new account that came with someone's code
  Future<void> credit(String ref, String newUserId) async {
    final r = normalize(ref);
    if (!exists(r) || _userCodes[r] == newUserId) return;
    final list = _joined[r] ??= [];
    if (list.contains(newUserId)) return;
    list.add(newUserId);
    await _save();
  }

  Map<String, dynamic> invites(String userId, String code, String link) {
    final friends = friendsOf(code);
    final counted = math.min(friends, rewardedFriends);
    return {
      'code': code,
      'link': link,
      'friends': friends,
      'rewarded': rewardedFriends,
      'bonusPerFriend': bonusPerFriend,
      'bonusQuestions': counted * bonusPerFriend,
    };
  }

  // an account is gone: its code stops crediting anyone
  Future<void> forgetUser(String userId) async {
    final code = _codeOfUser.remove(userId);
    if (code == null) return;
    _userCodes.remove(code);
    _joined.remove(code);
    await _save();
  }
}

// Buddy before sign-up: a few real answers per device and day, and a wider
// cap per address so a new device id does not open the tap.
class GuestQuota {
  final int perDevice;
  final int perIp;
  GuestQuota({this.perDevice = 3, this.perIp = 20});

  final _device = <String, ({String day, int count})>{};
  final _ip = <String, ({String day, int count})>{};

  static String _day(DateTime now) => now.toIso8601String().substring(0, 10);

  int _used(Map<String, ({String day, int count})> map, String key, String day) {
    final u = map[key];
    return u != null && u.day == day ? u.count : 0;
  }

  int left(String device, {DateTime? now}) => math.max(0, perDevice - _used(_device, device, _day(now ?? DateTime.now())));

  // counts one question, or throws when the device or the address is out
  void take(String device, String ip, {DateTime? now}) {
    if (device.length < 8 || device.length > 80) throw const GrowthError(400, 'Gerät unbekannt.');
    final day = _day(now ?? DateTime.now());
    final d = _used(_device, device, day);
    final i = _used(_ip, ip, day);
    if (d >= perDevice || i >= perIp) {
      throw const GrowthError(429,
          'Die Gratis-Fragen ohne Konto sind für heute aufgebraucht. Mit einem kostenlosen Konto geht es weiter.');
    }
    _device[device] = (day: day, count: d + 1);
    _ip[ip] = (day: day, count: i + 1);
    // yesterday's counters are not needed any more
    if (_device.length > 50000) _device.removeWhere((_, v) => v.day != day);
    if (_ip.length > 50000) _ip.removeWhere((_, v) => v.day != day);
  }
}
