// "Kündigen mit einem Tipp": Buddy writes the cancellation letter, keeps the
// date it was sent and later checks that the payments really stop.
import 'package:hive/hive.dart';
import '../utils/dates.dart';
import 'contracts.dart';

class CancellationService {
  static String _key(String name) => name.toLowerCase().trim();

  static Map<String, DateTime> get all {
    if (!Hive.isBoxOpen('settings')) return const {};
    final raw = Hive.box('settings').get('cancellations') as Map? ?? const {};
    return {for (final e in raw.entries) '${e.key}': DateTime.parse('${e.value}')};
  }

  static DateTime? sentAt(String name) => all[_key(name)];

  static Future<void> markSent(String name, {DateTime? at}) async {
    final map = {for (final e in all.entries) e.key: e.value.toIso8601String()};
    map[_key(name)] = (at ?? DateTime.now()).toIso8601String();
    await Hive.box('settings').put('cancellations', map);
  }

  static Future<void> undo(String name) async {
    final map = {for (final e in all.entries) e.key: e.value.toIso8601String()}..remove(_key(name));
    await Hive.box('settings').put('cancellations', map);
  }

  // a payment more than five weeks after the letter: the cancellation did not work
  static bool stillCharging(Contract c, DateTime sent) =>
      c.last.date.isAfter(sent.add(const Duration(days: 35)));

  static String subject(String provider, String customerNo) =>
      'Kündigung${customerNo.isEmpty ? '' : ' Kundennummer $customerNo'}';

  static String letter({
    required String provider,
    required String name,
    required String email,
    String customerNo = '',
    DateTime? date,
  }) {
    final today = date ?? DateTime.now();
    final sender = [if (name.isNotEmpty) name, if (email.isNotEmpty) email].join('\n');
    return [
      if (sender.isNotEmpty) '$sender\n',
      'An: $provider\n',
      Dates.full(today),
      '',
      'Kündigung meines Vertrags${customerNo.isEmpty ? '' : ' (Kundennummer $customerNo)'}',
      '',
      'Sehr geehrte Damen und Herren,',
      '',
      'hiermit kündige ich meinen Vertrag bei $provider fristgerecht zum nächstmöglichen Zeitpunkt.',
      '',
      'Bitte bestätigen Sie mir den Eingang dieser Kündigung und das Datum des Vertragsendes schriftlich. '
          'Eine erteilte Einzugsermächtigung (SEPA-Lastschriftmandat) widerrufe ich zum Vertragsende.',
      '',
      'Mit freundlichen Grüßen',
      if (name.isNotEmpty) name,
    ].join('\n');
  }
}
