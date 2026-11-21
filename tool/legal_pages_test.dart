// Writes the legal pages of the website: landing/impressum.html and
// landing/datenschutz.html, each in German and English (?lang=en, or the
// browser language). The website has its own privacy text, because it only
// presents Ahead and keeps a waitlist; the app's privacy text is in the app.
// Contact details come from the same place as the app's. Run after changing the texts:
//
//   flutter test tool/legal_pages_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:budget_buddy/l10n/l10n.dart';
import 'package:budget_buddy/legal/legal_info.dart';
import 'package:budget_buddy/legal/legal_lang.dart';
import 'package:budget_buddy/legal/legal_texts.dart';
import 'package:flutter_test/flutter_test.dart';

String _esc(String s) => const HtmlEscape(HtmlEscapeMode.element).convert(s);

String _doc(LegalDoc d, String lang) {
  final b = StringBuffer('<article lang="$lang" data-lang="$lang"><h1>${_esc(d.title)}</h1>');
  for (final s in d.sections) {
    b.write('<h2>${_esc(s.heading)}</h2>');
    for (final p in s.body.split('\n\n')) {
      b.write('<p>${_esc(p).replaceAll('\n', '<br>')}</p>');
    }
  }
  return '$b</article>';
}

String _page(String title, String de, String en) => '''<!DOCTYPE html>
<html lang="de">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="robots" content="noindex">
<title>$title · Ahead</title>
<link rel="icon" href="appicon.png">
<style>
  :root{--copper:#B06030;--paper:#FFFFFF;--ink:#17120E;--soft:#6E655F;--line:#ECE6E1;
        --text:"Inter",ui-sans-serif,system-ui,-apple-system,sans-serif}
  @media (prefers-color-scheme:dark){:root:not([data-theme="light"]){--paper:#12100E;--ink:#F3EDE8;--soft:#A39A93;--line:#2A2420;color-scheme:dark}}
  :root[data-theme="dark"]{--paper:#12100E;--ink:#F3EDE8;--soft:#A39A93;--line:#2A2420;color-scheme:dark}
  *{box-sizing:border-box;margin:0;padding:0}
  body{background:var(--paper);color:var(--ink);font:400 16px/1.6 var(--text);-webkit-font-smoothing:antialiased}
  .w{max-width:720px;margin:0 auto;padding:28px 16px 64px}
  nav{display:flex;justify-content:space-between;align-items:center;margin-bottom:36px}
  nav a,nav button{color:var(--ink);font:600 15px/1 var(--text);text-decoration:none;background:none;border:1px solid var(--line);
        border-radius:999px;padding:10px 14px;cursor:pointer}
  h1{font-size:clamp(30px,6vw,44px);letter-spacing:-.03em;line-height:1.05;margin-bottom:20px}
  h2{font-size:18px;margin:28px 0 8px}
  p{margin-bottom:12px;color:var(--ink)}
  article[hidden]{display:none}
  :focus-visible{outline:2px solid var(--copper);outline-offset:3px}
</style>
</head>
<body>
<div class="w">
  <nav><a href="./" data-back>← Ahead</a><button type="button" data-switch>EN</button></nav>
  $de
  $en
</div>
<script>
(function () {
  var q = new URLSearchParams(location.search).get('lang'), saved = null;
  try { saved = localStorage.getItem('ahead-lang'); } catch (e) {}
  var lang = q === 'en' || q === 'de' ? q : saved || ((navigator.language || 'de').toLowerCase().indexOf('de') === 0 ? 'de' : 'en');
  function apply() {
    document.documentElement.lang = lang;
    document.querySelectorAll('article').forEach(function (a) { a.hidden = a.dataset.lang !== lang; });
    var b = document.querySelector('[data-switch]');
    b.textContent = lang === 'en' ? 'DE' : 'EN';
    b.setAttribute('aria-label', lang === 'en' ? 'Auf Deutsch lesen' : 'Read in English');
    document.querySelector('[data-back]').href = './?lang=' + lang;
  }
  document.querySelector('[data-switch]').addEventListener('click', function () {
    lang = lang === 'en' ? 'de' : 'en';
    try { localStorage.setItem('ahead-lang', lang); } catch (e) {}
    apply();
  });
  apply();
})();
</script>
</body>
</html>
''';

// the app's imprint, with the liability paragraph written for a website instead of an app
LegalDoc _siteImprint() {
  final app = LegalTexts.imprint;
  return LegalDoc(app.title, [
    ...app.sections.take(app.sections.length - 1),
    L10n.isDe
        ? const LegalSection(
            'Haftung für Inhalte',
            'Wir erstellen die Inhalte dieser Website mit Sorgfalt. Ahead ist in Entwicklung, Angaben zum Produkt '
                'können sich ändern. Die Inhalte sind keine Anlage-, Steuer- oder Rechtsberatung.')
        : const LegalSection(
            'Liability for content',
            'We create the content of this website with care. Ahead is in development, and details about the '
                'product can change. The content is not investment, tax or legal advice.'),
  ]);
}

const _authority = 'Der Hamburgische Beauftragte für Datenschutz und Informationsfreiheit, '
    'Ludwig-Erhard-Str. 22, 20459 Hamburg';

LegalDoc _sitePrivacy() => L10n.isDe
    ? const LegalDoc('Datenschutzerklärung', [
        LegalSection(
            'Auf einen Blick',
            'Diese Website stellt Ahead vor und führt eine Warteliste. Sie setzt keine Cookies, nutzt kein Tracking '
                'und zeigt keine Werbung. Schriften und Skripte kommen von dieser Website selbst, nicht von Dritten.'
                '\n\nStand: November 2026'),
        LegalSection(
            '1. Verantwortlicher',
            '${LegalInfo.provider}\n${LegalInfo.street}\n${LegalInfo.city}\n${LegalInfo.country}\n'
                'E-Mail: ${LegalInfo.email}'),
        LegalSection(
            '2. Aufruf der Website',
            'Die Website liegt bei Netlify, Inc., 101 2nd Street, San Francisco, CA 94105, USA. Netlify arbeitet '
                'in unserem Auftrag. Wenn du die Website aufrufst, verarbeitet Netlify technisch notwendige Daten '
                'wie deine IP-Adresse, den Zeitpunkt und Angaben zu deinem Browser, um die Seite auszuliefern und '
                'Angriffe abzuwehren. Wir werten diese Daten nicht aus. Rechtsgrundlage '
                'ist Art. 6 Abs. 1 lit. f DSGVO (berechtigtes Interesse an einer sicheren und erreichbaren Website). '
                'Dabei können Daten in die USA übertragen werden. Netlify stützt das nach eigenen Angaben auf das '
                'EU-US Data Privacy Framework und auf Standardvertragsklauseln.'),
        LegalSection(
            '3. Warteliste',
            'Wenn du deine E-Mail-Adresse einträgst, speichern wir sie zusammen mit dem Zeitpunkt und der gewählten '
                'Sprache in unserer Liste beim Newsletter-Dienst Brevo (Brevo SAS, 17 rue de Salneuve, 75017 Paris, '
                'Frankreich). Brevo arbeitet in unserem Auftrag und kann dabei technische Angaben wie die IP-Adresse '
                'verarbeiten, um Missbrauch zu erkennen. Du bekommst zuerst eine E-Mail mit einem Bestätigungs-Link. '
                'Erst wenn du ihn anklickst, stehst du auf der Liste. Wir nutzen deine Adresse, um dir Neuigkeiten zu Ahead und '
                'die Nachricht zum Start zu schicken, und geben sie nicht weiter. Rechtsgrundlage ist deine '
                'Einwilligung (Art. 6 Abs. 1 lit. a DSGVO). Du kannst sie jederzeit widerrufen: über den Abmelde-Link '
                'in jeder E-Mail oder mit einer kurzen Nachricht an uns. Dann löschen wir deinen Eintrag.'
                '\n\nIst das Formular einmal nicht erreichbar, öffnet die Seite stattdessen dein E-Mail-Programm mit '
                'einer vorbereiteten Nachricht. Dann erhalten wir deine Adresse erst, wenn du die Nachricht abschickst.'),
        LegalSection(
            '4. Speicher in deinem Browser',
            'Die Seite merkt sich in deinem Browser die gewählte Sprache und, falls du über einen Einladungslink '
                'gekommen bist, den Code aus diesem Link. Beides bleibt auf deinem Gerät. Cookies setzt die Seite nicht.'),
        LegalSection(
            '5. Kontakt per E-Mail',
            'Schreibst du uns, verarbeiten wir deine Angaben, um dir zu antworten (Art. 6 Abs. 1 lit. f DSGVO). '
                'Wir löschen die Nachricht, wenn die Sache erledigt ist und keine Aufbewahrungspflicht besteht.'),
        LegalSection(
            '6. Deine Rechte',
            'Du hast das Recht auf Auskunft (Art. 15 DSGVO), Berichtigung (Art. 16), Löschung (Art. 17), '
                'Einschränkung der Verarbeitung (Art. 18), Datenübertragbarkeit (Art. 20) und Widerspruch (Art. 21). '
                'Eine erteilte Einwilligung kannst du jederzeit widerrufen. Schreib dafür an ${LegalInfo.email}.'
                '\n\nDu kannst dich außerdem bei einer Datenschutz-Aufsichtsbehörde beschweren, zum Beispiel bei '
                '$_authority.'),
        LegalSection('7. Die App', 'Für die Ahead-App gilt eine eigene Datenschutzerklärung. Du findest sie in der App.'),
      ])
    : const LegalDoc('Privacy policy', [
        LegalSection('Note', 'This is a translation for your convenience. Only the German version is legally binding.'),
        LegalSection(
            'At a glance',
            'This website presents Ahead and keeps a waitlist. It sets no cookies, uses no tracking and shows no '
                'advertising. Fonts and scripts come from this website itself, not from third parties.'
                '\n\nLast updated: November 2026'),
        LegalSection(
            '1. Controller',
            '${LegalInfo.provider}\n${LegalInfo.street}\n${LegalInfo.city}\nGermany\nEmail: ${LegalInfo.email}'),
        LegalSection(
            '2. Visiting the website',
            'The website is hosted by Netlify, Inc., 101 2nd Street, San Francisco, CA 94105, USA. Netlify works '
                'on our behalf. When you open the website, Netlify processes technically necessary data such as '
                'your IP address, the time and details of your browser in order to deliver the page and ward off '
                'attacks. We do not evaluate this data. The legal basis is Art. 6 (1) (f) GDPR '
                '(legitimate interest in a secure and reachable website). Data may be transferred to the USA. '
                'According to Netlify, this is based on the EU-US Data Privacy Framework and standard contractual clauses.'),
        LegalSection(
            '3. Waitlist',
            'When you enter your email address, we store it together with the time and the chosen language in our '
                'list at the newsletter service Brevo (Brevo SAS, 17 rue de Salneuve, 75017 Paris, France). Brevo '
                'works on our behalf and may process technical details such as the IP address to detect abuse. You '
                'first receive an email with a confirmation link. Only when you click it are you on the list. We use '
                'your address to send you news about Ahead and the message at launch, and we do not pass it on. The '
                'legal basis is your consent (Art. 6 (1) (a) GDPR). You can withdraw it at any time: through the '
                'unsubscribe link in every email or with a short message to us. We then delete your entry.'
                '\n\nIf the form cannot be reached, the page opens your email program with a prepared message instead. '
                'In that case we only receive your address when you send the message.'),
        LegalSection(
            '4. Storage in your browser',
            'The page remembers the chosen language in your browser and, if you came through an invitation link, '
                'the code from that link. Both stay on your device. The page sets no cookies.'),
        LegalSection(
            '5. Contact by email',
            'If you write to us, we process your details in order to answer you (Art. 6 (1) (f) GDPR). We delete the '
                'message once the matter is settled and no retention duty applies.'),
        LegalSection(
            '6. Your rights',
            'You have the right of access (Art. 15 GDPR), rectification (Art. 16), erasure (Art. 17), restriction of '
                'processing (Art. 18), data portability (Art. 20) and objection (Art. 21). You can withdraw consent at '
                'any time. Write to ${LegalInfo.email}.'
                '\n\nYou can also complain to a data protection authority, for example $_authority.'),
        LegalSection('7. The app', 'The Ahead app has its own privacy policy. You find it in the app.'),
      ]);

void main() {
  test('legal pages for the website', () {
    LegalLang.isDe = () => L10n.isDe;
    String both(LegalDoc Function() doc) {
      L10n.lang.value = 'de';
      final de = _doc(doc(), 'de');
      L10n.lang.value = 'en';
      final en = _doc(doc(), 'en');
      L10n.lang.value = 'de';
      return '$de\n  $en';
    }

    final imprint = both(_siteImprint).split('\n  ');
    final privacy = both(_sitePrivacy).split('\n  ');
    File('landing/impressum.html').writeAsStringSync(_page('Impressum', imprint[0], imprint[1]));
    File('landing/datenschutz.html').writeAsStringSync(_page('Datenschutz', privacy[0], privacy[1]));
    final page = File('landing/datenschutz.html').readAsStringSync();
    expect(page, contains('Privacy policy'));
    // the website's page must not describe app features a visitor cannot use here
    expect(page, isNot(contains('Enable Banking')));
  });
}
