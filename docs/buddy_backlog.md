# Buddy-Backlog (Dauerlauf)

Claude arbeitet diese Liste von oben nach unten ab, Runde für Runde, bis Luis
„Stopp“ sagt. Jede Runde: bauen, testen (flutter test, backend dart test,
l10n), Übersetzungen, Testfälle im Katalog, committen, Demo veröffentlichen,
kurz berichten. Erledigtes wandert nach unten.

## Offen
1. Glossar auf Englisch: „tax class“ landet bei der Gehaltsabrechnung statt beim Begriff
2. Barrierefreiheit Teil 2: Karten unter den Antworten (Übernehmen/Verwerfen) und Diagramme mit Beschreibung
3. Mahnung erkennen: Buchungen mit „Mahngebühr“/„Inkasso“ früh melden, mit Schritten
4. Leistungs-Check: Startzeit der App und des Buddy-Tabs messen und optimieren
5. Screenshot-Test „08 light mode chat“ hängt: Ursache finden (wartet vermutlich auf Netzwerk)
6. Monatsrückblick als teilbare Karte (Story) direkt aus dem Chat
7. Dispo-Warnung auch als Push am Morgen, wenn das Konto in den nächsten 3 Tagen ins Minus rutscht
8. Einnahmen-Ausfall: regelmäßige Einnahme (z. B. Kindergeld) bleibt diesen Monat aus, Hinweis
9. Abo-Spartipp auch als Hinweis, wenn ein Abo mit Tipp länger als 6 Monate läuft (einmal im Jahr)
10. stats.dart: Kosten pro Werkzeug und langsamste Werkzeuge ausweisen

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
