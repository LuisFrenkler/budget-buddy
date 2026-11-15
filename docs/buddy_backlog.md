# Buddy-Backlog (Dauerlauf)

Claude arbeitet diese Liste von oben nach unten ab, Runde für Runde, bis Luis
„Stopp“ sagt. Jede Runde: bauen, testen (flutter test, backend dart test,
l10n), Übersetzungen, Testfälle im Katalog, committen, Demo veröffentlichen,
kurz berichten. Erledigtes wandert nach unten.

## Offen
1. Ratenkäufe (Klarna, PayPal Später) erkennen und als Schulden-Überblick zeigen
2. Buddy merkt sich erledigte Hinweise und fragt eine Woche später nach, ob es geklappt hat
3. Versicherungs-Check: doppelte oder für 20-Jährige meist unnötige Versicherungen als Frage an Buddy
4. Leistungs-Check: Startzeit der App und des Buddy-Tabs messen und optimieren
5. Screenshot-Test „08 light mode chat“ hängt: Ursache finden (wartet vermutlich auf Netzwerk)
6. Monatsrückblick als teilbare Karte (Story) direkt aus dem Chat
7. Abo-Spartipp auch als Hinweis, wenn ein Abo mit Tipp länger als 6 Monate läuft (einmal im Jahr)
8. Buddy erkennt Jahreszahlungen (Kfz-Versicherung, GEZ quartalsweise) und legt dafür monatlich Geld zurück
9. Gehaltsabrechnung: Werte über die Monate vergleichen (Steuerklasse, Krankenkasse geändert?)
10. Ziel-Feier: erreichtes Sparziel mit kurzer Animation und nächstem Vorschlag

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
