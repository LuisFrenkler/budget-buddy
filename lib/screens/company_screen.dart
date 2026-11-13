import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../legal/legal_info.dart';
import '../legal/legal_texts.dart';
import '../utils/theme.dart';
import '../widgets/settings_list.dart';
import 'about_screen.dart';
import '../l10n/l10n.dart';

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
      query: 'subject=${Uri.encodeComponent('Mitarbeit bei Ahead')}',
    );
    if (LegalInfo.email.startsWith('[') || !await launchUrl(uri)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('Schreib uns an {email}', {'email': LegalInfo.email}))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dim = TextStyle(color: AppColors.text.withValues(alpha: 0.88), fontSize: 14.5, height: 1.5);
    return Scaffold(
      appBar: AppBar(title: Text(tr('Unternehmen & Vertrauen'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          _block(
            tr('Über Ahead'),
            tr('Ahead hilft, Alltagsgeld zu verstehen: was reinkommt, was regelmäßig weggeht, und was für Ziele oder eine grobe Vorsorge übrig bleibt. Die App führt kein Konto, zahlt nichts aus und ersetzt keine Beratung.'),
            dim,
          ),
          _block(
            tr('Für Nutzer'),
            tr('Die App ist privacy-first gebaut. Umsätze, Budgets, Ziele und Depot liegen zuerst auf deinem Gerät. Mit einem Konto gibt es zusätzlich eine Kopie, die dein Gerät vor dem Hochladen verschlüsselt, wir können sie nicht lesen. Keine Werbung, kein Tracking, kein Verkauf von Daten.'),
            dim,
          ),
          _block(
            tr('Für Investoren'),
            tr('Finanzguru ist eine Haushalts-App für ein großes Publikum, mit KI als Zusatz. Ahead ist ein Coach, dem die App nur als Datenquelle dient: gebaut für Lebenslagen wie den ersten Job, mit Erklärungen genau dann, wenn ein Begriff auftaucht, und Buddy bereitet vor, die Person entscheidet. Depot und Vorsorge sind Orientierung ohne Vermittlung. Wir nennen keine Nutzerzahlen, die einen Vergleich tragen würden. Buddy holt sich nur die Daten, die er für eine Frage braucht, und nur mit Zustimmung.'),
            dim,
          ),
          _block(
            tr('Karriere & Weiterbildung'),
            tr('Wir bauen die App selbst und sind offen für Werkstudenten, Praktika und Menschen, die Produkt, Flutter oder das Backend ernst nehmen. Ein paar Sätze, woran du arbeiten willst, reichen.'),
            dim,
          ),
          SettingsGroup([
            SettingsRow(
              icon: Icons.mail_outline_rounded,
              title: tr('Mitarbeit anfragen'),
              subtitle: LegalInfo.email,
              onTap: () => _mail(context),
              external: true,
            ),
          ]),
          _block(
            tr('Transparenz'),
            tr('Passwörter speichern wir nur als bcrypt-Hash. Optional kannst du unter Mein Konto → Sicherheit eine Authenticator-App als zweiten Faktor einschalten; angemeldete Geräte lassen sich einzeln oder alle widerrufen. Auf dem Gerät schützt zusätzlich die App-Sperre.\n\nDie Bankverbindung läuft über Enable Banking. Du bestätigst den Zugriff bei deiner Bank (starke Kundenauthentifizierung). Weder wir noch die App sehen deine Zugangsdaten.\n\nBuddy mit KI sendet nur nach deiner Zustimmung eine Zusammenfassung ohne Kontonummern. Ohne Zustimmung bleibt die Antwort auf dem Gerät, soweit sie dort möglich ist.'),
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
                    tr('Vor Store-Release noch ausfüllen: {x}. Nur in Test-Versionen sichtbar.', {'x': LegalInfo.missing.join(', ')}),
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
              ]),
            ),
          ],
          SectionLabel(tr('Rechtliches')),
          SettingsGroup([
            SettingsRow(
              icon: Icons.business_rounded,
              title: tr('Impressum'),
              onTap: () => _open(context, LegalTexts.imprint),
            ),
            SettingsRow(
              icon: Icons.privacy_tip_outlined,
              title: tr('Datenschutzerklärung'),
              onTap: () => _open(context, LegalTexts.privacy),
            ),
            SettingsRow(
              icon: Icons.description_outlined,
              title: tr('Nutzungsbedingungen'),
              onTap: () => _open(context, LegalTexts.terms),
            ),
            SettingsRow(
              icon: Icons.undo_rounded,
              title: tr('Widerrufsbelehrung'),
              onTap: () => _open(context, LegalTexts.withdrawal),
            ),
            SettingsRow(
              icon: Icons.info_outline_rounded,
              title: tr('Wichtige Hinweise'),
              subtitle: tr('Keine Anlageberatung, Kurse, KI'),
              onTap: () => _open(context, LegalTexts.notes),
            ),
            SettingsRow(
              icon: Icons.help_outline_rounded,
              title: tr('Hilfe & Lizenzen'),
              subtitle: tr('Support und Open Source'),
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
