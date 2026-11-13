// What Buddy may remember about the person: a short list of facts they
// confirmed themselves ("Erster Job seit Oktober", "Spart auf eine Wohnung").
// Buddy only ever suggests; a fact lands here after the person taps "Merken".
// Everything is visible under "Was Buddy über dich weiß" and goes with one tap.
//
// The list belongs to the signed-in account (wiped on logout, part of the
// encrypted backup) and goes to the AI only with the rest of the summary,
// after the person agreed to "Buddy mit KI".
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

class MemoryFact {
  final String id;
  final String text;
  final DateTime at;
  const MemoryFact(this.id, this.text, this.at);

  Map<String, dynamic> toMap() => {'id': id, 'text': text, 'at': at.toIso8601String()};

  static MemoryFact? fromMap(Object? m) {
    if (m is! Map) return null;
    final text = '${m['text'] ?? ''}'.trim();
    if (text.isEmpty) return null;
    return MemoryFact('${m['id'] ?? text.hashCode}', text, DateTime.tryParse('${m['at']}') ?? DateTime.now());
  }
}

class BuddyMemory {
  static const key = 'buddyMemory';
  static const max = 30;
  static const maxLength = 140;

  // bumps on every change, so the chat and the memory page stay in step
  static final changed = ValueNotifier<int>(0);

  static Box? get _box => Hive.isBoxOpen('settings') ? Hive.box('settings') : null;

  static List<MemoryFact> all() {
    final raw = _box?.get(key);
    if (raw is! List) return const [];
    return raw.map(MemoryFact.fromMap).whereType<MemoryFact>().toList();
  }

  static List<String> texts() => [for (final f in all()) f.text];

  // things that do not belong in a finance coach's memory
  static final _sensitive = RegExp(
      r'krank|diagnos|therap|depress|schwanger|religi|glaube|partei|politi|sex|iban|passwort|pin\b|kartennummer|\bDE\d{2}',
      caseSensitive: false);

  static bool allowed(String text) => text.trim().isNotEmpty && !_sensitive.hasMatch(text);

  static String clean(String text) {
    var t = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (t.endsWith('.')) t = t.substring(0, t.length - 1);
    if (t.length > maxLength) t = '${t.substring(0, maxLength - 1)}…';
    return t;
  }

  static bool knows(String text) {
    final t = clean(text).toLowerCase();
    return all().any((f) => f.text.toLowerCase() == t);
  }

  // false when it is empty, sensitive, or already known
  static Future<bool> add(String text, {DateTime? now}) async {
    final box = _box;
    if (box == null || !allowed(text) || knows(text)) return false;
    final t = clean(text);
    final at = now ?? DateTime.now();
    final list = [...all(), MemoryFact('${at.microsecondsSinceEpoch}', t, at)];
    final kept = list.length > max ? list.sublist(list.length - max) : list;
    await box.put(key, [for (final f in kept) f.toMap()]);
    changed.value++;
    return true;
  }

  static Future<void> remove(String id) async {
    final box = _box;
    if (box == null) return;
    await box.put(key, [for (final f in all()) if (f.id != id) f.toMap()]);
    changed.value++;
  }

  static Future<void> clear() async {
    await _box?.delete(key);
    changed.value++;
  }

  // "Merk dir, dass ich im Oktober anfange" -> "Dass ich im Oktober anfange"
  // (said straight to Buddy; still confirmed with a tap)
  static String? fromCommand(String message) {
    final m = RegExp(r'^\s*(?:bitte\s+)?merk(?:e)?\s+dir\s*(?:bitte\s*)?[,:]?\s*(.+)$', caseSensitive: false)
        .firstMatch(message);
    final what = m?.group(1)?.trim();
    if (what == null || what.length < 3) return null;
    return clean(what[0].toUpperCase() + what.substring(1));
  }
}
