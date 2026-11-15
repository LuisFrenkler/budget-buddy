# Buddy-Backlog (Dauerlauf)

Claude arbeitet diese Liste von oben nach unten ab, Runde für Runde, bis Luis
„Stopp“ sagt. Jede Runde: bauen, testen (flutter test, backend dart test,
l10n), Übersetzungen, Testfälle im Katalog, committen, Demo veröffentlichen,
kurz berichten. Erledigtes wandert nach unten.

## Offen
1. Gesprächsqualität: Antworten länger als 150 Wörter im Prompt-Beispiel kürzen, Rückfragen mit Antwort-Chips
2. Wiederkehrende Einnahmen (Kindergeld, BAföG, Nebenjob) erkennen und in der Prognose nutzen
3. Rücklastschrift-Hinweis: zurückgegangene Lastschrift erkennen und als Hinweis mit nächstem Schritt zeigen
4. Dispo-Warnung: Kontostand läuft laut Prognose vor dem Gehalt ins Minus, früh Bescheid geben
5. Abo-Preisvergleich: bekannte günstigere Tarife desselben Anbieters (Werbe-Abo, Jahresabo) als Hinweis
6. Auswertung Feedback-Gründe in stats.dart (welcher Grund, welche Werkzeuge)
7. Leistungs-Check: Startzeit der App und des Buddy-Tabs messen und optimieren
8. Screenshot-Test „08 light mode chat“ hängt: Ursache finden (wartet vermutlich auf Netzwerk)
9. Glossar auf Englisch: „tax class“ landet bei der Gehaltsabrechnung statt beim Begriff
10. Barrierefreiheit Teil 2: Karten unter den Antworten (Übernehmen/Verwerfen) und Diagramme mit Beschreibung

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
