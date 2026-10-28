import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../legal/legal_info.dart';
import '../legal/legal_texts.dart';
import '../utils/theme.dart';
import '../widgets/settings_list.dart';
import 'about_screen.dart';

// Who we are, for users, investors and people who might work with us.
// Legal pages stay the LegalDoc screens; this page only points at them.
class CompanyScreen extends StatelessWidget {
  const CompanyScreen({super.key});

  void _open(BuildContext context, LegalDoc doc) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => LegalDocScreen(doc: doc)));

  Future<void> _mail(BuildContext context) async {
    final uri = Uri(
      scheme: 'mailto',
      path: LegalInfo.email,
      query: 'subject=${Uri.encodeComponent('Mitarbeit bei BudgetBuddy')}',
    );
    if (LegalInfo.email.startsWith('[') || !await launchUrl(uri)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Schreib uns an ${LegalInfo.email}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dim = TextStyle(color: AppColors.text.withValues(alpha: 0.88), fontSize: 14.5, height: 1.5);
    return Scaffold(
      appBar: AppBar(title: const Text('Unternehmen & Vertrauen')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          _block(
            'Über BudgetBuddy',
            'BudgetBuddy hilft, Alltagsgeld zu verstehen: was reinkommt, was regelmäßig '
                'weggeht, und was für Ziele oder eine grobe Vorsorge übrig bleibt. Die App '
                'führt kein Konto, zahlt nichts aus und ersetzt keine Beratung.',
            dim,
          ),
          _block(
            'Für Nutzer',
            'Die App ist privacy-first gebaut. Umsätze, Budgets, Ziele und Depot liegen '
                'zuerst auf deinem Gerät. Mit einem Konto gibt es zusätzlich eine Kopie, '
                'die dein Gerät vor dem Hochladen verschlüsselt — wir können sie nicht lesen. '
                'Keine Werbung, kein Tracking, kein Verkauf von Daten.',
            dim,
          ),
          _block(
            'Für Investoren',
            'Finanzguru ist der etablierte Kontenüberblick für ein großes Publikum. '
                'BudgetBuddy setzt daneben an und ist früher dran: ein privater Coach für '
                'den Alltag, Buddy nur mit Zustimmung, Verträge aus den eigenen Buchungen, '
                'Depot und Vorsorge als Orientierung ohne Vermittlung. Wir nennen keine '
                'Nutzerzahlen, die einen Vergleich tragen würden, und beanspruchen den Markt '
                'nicht. Wer einsteigt, steigt in ein Produkt ein, das noch gebaut wird — '
                'mit dem Unterschied, dass die Finanzdaten bei der Person bleiben.',
            dim,
          ),
          _block(
            'Karriere & Weiterbildung',
            'Wir bauen die App selbst und sind offen für Werkstudenten, Praktika und '
                'Menschen, die Produkt, Flutter oder das Backend ernst nehmen. Ein paar '
                'Sätze, woran du arbeiten willst, reichen.',
            dim,
          ),
          SettingsGroup([
            SettingsRow(
              icon: Icons.mail_outline_rounded,
              title: 'Mitarbeit anfragen',
              subtitle: LegalInfo.email,
              onTap: () => _mail(context),
              external: true,
            ),
          ]),
          _block(
            'Transparenz',
            'Passwörter speichern wir nur als bcrypt-Hash. Optional kannst du unter '
                'Mein Konto → Sicherheit eine Authenticator-App als zweiten Faktor '
                'einschalten; angemeldete Geräte lassen sich einzeln oder alle widerrufen. '
                'Auf dem Gerät schützt zusätzlich die App-Sperre.\n\n'
                'Die Bankverbindung läuft über Enable Banking. Du bestätigst den Zugriff '
                'bei deiner Bank (starke Kundenauthentifizierung). Weder wir noch die App '
                'sehen deine Zugangsdaten.\n\n'
                'Buddy mit KI sendet nur nach deiner Zustimmung eine Zusammenfassung ohne '
                'Kontonummern. Ohne Zustimmung bleibt die Antwort auf dem Gerät, soweit '
                'sie dort möglich ist.',
            dim,
          ),
          if (!kReleaseMode && !LegalInfo.complete) ...[
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                const Icon(Icons.edit_note_rounded, color: AppColors.warning),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Vor Store-Release noch ausfüllen: ${LegalInfo.missing.join(', ')}. '
                    'Nur in Test-Versionen sichtbar.',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
              ]),
            ),
          ],
          const SectionLabel('Rechtliches'),
          SettingsGroup([
            SettingsRow(
              icon: Icons.business_rounded,
              title: 'Impressum',
              onTap: () => _open(context, LegalTexts.imprint),
            ),
            SettingsRow(
              icon: Icons.privacy_tip_outlined,
              title: 'Datenschutzerklärung',
              onTap: () => _open(context, LegalTexts.privacy),
            ),
            SettingsRow(
              icon: Icons.description_outlined,
              title: 'Nutzungsbedingungen',
              onTap: () => _open(context, LegalTexts.terms),
            ),
            SettingsRow(
              icon: Icons.undo_rounded,
              title: 'Widerrufsbelehrung',
              onTap: () => _open(context, LegalTexts.withdrawal),
            ),
            SettingsRow(
              icon: Icons.info_outline_rounded,
              title: 'Wichtige Hinweise',
              subtitle: 'Keine Anlageberatung, Kurse, KI',
              onTap: () => _open(context, LegalTexts.notes),
            ),
            SettingsRow(
              icon: Icons.help_outline_rounded,
              title: 'Hilfe & Lizenzen',
              subtitle: 'Support und Open Source',
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AboutScreen())),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _block(String title, String body, TextStyle style) {
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text(body, style: style),
        const SizedBox(height: 4),
      ]),
    );
  }
}
