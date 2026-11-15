// Where each kind of data lives and who can read it, as one list the app
// shows and Buddy answers from, so it never says anything the privacy policy
// does not. Each entry names the section of the policy it rests on, and a
// test checks that the facts named here (providers, encryption, periods)
// also stand in the policy. What is switched on is read from the app itself.
import '../l10n/l10n.dart';

// what is on for this person right now
class DataStatus {
  final bool signedIn;
  final bool bankLinked;
  final bool depotLinked;
  final bool aiConsent;
  final String aiProvider; // anthropic or google
  final bool plus;
  final bool holdings;
  final int memories; // things Buddy was allowed to keep
  const DataStatus({
    this.signedIn = false,
    this.bankLinked = false,
    this.depotLinked = false,
    this.aiConsent = false,
    this.aiProvider = 'anthropic',
    this.plus = false,
    this.holdings = false,
    this.memories = 0,
  });
}

enum DataPlace { device, ourServer, provider }

class DataFlow {
  final String id;
  final String what; // which data
  final DataPlace place;
  final String where; // where it lives or goes
  final String who; // who can read it
  final String end; // how to stop it or delete it
  final String section; // section of the privacy policy
  final List<String> facts; // names and numbers that must also stand in the policy
  final bool active; // on for this person now
  final bool optional; // only when a feature is used
  const DataFlow({
    required this.id,
    required this.what,
    required this.place,
    required this.where,
    required this.who,
    required this.end,
    required this.section,
    this.facts = const [],
    required this.active,
    this.optional = true,
  });
}

class DataMap {
  static List<DataFlow> flows(DataStatus s) {
    final google = s.aiProvider == 'google';
    return [
      DataFlow(
        id: 'device',
        what: tr('Umsätze, Budgets, Sparziele, Verträge, Depot, Einstellungen'),
        place: DataPlace.device,
        where: tr('Nur auf diesem Gerät, im geschützten Speicher der App'),
        who: tr('Nur du. Wir haben keinen Zugriff.'),
        end: tr('Profil › Erweitert › App zurücksetzen, oder die App löschen'),
        section: '2',
        active: true,
        optional: false,
      ),
      DataFlow(
        id: 'account',
        what: tr('Name, E-Mail, Passwort'),
        place: DataPlace.ourServer,
        where: tr('Unser Server. Das Passwort nur als Hash (bcrypt), nicht lesbar.'),
        who: tr('Wir, um dein Konto zu führen. Das Passwort kennt niemand außer dir.'),
        end: tr('Profil › Mein Konto › Konto löschen'),
        section: '3',
        facts: const ['bcrypt'],
        active: s.signedIn,
      ),
      DataFlow(
        id: 'copy',
        what: tr('Kopie deiner Umsätze, Budgets, Ziele, Splits, Depot-Positionen und was Buddy sich merken darf'),
        place: DataPlace.ourServer,
        where: tr('Unser Server, vorher auf deinem Gerät verschlüsselt (AES-256) mit einem Schlüssel aus deinem Passwort'),
        who: tr('Nur du. Wir sehen nur verschlüsselten Text und können ihn nicht öffnen.'),
        end: tr('Wird mit dem Konto gelöscht'),
        section: '3',
        facts: const ['AES-256'],
        active: s.signedIn,
      ),
      DataFlow(
        id: 'bank',
        what: tr('Kontostand und Umsätze deines Girokontos'),
        place: DataPlace.provider,
        where: tr('Enable Banking Oy (Finnland), zugelassener Kontoinformationsdienst nach PSD2'),
        who: tr('Enable Banking leitet sie an die App weiter. Deine Bank-Zugangsdaten sehen weder wir noch die App.'),
        end: tr('Gilt höchstens 180 Tage. Trennen unter Profil › Banken & Depots oder bei deiner Bank.'),
        section: '4',
        facts: const ['Enable Banking', '180 Tage', 'PSD2'],
        active: s.bankLinked,
      ),
      DataFlow(
        id: 'depot',
        what: tr('Depot-Positionen, Stückzahlen und Kurse, nur lesend'),
        place: DataPlace.provider,
        where: tr('Parqet Fintech GmbH (Deutschland)'),
        who: tr('Parqet gibt sie an die App. Deine Zugangsdaten sehen weder wir noch die App.'),
        end: tr('Trennen unter Profil › Banken & Depots oder bei Parqet unter Integrationen'),
        section: '4',
        facts: const ['Parqet'],
        active: s.depotLinked,
      ),
      DataFlow(
        id: 'ai',
        what: tr('Deine Frage und eine Zusammenfassung deiner Finanzen, ohne Kontonummern'),
        place: DataPlace.provider,
        where: google
            ? tr('Google (Gemini) erzeugt die Antwort')
            : tr('Anthropic, PBC (USA) erzeugt die Antwort mit Claude'),
        who: google
            ? tr('Google, um zu antworten. Im kostenlosen Gemini-Tarif kann Google sie zur Verbesserung nutzen.')
            : tr('Anthropic, nur um zu antworten. Laut Vertrag nicht zum Training.'),
        end: tr('Schalter „Buddy mit KI“ unter Profil › Privatsphäre & KI. Einfache Fragen beantwortet Buddy dann auf dem Gerät.'),
        section: '5',
        facts: google ? const ['Gemini', 'Google'] : const ['Anthropic', 'Training'],
        active: s.signedIn && s.aiConsent,
      ),
      DataFlow(
        id: 'memory',
        what: s.memories > 0
            ? tr('{n} Dinge, die Buddy sich merken darf', {'n': s.memories})
            : tr('Was Buddy sich merken darf'),
        place: DataPlace.device,
        where: tr('Auf dem Gerät und in deiner verschlüsselten Kopie. Geht mit jeder Buddy-Frage mit.'),
        who: tr('Du, und der KI-Anbieter für die Antwort'),
        end: tr('Profil › Was Buddy weiß'),
        section: '5',
        facts: const ['Was Buddy weiß'],
        active: s.memories > 0,
      ),
      DataFlow(
        id: 'journal',
        what: tr('Kurze Notizen zu deinen letzten Fragen und Werte geprüfter Gehaltsabrechnungen (ohne Foto)'),
        place: DataPlace.device,
        where: tr('Nur auf diesem Gerät, Notizen 60 Tage lang'),
        who: tr('Nur du. Die letzten Notizen gehen als Kontext mit an den KI-Anbieter.'),
        end: tr('Profil › Was Buddy weiß › Alles vergessen'),
        section: '5',
        facts: const ['60 Tage', 'Gehaltsabrechnung'],
        active: true,
        optional: false,
      ),
      DataFlow(
        id: 'feedback',
        what: tr('Frage, Antwort und Grund, wenn du eine Antwort bewertest'),
        place: DataPlace.ourServer,
        where: tr('Unser Server, ohne deinen Namen'),
        who: tr('Wir, um Buddy zu verbessern. Nicht zum Training von KI-Modellen.'),
        end: tr('Schreib uns, dann löschen wir es'),
        section: '5',
        facts: const ['Daumen'],
        active: false,
      ),
      DataFlow(
        id: 'payment',
        what: tr('Zahlungsdaten für Plus'),
        place: DataPlace.provider,
        where: tr('Apple (App Store), Google Play oder Stripe (Irland), je nachdem wo du kaufst'),
        who: tr('Nur der Zahlungsanbieter. Wir sehen nur, ob Plus aktiv ist, und eine gekürzte Zahlungsart.'),
        end: tr('Kündigen im Store oder unter Profil › Mein Abo'),
        section: '7',
        facts: const ['Stripe', 'App Store', 'Google Play'],
        active: s.plus,
      ),
      DataFlow(
        id: 'prices',
        what: tr('Börsenkürzel für aktuelle Kurse'),
        place: DataPlace.provider,
        where: tr('Yahoo Finance über unseren Server, Krypto direkt bei CoinGecko'),
        who: tr('Nur das Kürzel, keine Angaben zu deinem Depot. CoinGecko sieht deine IP-Adresse.'),
        end: tr('Keine Positionen im Depot, keine Abfrage'),
        section: '6',
        facts: const ['Yahoo Finance', 'CoinGecko'],
        active: s.holdings,
      ),
      DataFlow(
        id: 'whatsapp',
        what: tr('Wochenbericht und Erinnerungen per WhatsApp'),
        place: DataPlace.provider,
        where: tr('Meta (WhatsApp). Unser Server speichert nur einen Hash deiner Nummer.'),
        who: tr('Meta stellt die Nachricht zu'),
        end: tr('Profil › Mitteilungen, oder „Stop“ in WhatsApp'),
        section: '8',
        facts: const ['WhatsApp', 'Meta', 'Hash'],
        active: false,
      ),
      DataFlow(
        id: 'voice',
        what: tr('Deine Sprache, wenn du mit Buddy sprichst'),
        place: DataPlace.provider,
        where: tr('Die Spracherkennung deines Geräts, je nach System beim Hersteller (Apple oder Google)'),
        who: tr('Der Hersteller wandelt sie in Text um, wir bekommen nur den Text'),
        end: tr('Einfach tippen statt sprechen'),
        section: '5',
        facts: const ['Spracherkennung'],
        active: false,
      ),
    ];
  }

  static final _ask = RegExp(
      r'wer (hat|kann).{0,30}(zugriff|daten|sehen|lesen)|wo (liegen|sind|landen|speicher).{0,20}(daten|meine)|'
      r'(datenschutz|meine daten|privatsph[äa]re)\b|was (passiert|geschieht) mit meinen daten|'
      r'who (has|can).{0,30}(access|see|read).{0,20}data|where (is|are) my data|privacy|what happens to my data',
      caseSensitive: false);

  static bool matches(String question) => _ask.hasMatch(question);

  // Buddy's answer, built only from the list above: no guessing about privacy
  static String answer(DataStatus s) {
    final all = flows(s);
    final on = all.where((f) => f.active).toList();
    final off = all.where((f) => !f.active && f.optional).toList();
    final lines = [
      for (final f in on) '- **${f.what}**: ${f.where}. ${f.who}',
    ];
    return [
      tr('**Hier liegen deine Daten gerade, und wer sie lesen kann:**'),
      lines.join('\n'),
      if (off.isNotEmpty)
        tr('Aus oder nicht genutzt: {x}.', {'x': off.map((f) => f.what).join('; ')}),
      tr('Wir zeigen keine Werbung, nutzen kein Tracking und verkaufen keine Daten. Alles im Detail unter Profil › Wo deine Daten liegen.'),
      tr('Nächster Schritt: Schau dir die Übersicht an und schalte ab, was du nicht brauchst.'),
    ].join('\n\n');
  }
}
