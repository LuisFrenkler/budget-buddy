# Buddy-Backlog (Dauerlauf)

Claude arbeitet diese Liste von oben nach unten ab, Runde für Runde, bis Luis
„Stopp“ sagt. Jede Runde: bauen, testen (flutter test, backend dart test,
l10n), Übersetzungen, Testfälle im Katalog, committen, Demo veröffentlichen,
kurz berichten. Erledigtes wandert nach unten.

## Offen
1. Buddy erkennt Jahreszahlungen (Kfz-Versicherung, GEZ quartalsweise) und legt dafür monatlich Geld zurück
2. Gehaltsabrechnung: Werte über die Monate vergleichen (Steuerklasse, Krankenkasse geändert?)
3. Ziel-Feier: erreichtes Sparziel mit kurzer Animation und nächstem Vorschlag
4. Leistungs-Check: Startzeit der App und des Buddy-Tabs messen und optimieren
5. Screenshot-Test „08 light mode chat“ hängt: Ursache finden (wartet vermutlich auf Netzwerk)
6. Monatsrückblick als teilbare Karte (Story) direkt aus dem Chat
7. Abo-Spartipp auch als Hinweis, wenn ein Abo mit Tipp länger als 6 Monate läuft (einmal im Jahr)
8. Ratenkäufe: Tilgungsplan („in 4 Monaten frei“) aus bezahlten Raten und Restbetrag, wenn bekannt
9. Versicherungs-Check offline (LocalBuddy) und als Eintrag in der Vermögens-Ansicht
10. Schulden-Lawine: Reihenfolge zum Abbezahlen (teuerste zuerst) als Plan-Karte

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
