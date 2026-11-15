# Buddy-Backlog (Dauerlauf)

Claude arbeitet diese Liste von oben nach unten ab, Runde für Runde, bis Luis
„Stopp“ sagt. Jede Runde: bauen, testen (flutter test, backend dart test,
l10n), Übersetzungen, Testfälle im Katalog, committen, Demo veröffentlichen,
kurz berichten. Erledigtes wandert nach unten.

## Offen
1. Datenübersicht: Serverstandort eintragen, sobald der Server steht
2. Server-Ende-zu-Ende-Test: Server in der Testumgebung starten und Anmeldung, Sicherung, Export prüfen

## Erledigt
- Stop bricht HTTP/SSE wirklich ab; Streaming-Updates gedrosselt (~50 ms)
- Buddy ChatGPT-clean: Thinking-Zeile (Orb + „Prüft …“), max. 2 Follow-ups, kurze Tool-Status
- Persona auf die Regeln gekürzt, die die Antwort ändern
- Weitere Textkürzungen auf Screens und Widgets
- Abrechnungs-Verlauf als Diagramm (Brutto/Netto/Abzüge) über Buddy-Werkzeug `diagramm` art `abrechnung`
- Buddy-Start: Prognose und Hinweise erst nach dem ersten Frame; ein Forecast für Zahl und Tipp
- Monatsrückblick als Story aus dem Chat (Chip „Monats-Story teilen“ und Menü)
- Versicherungs-Check offline (LocalBuddy) und als Eintrag in der Vermögens-Ansicht
- Schulden: Zinssatz pro Schuld in der Vermögens-Ansicht speichern
- Calm Buddy-Start nach Login: Zahl, eine Bemerkung, drei Wege; Composer „Nachricht an Buddy“; Stopp während Streaming
- Persona kürzer (ChatGPT/Claude-Stil, max. ~80 Wörter); LocalBuddy-Überblick gekürzt
- Abo-Spartipp einmal im Jahr, wenn bekanntes Abo >6 Monate läuft
- Profil-/Auth-/Getting-Started-Texte gekürzt
- Zahlen-Check, verworfene Vorschläge, Kündigungsfristen
- Gesprächsgedächtnis, Brutto-Netto 2026, Monatsabschluss, Sparrate
- Gehaltsabrechnung prüfen, Sparziel-Rückstand
- Doppelte Abbuchungen, Bankgebühren, Wochenplan, Frag Buddy in der Buchung
- Hinweise nach Wichtigkeit, Steuer 2026, Onboarding als Gespräch
- „Was kannst du alles?“ lokal beantwortet
- Gehaltserhöhung, unrealistische Budgets, Steuer-Erinnerung, Lebenslagen haken sich selbst ab
- Notgroschen aus echten Fixkosten (Karte), „Kann ich mir das leisten?“ als Ampel, Bank-Buchungen in Klartext
- Offline-Antworten komplett auf Englisch (mit Test), Ampel auch offline, Chat für Screenreader, Kontrast geprüft (brandText)
- Rückfragen mit Antwort-Chips (Prompt, Grader, bis 4 Chips), Dispo-Warnung vor dem Gehalt, zurückgegangene Lastschriften
- Regelmäßige Einnahmen (Kindergeld, BAföG, Nebenjob) in der Prognose, Abo-Spartipps ohne Preise, Feedback-Auswertung in stats.dart
- Glossar zuerst bei „Was ist …?“, Karten und Diagramme für Screenreader, Mahngebühren und Inkasso erkennen
- Ausbleibende Einnahmen (Gehalt, Kindergeld), Push am Morgen vor dem Minus, Werkzeug-Auswertung (Kosten, Tempo)
- Ratenkäufe (Klarna, PayPal, Finanzierung) als Monatssumme, Nachfrage eine Woche nach einer Karte, Versicherungs-Check nach Art
- Plus-Kauf verlangt kein neues Konto mehr (Fix), Jahreszahlungen mit Rücklage, Ziel-Feier mit nächstem Schritt
- Gehaltsabrechnungen im Monatsvergleich (Steuerklasse, Kirchensteuer, Krankenkasse, Betriebsrente), Schulden-Plan (Lawine)
- Rücklage für Jahreszahlungen in der Prognose, Ratenkäufe mit Enddatum, „Wo deine Daten liegen“ (live, gegen die Datenschutzerklärung getestet), Chat folgt dem Sprachwechsel
- Englisch-Klicktest durch alle Tabs und Profilseiten (keine deutschen Reste mehr), „Alle meine Daten“ als Datei, Screenshot-Test 08 hängt nicht mehr
- Server startet wieder (Rechtstexte ohne Flutter, Wächter-Test), Server-Export in „Alle meine Daten“
- Startbildschirm stark reduziert, Plus-Knopf aus der Leiste (Eintragen über Buddy, „+“ im Konto-Tab), Buddy versteht „Kaffee 3,50“
