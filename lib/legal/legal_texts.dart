// The legal pages shown under "Über BudgetBuddy". They describe how this
// app actually works (local data, account server, bank access via Enable
// Banking, Buddy via Anthropic, market data, store payments) and should be
// reviewed by a lawyer before the app is published.
import 'legal_info.dart';

class LegalSection {
  final String heading;
  final String body; // paragraphs separated by blank lines
  const LegalSection(this.heading, this.body);
}

class LegalDoc {
  final String title;
  final List<LegalSection> sections;
  const LegalDoc(this.title, this.sections);
}

class LegalTexts {
  static String get _contact => '${LegalInfo.provider}\n${LegalInfo.address}\n'
      'E-Mail: ${LegalInfo.email}${LegalInfo.phone.isEmpty ? '' : '\nTelefon: ${LegalInfo.phone}'}';

  static LegalDoc get imprint => LegalDoc('Impressum', [
        LegalSection('Angaben gemäß § 5 DDG', _contact),
        if (LegalInfo.representative.isNotEmpty) LegalSection('Vertreten durch', LegalInfo.representative),
        if (LegalInfo.register.isNotEmpty) LegalSection('Registereintrag', LegalInfo.register),
        if (LegalInfo.vatId.isNotEmpty)
          LegalSection('Umsatzsteuer-ID', 'Umsatzsteuer-Identifikationsnummer gemäß § 27a UStG: ${LegalInfo.vatId}'),
        LegalSection('Verantwortlich für den Inhalt gemäß § 18 Abs. 2 MStV',
            '${LegalInfo.responsible}\n${LegalInfo.address}'),
        const LegalSection(
            'Verbraucherstreitbeilegung',
            'Wir sind nicht bereit und nicht verpflichtet, an Streitbeilegungsverfahren vor einer '
                'Verbraucherschlichtungsstelle teilzunehmen. Bei Fragen oder Problemen schreib uns einfach, '
                'wir finden eine Lösung.'),
        const LegalSection(
            'Haftung für Inhalte',
            'Wir erstellen die Inhalte dieser App mit großer Sorgfalt. Für die Richtigkeit, Vollständigkeit '
                'und Aktualität von Kursdaten, automatisch erkannten Verträgen und Antworten von Buddy können '
                'wir jedoch keine Gewähr übernehmen. Sie ersetzen keine Beratung.'),
      ]);

  static LegalDoc get privacy => LegalDoc('Datenschutzerklärung', [
        LegalSection(
            'Auf einen Blick',
            'BudgetBuddy ist so gebaut, dass nur du deine Finanzdaten lesen kannst. Umsätze, Budgets, '
                'Depot und Sparziele werden auf deinem Gerät gespeichert. Mit einem Nutzerkonto liegt zusätzlich '
                'eine Kopie bei uns, die schon auf deinem Gerät mit deinem Passwort verschlüsselt wird: Wir können '
                'sie nicht lesen. Andere Daten verlassen dein Gerät nur, wenn du eine Funktion nutzt, die das '
                'braucht, etwa die Bankverbindung oder Buddy. '
                'Wir zeigen keine Werbung, nutzen kein Tracking und verkaufen keine Daten.\n\n'
                'Stand: ${LegalInfo.updated}'),
        LegalSection('1. Verantwortlicher', _contact),
        const LegalSection(
            '2. Daten auf deinem Gerät',
            'Deine Umsätze, Budgets, Depot-Positionen, Sparziele, Verträge und Einstellungen speichert die App '
                'im geschützten Speicher deines Geräts. Wir haben darauf keinen Zugriff. Exporte und Backups '
                'erstellst nur du selbst. Beim Löschen der App oder über „App zurücksetzen“ werden diese Daten '
                'entfernt.'),
        const LegalSection(
            '3. Nutzerkonto',
            'Für ein Konto verarbeiten wir deinen Namen, deine E-Mail-Adresse und dein Passwort. Das Passwort '
                'speichern wir nur als sicheren Hash (bcrypt), Anmelde-Sitzungen nur als Prüfsumme. '
                'Rechtsgrundlage ist Art. 6 Abs. 1 lit. b DSGVO (Vertrag). Die Daten werden gelöscht, sobald '
                'du dein Konto löschst. Gast-Nutzung ist ohne Konto möglich.\n\n'
                'Damit deine Daten nach der Anmeldung auf jedem Gerät da sind, speichern wir eine Kopie deiner '
                'Umsätze, Budgets, Ziele, geteilten Ausgaben, Depot-Positionen und der Bank- und Depotverbindung. '
                'Die App verschlüsselt sie vor dem Hochladen (AES-256) mit einem Schlüssel, der aus deinem Passwort '
                'entsteht und dein Gerät nie verlässt. Wir speichern nur den verschlüsselten Text und können ihn '
                'nicht öffnen. Deshalb kann auch niemand die Kopie wiederherstellen, wenn du dein Passwort vergisst. '
                'Mit dem Konto wird auch die Kopie gelöscht.'),
        const LegalSection(
            '4. Bank- und Depotverbindung',
            'Wenn du dein Girokonto verbindest, läuft der Zugriff über Enable Banking Oy (Otaniemi, Finnland), '
                'einen nach der Zahlungsdiensterichtlinie (PSD2) zugelassenen Kontoinformationsdienst. Du '
                'bestätigst den Zugriff direkt bei deiner Bank; deine Zugangsdaten sehen weder wir noch die App. '
                'Übertragen werden Kontostand und Umsätze, um sie in der App anzuzeigen. Die Zustimmung gilt '
                'höchstens 180 Tage und kann jederzeit in der App oder bei deiner Bank beendet werden. '
                'Rechtsgrundlage ist Art. 6 Abs. 1 lit. b DSGVO.\n\n'
                'Verbindest du dein Depot, läuft der Zugriff über Parqet (Parqet Fintech GmbH, Deutschland), '
                'wo du dein Depot selbst angebunden hast. Du erlaubst den Zugriff direkt bei Parqet; deine '
                'Zugangsdaten bei Parqet oder deinem Broker sehen weder wir noch die App. Übertragen werden '
                'Positionen, Stückzahlen, Kaufkurse und aktuelle Kurse, nur lesend. Du kannst die Freigabe '
                'jederzeit in der App oder bei Parqet unter Integrationen beenden. Rechtsgrundlage ist '
                'Art. 6 Abs. 1 lit. b DSGVO.'),
        const LegalSection(
            '5. Buddy (KI-Assistent) und Belegscan',
            'Stellst du Buddy eine Frage oder scannst einen Beleg, senden wir deine Frage bzw. das Foto und '
                'eine zusammengefasste Übersicht deiner Finanzen (z. B. Summen je Kategorie) an Anthropic, PBC '
                '(San Francisco, USA), die das KI-Modell Claude betreibt. Anthropic verarbeitet die Daten in '
                'unserem Auftrag, um die Antwort zu erzeugen, und verwendet sie laut Vertrag nicht zum Training. '
                'Die Übermittlung in die USA stützt sich auf das EU-US Data Privacy Framework bzw. '
                'Standardvertragsklauseln (Art. 45, 46 DSGVO). Rechtsgrundlage ist Art. 6 Abs. 1 lit. b DSGVO. '
                'Einfache Fragen beantwortet Buddy direkt auf deinem Gerät, ohne Übertragung. '
                'Ist statt Claude das KI-Modell Gemini von Google eingerichtet, gehen dieselben Daten an Google; '
                'im kostenlosen Gemini-Tarif kann Google sie zur Verbesserung seiner Dienste verwenden. Buddy '
                'nennt vor deiner ersten Frage, welcher Anbieter antwortet.'),
        const LegalSection(
            '6. Kurse und Marktdaten',
            'Für aktuelle Kurse fragt die App öffentliche Marktdaten ab: Aktien und ETFs über unseren Server '
                'bei Yahoo Finance, Kryptowährungen direkt bei CoinGecko. Dabei werden nur Börsenkürzel '
                'übertragen, keine Angaben zu deinem Depot. Bei der direkten Abfrage erhält CoinGecko technisch '
                'bedingt deine IP-Adresse. Rechtsgrundlage ist Art. 6 Abs. 1 lit. f DSGVO (berechtigtes '
                'Interesse an aktuellen Kursen).'),
        const LegalSection(
            '7. BudgetBuddy Plus und Zahlungen',
            'Plus kaufst du über den App Store von Apple, Google Play oder im Web über Stripe (Stripe Payments '
                'Europe Ltd., Dublin, Irland). Die Zahlungsdaten gibst du direkt auf der Zahlungsseite des '
                'Anbieters ein; er verarbeitet sie in eigener Verantwortung. Wir erhalten nur, ob und welches '
                'Abo aktiv ist, bis wann es läuft und eine gekürzte Angabe der Zahlungsart (z. B. „Visa •••• '
                '4242“), damit du sie in der App siehst. Rechtsgrundlage ist Art. 6 Abs. 1 lit. b DSGVO; '
                'steuerrechtliche Aufbewahrungspflichten (bis zu zehn Jahre) bleiben unberührt.'),
        const LegalSection(
            '8. Mitteilungen',
            'Erinnerungen und Hinweise plant die App auf deinem Gerät. Es gibt keinen Push-Server, der deine '
                'Daten dafür erhält. Mitteilungen kannst du jederzeit im Profil oder in den Systemeinstellungen '
                'abschalten.'),
        const LegalSection(
            '9. Server und Sicherheit',
            'Beim Aufruf unseres Servers werden technisch notwendige Daten wie IP-Adresse und Zeitpunkt kurz '
                'verarbeitet, um die Verbindung herzustellen und Missbrauch abzuwehren (Art. 6 Abs. 1 lit. f '
                'DSGVO). Die Übertragung ist verschlüsselt. Geheime Schlüssel liegen nur auf dem Server, nie in '
                'der App.'),
        LegalSection(
            '10. Deine Rechte',
            'Du hast das Recht auf Auskunft (Art. 15 DSGVO), Berichtigung (Art. 16), Löschung (Art. 17), '
                'Einschränkung der Verarbeitung (Art. 18), Datenübertragbarkeit (Art. 20) und Widerspruch '
                '(Art. 21). Eine erteilte Einwilligung kannst du jederzeit widerrufen. Vieles geht direkt in der '
                'App: Daten exportieren, Konto ändern oder löschen, Bankverbindung trennen. Für alles andere '
                'schreib an ${LegalInfo.email}.\n\n'
                'Du kannst dich außerdem bei einer Datenschutz-Aufsichtsbehörde beschweren, zum Beispiel bei '
                '${LegalInfo.authority}.'),
      ]);

  static LegalDoc get terms => LegalDoc('Nutzungsbedingungen', [
        LegalSection(
            '1. Geltung',
            'Diese Bedingungen gelten für die Nutzung der App BudgetBuddy, angeboten von ${LegalInfo.provider}. '
                'Stand: ${LegalInfo.updated}.'),
        const LegalSection(
            '2. Was BudgetBuddy ist',
            'BudgetBuddy hilft dir, Einnahmen, Ausgaben, Budgets, Verträge, Sparziele und dein Depot im Blick '
                'zu behalten. BudgetBuddy ist keine Bank, führt keine Zahlungen aus und bietet keine Anlage-, '
                'Steuer- oder Rechtsberatung. Antworten von Buddy werden von einer KI erzeugt und können Fehler '
                'enthalten; triff wichtige Entscheidungen bitte nicht allein auf ihrer Grundlage.'),
        const LegalSection(
            '3. Konto',
            'Du kannst die App als Gast oder mit Konto nutzen. Halte dein Passwort geheim und sag uns Bescheid, '
                'wenn du einen Missbrauch vermutest. Du kannst dein Konto jederzeit in der App löschen.'),
        LegalSection(
            '4. BudgetBuddy Plus',
            'Die Grundfunktionen sind kostenlos. Plus erweitert die App gegen eine Gebühr von derzeit '
                '4,99 € im Monat oder 39,99 € im Jahr, jeweils inklusive Umsatzsteuer. Neue Abonnenten können '
                'Plus 7 Tage kostenlos testen; kündigst du während des Tests, entstehen keine Kosten.\n\n'
                'Das Abo verlängert sich automatisch um die gewählte Laufzeit, wenn du es nicht vorher kündigst. '
                'Kündigen kannst du jederzeit zum Ende der laufenden Laufzeit, in der App unter Profil › Mein Abo '
                'oder, bei Kauf im App Store bzw. bei Google Play, in deren Kontoeinstellungen. Dort gelten '
                'ergänzend die Bedingungen des jeweiligen Stores.\n\n'
                'Preisänderungen teilen wir dir rechtzeitig vorher mit; sie gelten erst ab der nächsten Laufzeit.'),
        const LegalSection(
            '5. Verfügbarkeit',
            'Wir bemühen uns um einen störungsfreien Betrieb. Bankverbindung, Kursdaten und Buddy hängen auch von '
                'Diensten Dritter ab und können vorübergehend nicht verfügbar sein.'),
        const LegalSection(
            '6. Haftung',
            'Wir haften unbeschränkt bei Vorsatz und grober Fahrlässigkeit, bei Verletzung von Leben, Körper oder '
                'Gesundheit sowie nach dem Produkthaftungsgesetz. Bei leicht fahrlässiger Verletzung wesentlicher '
                'Vertragspflichten ist die Haftung auf den vorhersehbaren, typischerweise eintretenden Schaden '
                'begrenzt. Im Übrigen ist die Haftung bei leichter Fahrlässigkeit ausgeschlossen.'),
        const LegalSection(
            '7. Änderungen',
            'Wir können diese Bedingungen anpassen, wenn es dafür einen sachlichen Grund gibt, etwa neue '
                'Funktionen oder geänderte Gesetze. Über wesentliche Änderungen informieren wir dich vorher in '
                'der App.'),
        const LegalSection(
            '8. Schluss',
            'Es gilt deutsches Recht. Zwingende Verbraucherschutzvorschriften deines Wohnsitzlandes bleiben '
                'unberührt.'),
      ]);

  static LegalDoc get withdrawal => LegalDoc('Widerrufsbelehrung', [
        const LegalSection(
            'Widerrufsrecht',
            'Du hast das Recht, binnen vierzehn Tagen ohne Angabe von Gründen diesen Vertrag zu widerrufen. '
                'Die Widerrufsfrist beträgt vierzehn Tage ab dem Tag des Vertragsabschlusses.'),
        LegalSection(
            'Ausübung',
            'Um dein Widerrufsrecht auszuüben, musst du uns (${LegalInfo.provider}, ${LegalInfo.street}, '
                '${LegalInfo.city}, E-Mail: ${LegalInfo.email}) mittels einer eindeutigen Erklärung über deinen '
                'Entschluss informieren, diesen Vertrag zu widerrufen. Am einfachsten geht das in der App unter '
                'Profil › Mein Abo › „Vertrag widerrufen“. Du kannst dafür auch das Muster-Widerrufsformular '
                'unten verwenden, das jedoch nicht vorgeschrieben ist.\n\n'
                'Zur Wahrung der Widerrufsfrist reicht es aus, dass du die Mitteilung über die Ausübung des '
                'Widerrufsrechts vor Ablauf der Widerrufsfrist absendest. Bei Käufen über den App Store oder '
                'Google Play erfolgt die Erstattung über den jeweiligen Store.'),
        const LegalSection(
            'Folgen des Widerrufs',
            'Wenn du diesen Vertrag widerrufst, haben wir dir alle Zahlungen, die wir von dir erhalten haben, '
                'unverzüglich und spätestens binnen vierzehn Tagen ab dem Tag zurückzuzahlen, an dem die '
                'Mitteilung über deinen Widerruf bei uns eingegangen ist. Für die Rückzahlung verwenden wir '
                'dasselbe Zahlungsmittel, das du bei der ursprünglichen Transaktion eingesetzt hast, es sei denn, '
                'mit dir wurde ausdrücklich etwas anderes vereinbart; in keinem Fall werden dir wegen dieser '
                'Rückzahlung Entgelte berechnet.\n\n'
                'Hast du verlangt, dass die Dienstleistung während der Widerrufsfrist beginnen soll, so hast du '
                'uns einen angemessenen Betrag zu zahlen, der dem Anteil der bis zum Widerruf bereits erbrachten '
                'Dienstleistungen im Vergleich zum Gesamtumfang der im Vertrag vorgesehenen Dienstleistungen '
                'entspricht. Während des kostenlosen Tests fallen dafür keine Kosten an.'),
        LegalSection(
            'Muster-Widerrufsformular',
            'Wenn du den Vertrag widerrufen willst, fülle bitte dieses Formular aus und sende es zurück.\n\n'
                'An: ${LegalInfo.provider}, ${LegalInfo.street}, ${LegalInfo.city}, ${LegalInfo.email}\n\n'
                'Hiermit widerrufe(n) ich/wir (*) den von mir/uns (*) abgeschlossenen Vertrag über die Erbringung '
                'der folgenden Dienstleistung: BudgetBuddy Plus\n\n'
                'Bestellt am (*) / erhalten am (*)\n'
                'Name des/der Verbraucher(s)\n'
                'Anschrift des/der Verbraucher(s)\n'
                'Unterschrift des/der Verbraucher(s) (nur bei Mitteilung auf Papier)\n'
                'Datum\n\n'
                '(*) Unzutreffendes streichen.'),
      ]);

  static const notes = LegalDoc('Wichtige Hinweise', [
    LegalSection(
        'Keine Anlageberatung',
        'Depotwerte, Kursverläufe und Auswertungen dienen nur deiner Übersicht. Sie sind keine Empfehlung '
            'zum Kauf oder Verkauf von Wertpapieren oder Kryptowährungen. Investitionen sind mit Risiken '
            'verbunden, bis hin zum Totalverlust.'),
    LegalSection(
        'Kursdaten',
        'Kurse können verzögert, unvollständig oder fehlerhaft sein und werden ohne Gewähr angezeigt. '
            'Maßgeblich sind die Angaben deiner Bank bzw. deines Brokers.'),
    LegalSection(
        'Buddy ist eine KI',
        'Buddy rechnet mit deinen Daten und formuliert Antworten mit Hilfe eines KI-Modells. Das ist '
            'praktisch, aber nicht unfehlbar. Prüfe Zahlen, bevor du wichtige Entscheidungen triffst. Für '
            'Steuer- oder Rechtsfragen wende dich an eine Fachperson.'),
    LegalSection(
        'Automatische Erkennung',
        'Verträge, Kategorien und Hinweise erkennt BudgetBuddy automatisch aus deinen Umsätzen. Das klappt '
            'meistens, aber nicht immer. Du kannst alles jederzeit selbst korrigieren.'),
    LegalSection(
        'Sicherheit',
        'Schütze dein Gerät mit einer Sperre und aktiviere die App-Sperre im Profil. Wir fragen dich nie '
            'nach deinen Bank-Zugangsdaten, weder per E-Mail noch in der App.'),
  ]);
}
