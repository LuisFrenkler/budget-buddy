// "Lade 3 Freunde ein": each friend who joins through your link moves you up
// the waitlist or, in the app, adds a few free Buddy questions. The server
// counts; the app keeps the last known numbers for the profile and the quota.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;

import 'account_service.dart';
import 'backend_service.dart';

class InviteInfo {
  final String code;
  final String link;
  final int friends;
  final int rewarded;
  final int bonusPerFriend;
  final int bonusQuestions;
  const InviteInfo(this.code, this.link, this.friends, this.rewarded, this.bonusPerFriend, this.bonusQuestions);

  int get open => (rewarded - friends).clamp(0, rewarded);

  static InviteInfo fromJson(Map j) => InviteInfo(
        '${j['code'] ?? ''}',
        '${j['link'] ?? ''}',
        (j['friends'] as num?)?.toInt() ?? 0,
        (j['rewarded'] as num?)?.toInt() ?? 3,
        (j['bonusPerFriend'] as num?)?.toInt() ?? 5,
        (j['bonusQuestions'] as num?)?.toInt() ?? 0,
      );

  String shareText(String? name) =>
      'Ich nutze Ahead, einen Finanz-Buddy, der mit deinen echten Zahlen rechnet und sagt, was du als Nächstes tun kannst. '
      '${name != null && name.isNotEmpty ? 'Hier ist meine Einladung: ' : 'Einladung: '}$link';
}

class InviteService {
  static const bonusKey = 'inviteBonus';
  // the code that brought this person here (?ref=CODE), sent with sign-up
  static const refKey = 'inviteRef';

  static final info = ValueNotifier<InviteInfo?>(null);

  static Box? get _box => Hive.isBoxOpen('settings') ? Hive.box('settings') : null;

  static String? get pendingRef => _box?.get(refKey) as String?;

  static Future<void> rememberRef(String? code) async {
    final c = code?.trim().toUpperCase() ?? '';
    if (RegExp(r'^[A-Z0-9]{6}$').hasMatch(c)) await _box?.put(refKey, c);
  }

  static Future<void> clearRef() async => _box?.delete(refKey);

  static Future<InviteInfo?> refresh() async {
    if (AccountService.current.value == null) return null;
    try {
      final res = await http
          .get(Uri.parse('${BackendService.base}/invite'), headers: BackendService.authHeaders)
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return info.value;
      final i = InviteInfo.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map);
      info.value = i;
      await _box?.put(bonusKey, i.bonusQuestions);
      return i;
    } catch (_) {
      return info.value;
    }
  }
}
