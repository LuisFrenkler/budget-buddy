// Writes the legal pages of the website from the same texts as the app:
// landing/impressum.html and landing/datenschutz.html, each in German and
// English (?lang=en, or the browser language). Run after changing the texts:
//
//   flutter test tool/legal_pages_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:budget_buddy/l10n/l10n.dart';
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

void main() {
  test('legal pages for the website', () {
    String both(LegalDoc Function() doc) {
      L10n.lang.value = 'de';
      final de = _doc(doc(), 'de');
      L10n.lang.value = 'en';
      final en = _doc(doc(), 'en');
      L10n.lang.value = 'de';
      return '$de\n  $en';
    }

    final imprint = both(() => LegalTexts.imprint).split('\n  ');
    final privacy = both(() => LegalTexts.privacy).split('\n  ');
    File('landing/impressum.html').writeAsStringSync(_page('Impressum', imprint[0], imprint[1]));
    File('landing/datenschutz.html').writeAsStringSync(_page('Datenschutz', privacy[0], privacy[1]));
    expect(File('landing/datenschutz.html').readAsStringSync(), contains('Privacy policy'));
  });
}
