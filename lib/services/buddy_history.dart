// The Buddy chat survives closing the app: the last messages stay on the
// device (not in the cloud backup) and go with logout or "Verlauf löschen".
//
// Before an account exists the guest chat is kept under its own key; the
// first time the person is signed in, Buddy picks up that conversation.
import 'package:hive/hive.dart';

class SavedMessage {
  final bool fromUser;
  final String text;
  final DateTime at;
  final bool offline;
  const SavedMessage(this.fromUser, this.text, this.at, {this.offline = false});

  Map<String, dynamic> toMap() => {'u': fromUser, 't': text, 'at': at.toIso8601String(), if (offline) 'off': true};

  static SavedMessage? fromMap(Object? m) {
    if (m is! Map) return null;
    final text = '${m['t'] ?? ''}';
    if (text.trim().isEmpty) return null;
    return SavedMessage(m['u'] == true, text, DateTime.tryParse('${m['at']}') ?? DateTime.now(), offline: m['off'] == true);
  }
}

class BuddyHistory {
  static const accountKey = 'buddyChat';
  static const guestKey = 'guestChat';
  static const max = 80;

  static Box? get _box => Hive.isBoxOpen('settings') ? Hive.box('settings') : null;

  static List<SavedMessage> load({bool guest = false}) {
    final raw = _box?.get(guest ? guestKey : accountKey);
    if (raw is! List) return const [];
    return raw.map(SavedMessage.fromMap).whereType<SavedMessage>().toList();
  }

  static Future<void> save(List<SavedMessage> messages, {bool guest = false}) async {
    final box = _box;
    if (box == null) return;
    final kept = messages.length > max ? messages.sublist(messages.length - max) : messages;
    await box.put(guest ? guestKey : accountKey, [for (final m in kept) m.toMap()]);
  }

  static Future<void> clear({bool guest = false}) async => _box?.delete(guest ? guestKey : accountKey);

  // the first signed-in start after a guest chat: carry it over once
  static Future<bool> adoptGuest() async {
    final box = _box;
    if (box == null) return false;
    final guest = load(guest: true);
    if (guest.isEmpty) return false;
    if (load().isEmpty) await save(guest);
    await box.delete(guestKey);
    return true;
  }
}
