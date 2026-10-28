import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../legal/legal_info.dart';
import '../legal/legal_texts.dart';
import '../utils/theme.dart';
import '../widgets/brand.dart';
import '../widgets/settings_list.dart';

// "Über BudgetBuddy": version, help and every legal page in one place.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  void _open(BuildContext context, LegalDoc doc) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => LegalDocScreen(doc: doc)));

  Future<void> _mail(BuildContext context, String subject) async {
    final uri = Uri(scheme: 'mailto', path: LegalInfo.email, query: 'subject=${Uri.encodeComponent(subject)}');
    if (LegalInfo.email.startsWith('[') || !await launchUrl(uri)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(duration: const Duration(milliseconds: 2800), content: Text('Schreib uns an ${LegalInfo.email}')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Über BudgetBuddy')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          const SizedBox(height: 8),
          const Center(child: BrandMark(size: 72)),
          const SizedBox(height: 14),
          const Center(child: Wordmark(size: 24)),
          const SizedBox(height: 4),
          Center(
            child: Text('Version ${LegalInfo.appVersion}', style: TextStyle(color: AppColors.textDim, fontSize: 13)),
          ),
          const SizedBox(height: 10),
          Center(
            child: Text('Deine Finanzen. Klar, smart und privat.',
                style: TextStyle(color: AppColors.textDim, fontSize: 14)),
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
                    'Vor der Veröffentlichung noch: ${LegalInfo.missing.isEmpty ? 'Anbieter-Angaben' : LegalInfo.missing.join(', ')}. '
                    'Nur in Test-Versionen sichtbar.',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
              ]),
            ),
          ],
          const SectionLabel('Hilfe'),
          SettingsGroup([
            SettingsRow(
              icon: Icons.mail_outline_rounded,
              title: 'Support kontaktieren',
              subtitle: 'Wir antworten meist innerhalb eines Tages',
              onTap: () => _mail(context, 'BudgetBuddy Support'),
              external: true,
            ),
            SettingsRow(
              icon: Icons.lightbulb_outline_rounded,
              title: 'Idee vorschlagen',
              subtitle: 'Was würde BudgetBuddy für dich besser machen?',
              onTap: () => _mail(context, 'Idee für BudgetBuddy'),
              external: true,
            ),
            SettingsRow(
              icon: Icons.info_outline_rounded,
              title: 'Wichtige Hinweise',
              subtitle: 'Keine Anlageberatung, Kurse, KI',
              onTap: () => _open(context, LegalTexts.notes),
            ),
          ]),
          const SectionLabel('Rechtliches'),
          SettingsGroup([
            SettingsRow(icon: Icons.business_rounded, title: 'Impressum', onTap: () => _open(context, LegalTexts.imprint)),
            SettingsRow(
                icon: Icons.privacy_tip_outlined,
                title: 'Datenschutzerklärung',
                onTap: () => _open(context, LegalTexts.privacy)),
            SettingsRow(
                icon: Icons.description_outlined,
                title: 'Nutzungsbedingungen',
                onTap: () => _open(context, LegalTexts.terms)),
            SettingsRow(
                icon: Icons.undo_rounded,
                title: 'Widerrufsbelehrung',
                onTap: () => _open(context, LegalTexts.withdrawal)),
            SettingsRow(
              icon: Icons.code_rounded,
              title: 'Open-Source-Lizenzen',
              onTap: () => showLicensePage(
                context: context,
                applicationName: 'BudgetBuddy',
                applicationVersion: LegalInfo.appVersion,
                applicationIcon: const Padding(padding: EdgeInsets.all(12), child: BrandMark(size: 48)),
              ),
            ),
          ]),
          const SizedBox(height: 28),
          Center(
            child: Text('Mit 💜 in Deutschland gemacht', style: TextStyle(color: AppColors.textDim, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

// One legal page, readable and selectable.
class LegalDocScreen extends StatelessWidget {
  final LegalDoc doc;
  const LegalDocScreen({super.key, required this.doc});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(doc.title)),
      body: SelectionArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 48),
          children: [
            for (final s in doc.sections) ...[
              Padding(
                padding: const EdgeInsets.only(top: 18, bottom: 6),
                child: Text(s.heading, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              ),
              for (final p in s.body.split('\n\n'))
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(p, style: TextStyle(fontSize: 14.5, height: 1.5, color: AppColors.text.withValues(alpha: 0.88))),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
