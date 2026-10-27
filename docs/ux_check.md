# UX-Check BudgetBuddy (26.10.2026)

Alle 29 Screens, geprüft im Code (4 parallele Durchgänge) und im Browser
(Handy-Größe, Beispieldaten). Kriterien: stimmen die Zahlen, ist es klar,
gibt es Leer-/Lade-/Fehlerzustände, Bedienung, Barrierefreiheit, Tempo,
durchdachte Produktlogik.

**P0** = falsch, kaputt, Datenverlust, Vertrauens- oder Store-Risiko ·
**P1** = verwirrend oder deutlich schlechter · **P2** = Feinschliff.
Status: ✅ behoben · ⏳ offen · 🧑 braucht dich (Entscheidung, Zugang, Gerät)

## P0

| # | Bereich | Befund | Status |
|---|---|---|---|
| 1 | ganze App | Keine deutsche Lokalisierung: Datumswähler „Select date / Cancel“, Woche ab Sonntag, Tooltips englisch | ✅ |
| 2 | Start | Budget-Ring mit Limit 0 → Division durch 0 → ganze Startseite stürzt ab | ✅ |
| 3 | Budgets | Jeder Monat legt ein neues Budget an, die Liste zeigt alle Monate („Lebensmittel“ 3×); altes wegwischen stoppt das aktuelle | ✅ |
| 4 | Verträge | Preiserhöhung > 15 % lässt den Vertrag verschwinden statt „teurer geworden“ zu melden | ✅ |
| 5 | Verträge | „Kopieren“/Mail-App öffnen markiert sofort „Gekündigt“, obwohl nichts verschickt wurde | ✅ |
| 6 | Daueraufträge | Nach Pause fortsetzen bucht alle verpassten Termine nach | ✅ |
| 7 | Umsätze | Bank-Buchungen lassen sich wegwischen und kommen beim nächsten Sync zurück | ✅ |
| 8 | Privatsphäre | „Beträge verbergen“ wirkt nicht in Analyse und Budgets (bleiben sichtbar) | ✅ |
| 9 | Erfassen | Zukunftsdaten erlaubt → Kontostand, Diagramm und „Letzte Umsätze“ widersprechen sich | ✅ (keine Zukunftsdaten mehr) |
| 10 | Schnell erfassen | Nach „Speichern“ kann die KI Betrag/Kategorie noch ändern | ✅ |
| 11 | Depot | Position löschen schließt vermutlich zwei Screens (schwarzer Bildschirm) | ✅ |
| 12 | Depot | Bearbeiten rundet die Stückzahl auf 4 Stellen (0,123456 BTC → 0,1235) | ✅ |
| 13 | Depot | Kurse unter 1 Cent (HBAR, DOGE) werden auf ganze Cent gerundet | ✅ |
| 14 | Depot | Kurse ohne Datum/Quelle; Referenzkurse wirken wie aktuelle | ✅ |
| 15 | Depot | USD-Kurs wird als EUR gezeigt, wenn der Wechselkurs fehlt | ✅ |
| 16 | Geteilt | Gruppe löschen/verlassen ohne Rückfrage; Server-Fehler wird verschluckt | ✅ |
| 17 | Geteilt | Ausgabe wegwischen ohne Rückgängig; offline bleibt eine „Geister-Zeile“ | ✅ |
| 18 | Sparziele | Automatik übernimmt den Vorschlag als echten Betrag und bucht ihn sofort | ✅ |
| 19 | Beispieldaten | Nicht markiert und nicht entfernbar → mischen sich mit echten Daten | ✅ |
| 20 | Start | Kontostand unbekannt: Konto-Zeile zeigt trotzdem eine sinnlose Summe | ✅ |
| 21 | App-Sperre | Sperre/Sichtschutz liegen unter geöffneten Unterseiten | ✅ |
| 22 | Abmelden | Daten bleiben ohne Anmeldung sichtbar, obwohl der Dialog Schutz verspricht | ✅ |
| 23 | Registrieren | In-App-Registrierung kann Beispieldaten in echte Daten mischen | ✅ |
| 24 | Anmelden | Kein „Passwort vergessen“ | 🧑 (braucht E-Mail-Versand) |
| 25 | Checkout Web | Lokaler Testmodus schaltet Plus gratis frei und fragt echte Kartendaten ab | ✅ |
| 26 | Verbindungen | Entwickler-Hinweise („cd backend && dart run server.dart“) für Endnutzer | ✅ |
| 27 | Rechtliches | Platzhalter in Impressum/Support würden ohne Warnung ausgeliefert | 🧑 (deine Angaben) |

## P1

| # | Bereich | Befund | Status |
|---|---|---|---|
| 28 | Start | Drei Zeitbegriffe auf einem Screen (30 Tage / Kalendermonat / gesamt) | ✅ |
| 29 | Prognose | „Noch frei“: Gehalt am Monatsende zählt 1,5×; Tempo durch 60 Tage geteilt auch bei kurzer Historie; nicht durch Kontostand begrenzt; Ziele ohne Datum zählen 0 € | ✅ (Ziele ohne Datum zählen bewusst nicht) |
| 30 | Analyse | Rundung Legende 5 % vs. Liste 4,5 %; Ausgaben in Alarm-Rot | ✅ |
| 31 | Rückblick | „Am meisten ging an …“ ignoriert Miete ohne es zu sagen | ✅ |
| 32 | Rückblick/Wochenbericht | Nach einmal Ansehen nicht mehr erreichbar | ✅ |
| 33 | Erfassen | Löschen ohne Rückgängig, danach leere Seite | ✅ |
| 34 | Erfassen | Tastatur für Beschreibung lässt den Screen überlaufen | ✅ |
| 35 | Erfassen | Datumswähler immer dunkel, Absturz bei Buchungen vor 2020 | ✅ |
| 36 | Daueraufträge | Startdatum in der Vergangenheit trägt still hunderte Umsätze nach | ✅ (Rückfrage) |
| 37 | Daueraufträge | Nicht bearbeitbar; doppelt mit verbundener Bank | ✅ |
| 38 | Budgets | Limit nicht änderbar; Fehlermeldung unter dem Sheet unsichtbar | ✅ |
| 39 | Kategorien | Keine Umbuchung/Erstattung: Sparüberweisungen = Ausgabe, Erstattungen = Einnahme | ✅ (neue Kategorie „Umbuchung“; Erstattungen gegen Ausgaben ⏳) |
| 40 | Verträge | Fehlalarme (Taschengeld) nicht ausblendbar; eine verpasste Abbuchung lässt Vertrag verschwinden | ✅ |
| 41 | Depot | Verlauf rechnet heutige Stückzahlen rückwärts; Detail-Chart skaliert Historie auf gespeicherten Kurs | ✅ (echte Kurse statt umgerechnet; Hinweis „mit heutigem Bestand“) |
| 42 | Depot | Technische Meldungen („Finnhub-Key“); eigene Positionen ohne Symbol nie live | ✅ (Symbol-Feld für eigene Positionen ⏳) |
| 43 | Depot | „1.000“ bedeutet bei Anzahl 1, beim Preis 1.000 | ✅ |
| 44 | Depot | Synchronisierte Positionen editierbar, nächster Sync macht es rückgängig | ✅ |
| 45 | Geteilt | Begleichen ohne Rückfrage/Verlauf; Mitglieder nicht änderbar; Einladungscode nicht normalisiert | ✅ (Rückfrage, Verlauf, Rückgängig, Code); Mitglieder ändern ⏳ |
| 46 | Sparziele | Ziele nicht bearbeitbar, Einzahlung ohne Rückgängig; Plan ignoriert Automatik und überfällige Ziele; Aufrunden doppelt gezählt | ✅ (bearbeiten, entnehmen, Rückgängig; Plan vs. Automatik ⏳) |
| 47 | Plus | Gratis-Test versprochen, auch wenn nicht (mehr) möglich; feste Preise neben Store-Preisen | ✅ (Google erkennt es; bei Apple entscheidet der Store-Dialog) |
| 48 | Plus | Paywall ohne „verlängert sich automatisch“ und ohne AGB/Datenschutz-Links | ✅ |
| 49 | Abo | „Nächste Zahlung“ falsch am 31.; Server-Datum ignoriert | ✅ |
| 50 | Buddy | Fehlgeschlagene Antwort verbraucht Gratis-Frage; KI-Einwilligung nicht widerrufbar | ✅ |
| 51 | Buddy | Schlägt vorhandenes Sparziel erneut vor | ✅ |
| 52 | Verbindungen | Spinner läuft nach Timeout ewig; Demo-Bank wirkt verbunden echt | ✅ |
| 53 | überall | Rohe Fehlermeldungen (Exception-Text) | ✅ (die meisten Stellen) |
| 54 | Barrierefreiheit | Keine einzige Semantics-Beschriftung; Diagramme stumm; Tap-Flächen < 44 pt | ✅ (Navigation, Diagramme, Zeitraum-Knöpfe, Tooltips) |
| 55 | Kontrast | Grün/Rot als Text im hellen Modus 2:1 bzw. 3:1 (nötig 4,5:1) | ✅ |
| 56 | Tempo | Diagramm-Scrubben baut die ganze Startseite neu, inkl. Prognose & Verträge | ✅ |
| 57 | Willkommen | Kein Zurück auf „Los geht's“, obere Hälfte leer | ✅ |

## P2 (Auswahl)

Wochenbericht „−0 %“ und rotes „+1 %“ bei „ganz normaler Woche“ · „1 Hinweise“ ·
Hinweis wegwischen ohne Rückgängig · Depot-Avatare gleich („I“) · Prozente
ergeben 99/101 % · Budget-Zeitraum „1.10 - 31.10.2026“ · „Nein/Ja“ statt
„Abbrechen/Löschen“ · Passwort-Stärke zwei Maßstäbe · Face-ID-Gerät zeigt
Fingerabdruck · Tab erneut tippen scrollt nicht nach oben · Android-Zurück
beendet die App aus Konto/Depot.

## Was bleibt, weil es schon top ist

- Geld überall als ganze Cent, deutsche Formatierung, typografisches Minus.
- Wischen-Löschen mit Rückgängig (Umsätze, Budgets, Depot).
- „So rechnet Buddy“: offene Herleitung von „Diesen Monat noch frei“.
- Kategorie ändern: „alle N ändern / nur diese“, App lernt mit.
- Budget-Tempo-Markierung, „≈ X € pro Tag“, kluger Limit-Vorschlag.
- Natürliche Suche („Rewe, über 100, Oktober“).
- Begleichen mit den wenigsten Überweisungen (Geteilt).
- Ehrliche Sparziel-Automatik („bewegt kein Geld“).
- Kündigen in zwei Taps, Store-Käufe serverseitig geprüft.
- Buddy fragt vor dem ersten Datenversand und rechnet offline weiter.
