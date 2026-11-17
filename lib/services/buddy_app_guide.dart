// App questions ("Passwort ändern?", "Wo ist Plus?") answered on the device:
// the path in the app, then one next step. Name and email only from the
// signed-in account, never guessed.
import '../l10n/l10n.dart';
import 'account_service.dart';

class BuddyAppGuide {
  static bool matches(String q) => _topic(_norm(q)) != null;

  static String? answerOrNull(String q) {
    final t = _topic(_norm(q));
    return t == null ? null : _text(t);
  }

  static String _norm(String q) =>
      q.toLowerCase().replaceAll('’', "'").replaceAll('´', "'").trim();

  // "ändern" sits next to a word boundary that \b misses, so match the stems plainly
  static final _passwordWord = RegExp(r'passwort|password');
  static final _passwordVerb = RegExp(r'änder|aender|ander|wechsel|change|reset|update|\bneu\b|vergess|forgot');
  static final _account = RegExp(
    r"wie hei(ss|ß)t mein (account|konto|name)|"
    r"wie lautet mein(e)? (name|e-?mail|email|account)|"
    r"wie ist meine e-?mail|welche e-?mail|"
    r"what('?s| is) my (account(?! balance)|name|e-?mail|email)|"
    r"\b(account name|mein account|my account name|my email|meine e-?mail)\b|"
    r"wie hei(ss|ß)e ich|"
    r"\b(e-?mail|email)\b.{0,24}\b(ander\w*|änder\w*|aender\w*|wechsel\w*|change\w*)\b|"
    r"\b(ander\w*|änder\w*|aender\w*|wechsel\w*|change\w*)\b.{0,30}\b(e-?mail|email|namen|name)\b",
    unicode: true,
  );
  static final _plus = RegExp(
    r"\b(ahead plus|was ist plus|what('?s| is) plus)\b|"
    r"\b(wo (ist|finde ich)|where (is|do i find|can i find)|finde ich|find)\b.{0,24}\b(plus|premium|abo)\b",
    unicode: true,
  );
  static final _privacy = RegExp(
    r'\b(wo (finde ich|ist|liegt)|where (is|do i find|can i find))\b.{0,40}\b(datenschutz|privacy|privatsph\w*|datenschutzerkl\w*)\b|'
    r'\b(datenschutzerkl\w*|privacy policy)\b',
    unicode: true,
  );
  static final _export = RegExp(
    r'\b(datenexport|data export|exportieren|export)\b|\bcsv\b.{0,16}\bexport|\bexport\b.{0,12}\bcsv',
    unicode: true,
  );
  static final _delete = RegExp(
    r'\b(konto|account)\b.{0,24}\b(l(ö|oe)sch\w*|delete\w*|entfern\w*|remove\w*)\b|'
    r'\b(l(ö|oe)sch\w*|delete\w*|entfern\w*|remove\w*)\b.{0,24}\b(mein |my )?(konto|account)\b',
    unicode: true,
  );
  static final _ai = RegExp(
    r'\b((?:aus|ein)?schalt\w*|turn(?: off| on)?|switch(?: off| on)?|deaktiv\w*|aktivier\w*|enable|disable)\b.{0,30}\b(ki|ai|buddy mit ki|buddy with ai)\b|'
    r'\b(ki|ai|buddy mit ki|buddy with ai)\b.{0,20}\b(an|aus|ein|off|on|ausschalten|einschalten)\b|'
    r'\b(wo|where)\b.{0,24}\b(buddy mit ki|buddy with ai)\b',
    unicode: true,
  );
  static final _about = RegExp(
    r"^\s*(was ist|what is|what'?s|whats|wer ist|who is|who'?s)\s+(ahead|buddy)\b",
    unicode: true,
  );
  static final _signOut = RegExp(
    r'\b(abmelden|ausloggen|log ?out|sign ?out|melde( ich)? mich ab|log me out)\b',
    unicode: true,
  );
  static final _where = RegExp(
    r'\b(wo (ist|sind|finde ich|liegt|finde)|where (is|are)|where do i find|where can i find)\b',
    unicode: true,
  );

  static String? _topic(String q) {
    if (_passwordWord.hasMatch(q) && _passwordVerb.hasMatch(q)) return 'password';
    if (_account.hasMatch(q) &&
        !RegExp(r'\b(balance|saldo|stand|guthaben|overdraft|dispo)\b', unicode: true).hasMatch(q)) {
      return 'account';
    }
    if (_delete.hasMatch(q)) return 'delete';
    if (_export.hasMatch(q)) return 'export';
    if (_plus.hasMatch(q)) return 'plus';
    if (_privacy.hasMatch(q)) return 'privacy';
    if (_ai.hasMatch(q)) return 'ai';
    if (_signOut.hasMatch(q)) return 'signOut';
    if (_about.hasMatch(q) && !RegExp(r'\bplus\b', unicode: true).hasMatch(q)) return 'about';
    if (_where.hasMatch(q)) {
      if (RegExp(r'notgroschen|emergency fund|r(ü|ue)cklage', unicode: true).hasMatch(q)) return 'emergency';
      if (RegExp(r'vertr\w*|abo\b|abos\b|contract|subscription', unicode: true).hasMatch(q)) return 'contracts';
      if (RegExp(r'geteilt\w*|split\w*|shared expense', unicode: true).hasMatch(q)) return 'shared';
    }
    return null;
  }

  static Account? get _accountNow => AccountService.current.value;

  static String _first(Account a) {
    final name = a.name.trim();
    if (name.isEmpty) return '';
    return name.split(RegExp(r'\s+')).first;
  }

  static String _who(Account a) {
    final name = _first(a);
    final email = a.email.trim();
    if (name.isNotEmpty && email.isNotEmpty) return '**$name** ($email)';
    if (email.isNotEmpty) return '**$email**';
    if (name.isNotEmpty) return '**$name**';
    return '';
  }

  static String _text(String topic) {
    final a = _accountNow;
    switch (topic) {
      case 'password':
        return a == null
            ? tr('**Du bist nicht angemeldet.** Passwort ändern geht erst im Konto. Per E-Mail zurücksetzen geht nicht.\n\n'
                'Nächster Schritt: Profil › Konto erstellen, oder Anmelden. Danach Mein Konto › Sicherheit › Passwort ändern.')
            : tr('**Profil › Mein Konto › Sicherheit › Passwort ändern.** Per E-Mail zurücksetzen geht nicht.\n\n'
                'Nächster Schritt: Aktuelles Passwort eingeben, das neue zweimal.');
      case 'account':
        if (a == null) {
          return tr('**Du bist nicht angemeldet.** Einen Namen und eine E-Mail gibt es erst mit Konto.\n\n'
              'Nächster Schritt: Profil › Konto erstellen, oder Anmelden.');
        }
        final name = _first(a);
        final email = a.email.trim();
        if (name.isNotEmpty && email.isNotEmpty) {
          return tr('**{name}**, E-Mail **{email}**.\n\n'
              'Nächster Schritt: Profil › Mein Konto, dort änderst du Name und E-Mail.', {'name': name, 'email': email});
        }
        if (email.isNotEmpty) {
          return tr('**{email}**.\n\nNächster Schritt: Profil › Mein Konto, dort änderst du die E-Mail.', {'email': email});
        }
        if (name.isNotEmpty) {
          return tr('**{name}**.\n\nNächster Schritt: Profil › Mein Konto, dort änderst du den Namen.', {'name': name});
        }
        return tr('**Angemeldet, ohne Namen und E-Mail im Profil.**\n\nNächster Schritt: Profil › Mein Konto.');
      case 'plus':
        return tr('**Profil**, die Karte **Ahead Plus**. Läuft Plus schon, steht dort Mein Abo.\n\n'
            'Nächster Schritt: Tippe die Karte.');
      case 'privacy':
        return tr('**Profil › Privatsphäre & KI › Wo deine Daten liegen.** Die Erklärung findest du unter Profil › Ahead › Unternehmen & Vertrauen › Datenschutzerklärung.\n\n'
            'Nächster Schritt: Öffne Wo deine Daten liegen.');
      case 'export':
        return tr('**Profil › Erweitert › Import, Export & Backup › Als CSV exportieren.**\n\n'
            'Nächster Schritt: Erweitert aufklappen, dann Als CSV exportieren.');
      case 'delete':
        return a == null
            ? tr('**Du bist nicht angemeldet.** Hier gibt es kein Konto zum Löschen.\n\n'
                'Nächster Schritt: Profil › Konto erstellen, oder Anmelden, falls das Konto noch woanders besteht.')
            : tr('**Profil › Mein Konto › Konto löschen.** Das löscht das Konto endgültig.\n\n'
                'Nächster Schritt: Mein Konto öffnen und unten Konto löschen tippen.');
      case 'ai':
        return tr('**Profil › Privatsphäre & KI**, Schalter **Ahead mit KI**. An gehen Fragen an die KI, aus bleiben einfache Fragen auf dem Gerät.\n\n'
            'Nächster Schritt: Schalter umlegen.');
      case 'about':
        return tr('**Ahead** ist diese App, **Ahead** der Coach darin. Er rechnet mit deinen Zahlen und nennt den nächsten Schritt. Gespeichert wird erst, wenn du Übernehmen tippst.\n\n'
            'Nächster Schritt: Frag, was diesen Monat noch frei ist.');
      case 'signOut':
        if (a == null) {
          return tr('**Du bist schon abgemeldet.**\n\nNächster Schritt: Profil › Konto erstellen, oder Anmelden.');
        }
        final who = _who(a);
        if (who.isEmpty) {
          return tr('**Profil › Mein Konto › Abmelden.** Auch unter Profil › Erweitert.\n\n'
              'Nächster Schritt: Mein Konto öffnen und Abmelden tippen.');
        }
        return tr('**Profil › Mein Konto › Abmelden.** Angemeldet als {who}. Auch unter Profil › Erweitert.\n\n'
            'Nächster Schritt: Mein Konto öffnen und Abmelden tippen.', {'who': who});
      case 'emergency':
        return tr('**Profil › Erweitert › Vermögen & Absicherung**, Abschnitt Notgroschen. Als Sparziel: Profil › Planen › Sparziele.\n\n'
            'Nächster Schritt: Erweitert aufklappen.');
      case 'contracts':
        return tr('**Profil › Planen › Verträge & Abos.**\n\nNächster Schritt: Dort siehst du die erkannten Abos.');
      case 'shared':
        return tr('**Profil › Planen › Geteilte Ausgaben.**\n\nNächster Schritt: Dort steht, wer wem was schuldet.');
      default:
        return '';
    }
  }
}
