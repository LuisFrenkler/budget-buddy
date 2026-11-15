# Buddy-Backlog (Dauerlauf)

Claude arbeitet diese Liste von oben nach unten ab, Runde für Runde, bis Luis
„Stopp“ sagt. Jede Runde: bauen, testen (flutter test, backend dart test,
l10n), Übersetzungen, Testfälle im Katalog, committen, Demo veröffentlichen,
kurz berichten. Erledigtes wandert nach unten.

## Offen
1. Leistungs-Check: Startzeit der App und des Buddy-Tabs messen und optimieren
2. Monatsrückblick als teilbare Karte (Story) direkt aus dem Chat
3. Abo-Spartipp auch als Hinweis, wenn ein Abo mit Tipp länger als 6 Monate läuft (einmal im Jahr)
4. Versicherungs-Check offline (LocalBuddy) und als Eintrag in der Vermögens-Ansicht
5. Schulden: Zinssatz pro Schuld in der Vermögens-Ansicht speichern, damit der Plan ohne Nachfrage rechnet
6. Abrechnungs-Verlauf als kleine Grafik (Brutto, Netto, Abzüge über die Monate)
7. Datenübersicht: Serverstandort eintragen, sobald der Server steht (LegalInfo + Datenschutzerklärung)
8. Server-Export: Konto und Feedback vom Server mit in „Alle meine Daten“ (Endpunkt /account/export)
9. Klick-Test auch für Deutsch und für die Unterseiten von Planen und Vermögen
10. Chat-Verlauf: Sprachwechsel auch für Hinweise im Überblick („Buddy sagt“) sofort neu berechnen

## Erledigt
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
