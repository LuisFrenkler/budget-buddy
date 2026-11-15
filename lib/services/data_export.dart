// "Alle meine Daten" (Art. 15 and 20 GDPR) in one file: everything the app
// keeps on this device, what Buddy was allowed to remember, the notes and
// payslip numbers, the account it belongs to, and where each kind of data
// lives. Readable JSON, made on the device; nothing is sent anywhere.
import 'dart:convert';

import 'package:hive/hive.dart';

import '../legal/data_map.dart';
import '../legal/legal_info.dart';
import 'account_service.dart';
import 'backup_service.dart';

class DataExport {
  static String build({required DataStatus status, DateTime? now}) {
    final settings = Hive.isBoxOpen('settings') ? Hive.box('settings') : null;
    final user = AccountService.current.value;
    final device = jsonDecode(BackupService.toBackupJson()) as Map<String, dynamic>;
    final data = {
      'art': 'Ahead – alle meine Daten',
      'erstellt': (now ?? DateTime.now()).toIso8601String(),
      'verantwortlich': {'name': LegalInfo.provider, 'email': LegalInfo.email},
      if (user != null) 'konto': {'name': user.name, 'email': user.email},
      'aufDiesemGeraet': device,
      'buddy': {
        'gemerkt': settings?.get('buddyMemory') ?? const [],
        'notizen': settings?.get('buddyJournal') ?? const [],
        'gehaltsabrechnungen': settings?.get('payslips') ?? const [],
      },
      'woDieDatenLiegen': [
        for (final f in DataMap.flows(status))
          {'was': f.what, 'wo': f.where, 'werLiest': f.who, 'stoppen': f.end, 'aktiv': f.active}
      ],
      'hinweis': 'Auf unserem Server liegen zusätzlich dein Konto (Name, E-Mail, Passwort-Hash) und eine '
          'verschlüsselte Kopie derselben Daten, die nur du öffnen kannst. Für alles andere: ${LegalInfo.email}',
    };
    return const JsonEncoder.withIndent('  ').convert(data);
  }
}
