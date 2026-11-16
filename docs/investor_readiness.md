# Ahead — Investor-Readiness (ehrlich)

Stand 15. Nov 2026. Quellen: `docs/launch.md`, `docs/buddy_backlog.md`, `docs/store_listing_de.md`, Plus-Code, Landing. Kein Pitch. Preis, Trial, Quotas und die Rechnung: `docs/business_model.md`.

These: Das Produkt ist weiter als die Firma. YC finanziert Lernspeed an echten Nutzern, nicht Feature-Tiefe. Heute gibt es die Tiefe und null öffentliche Zahlen.

## Was schon belastbar ist

- **Satz ist scharf.** Landing: „Was mach ich jetzt mit meinem Gehalt?“ → Buddy rechnet mit deinen Zahlen, ein nächster Schritt, du entscheidest. Store-Entwurf sagt dasselbe enger: Alltagsgeld, nicht Depot-Tracker.
- **Ungewöhnlich fertig für null Nutzer.** Auth, Vault (AES, Passwort), Buddy mit Consent / Quota / Offline-Fallback, Verträge, Prognose, Splits, Plus verdrahtet: 4,99 €/Monat, 39,99 €/Jahr, 7 Tage Trial, Store- und Stripe-Hooks. Free lässt Konto, Budgets, Prognose, Verträge, Notgroschen, einen Ziel-Slot; Plus ist Buddy ohne Limit, Belege ohne Limit, mehr Ziele (`PlusService`: 30 Gratis-KI-Fragen, 3 Scans, 1 Ziel).
- **Regulierung ist die richtige Form, nicht die falsche Lizenz.** Kein Zahlungsverkehr, kein Konto, Disclaimer „Orientierung, keine Beratung“. PSD2 nur lesend, geplant über Enable Banking (lizenzierter AISP), nicht als eigene BaFin-Lizenz. Deckel und Boden in einer Entscheidung: kein Interchange, aber auch kein Zahlungsinstitut.
- **Kosten sind nicht das Risiko.** Hetzner wenige Euro, Haiku grob 0,1 ¢/Frage. Gemini-Free-Tier trägt einen Soft Launch, nicht eine Marge.
- **Ein Builder, der shipped.** Der Backlog ist ein Produkt, kein Prototyp. Das ist der einzige harte Beleg.

## Harte Lücken

1. **Traction = null.** Kein Store, keine publizierte Waitlist-Conversion, kein D7, kein Umsatz. Warteliste plus Referral (+5 Plätze, +5 Fragen) ist Mechanik, kein Kanal. Demo-Modus der Landing antwortet mit Platz 128 von 412 — das ist Attrappe.
2. **Distribution fehlt.** CTA ist Warteliste. Kein Kanal-Test, kein Store-Submit. ASO-Entwurf liegt, Screenshots nicht.
3. **Das Versprechen auf der Site ist voraus.** Fine Print: „Nur Lesezugriff auf die Bank.“ `launch.md`: Bank öffentlich nur mit Enable-Banking-Vertrag, sonst Demo/Waitlist. Wer die Site klickt, sieht eine Lüge oder ein Produkt — du musst wählen.
4. **Moat ist Miete.** Enable Banking + Gemini/Anthropic kann jeder kaufen. Verhaltensloop (Verträge, Gedächtnis, bessere Woche-4-Antwort) ist ungemessen. Depot, Vorsorge, Splits verwässern den einen Satz. Finanzguru hat die Bank schon, Finanzfluss die Reichweite, ChatGPT die Frage.
5. **Firma ist eine Person.** Luis Frenkler, Hamburg, private Mail, kein HRB, keine USt-Id. Für Soft Launch ok. Für eine Runde fehlt Gesellschaft plus ein Anwaltspass (KI-Transfer, AGB). Der Pass steht in `launch.md` noch unter SHOULD.
6. **Metriken sind nicht instrumentiert.** Kein Cohort-Tool. Sentry und CI stehen unter SHOULD. Ohne vier Zähler ist jede Kurve erfunden.
7. **Zahlungsbereitschaft unbekannt.** Plus verkauft mehr vom Gleichen, während der Kern gratis ist. 4,99 € ist App-Store-Commodity. Ob jemand nach Tag 7 zahlt, weißt du nicht.
8. **Team-Satz fehlt.** „Ich habe es gebaut“ beantwortet nicht „wer holt die ersten 1.000 Weekly“. Kein unfairer Kanal (Audience, Community, Bank) ist dokumentiert.
9. **Name in Rechtstexten und Package-ID.** App, Landing, `launch.md` und Store-Entwurf: Ahead, Quota 30 / 3 / 1 aus `PlusService`. `docs/legal` und die Package-ID sagen noch BudgetBuddy.
10. **Kein Weg zur Venture-Größe.** DE-Soft-Launch ist richtig. Ein Satz „DACH, dann stoppen oder weiter“ fehlt. TAM aus dem Hut ist schlimmer als die Lücke.

YC nimmt das heute nicht. Ein Accelerator mit Produktfokus vielleicht als „komm wieder mit Weekly-Nutzern“. Vorher ist es ein Solo-Build, kein Case.

## Nächste 10 Züge, nach Hebel

1. **Fremde rein, eine Zahl raus.** TestFlight/Play an Leute, die dich nicht kennen. Wöchentlich: Signups, Anteil mit echter Zahl oder Bank, D7, Fragen/Nutzer. Bis das existiert, ist der Rest Folie.
2. **Vier Zähler vor dem nächsten Feature.** Waitlist (echter Server), erste Buddy-Antwort mit Zahl, D1/D7, Trial-Start → Paid → Refund. Sentry nur, damit Crashes dich nicht statt Nutzer lehren.
3. **Ein Kanal, vier Wochen.** Die Gehaltsfrage ist die Anzeige. Eine Fläche (Reels, ein Subreddit, eine Uni, ein Creator-Code). Zeit oder Euro pro aktiviertem Nutzer. Referral zählt erst, wenn ein Fremder ihn benutzt.
4. **Bank-Satz wahr machen oder streichen.** Enable Banking kommerziell für eine geschlossene Kohorte und Connect-Rate messen — oder „Lesezugriff“ von der Landing, bis der Vertrag steht. Connect-Rate ist die Aktivierung, nicht der Moat.
5. **Pitch auf einen Job kürzen.** „Deutscher Alltagscoach, nächster Schritt aus deinen Zahlen.“ Depot, Vorsorge, Splits nicht in die ersten fünf Minuten.
6. **Preis an 50 echten Trials festnageln.** Quota liegt fest: 30 Fragen und 3 Scans im Monat, 1 Ziel; Plus ist Buddy ohne Limit. Trial→Paid, Refund, Kündigung in Woche 1. Zahlt niemand, ist die Story Nutzung, nicht SaaS. Die hübschere nicht aussuchen.
7. **Gesellschaft entscheiden, ein Anwalt, eine Woche.** UG ja oder nein, schriftlich. KI-Auftragsverarbeitung (Gemini/Anthropic, US-Transfer), AGB, Enable-Banking-Vertrag. Disclaimer „keine Beratung“ behalten, nicht zur Beratung aufbohren.
8. **Kosten auf eine Serviette, die Fragen überlebt.** Cent pro Antwort, Hosting, Store-Cut 15–30 %, Minuten Support pro Nutzer. Free-Tier nicht als Marge zeichnen.
9. **Team-Absatz, ein Absatz.** Solo, Produkt steht, Lücke ist Distribution. Wen du nicht einstellst, um voller auszusehen. Wenn kein Kanal da ist: der Plan ist Zeit gegen Lernen, nicht ein erfundener Co-Founder.
10. **Moat-Satz verbieten, bis er messbar ist.** Erlaubt erst, wenn Woche-4-Antworten für denselben Nutzer nachweisbar besser sind als Woche 1 (Verträge, Gedächtnis, weniger Nachfragen). Vorher ist der Vorsprung Geschmack und deutscher Ton. Das steht nicht auf einer Folie.

## Was du nicht fakest

- Waitlist-Größe, Platz, „412 Leute“, Referral-Coefficient. Die Demo-Zahlen sind fest verdrahtet.
- Nutzer, WAU, Retention, Umsatz, NPS, „Freunde im TestFlight“ als Traction.
- „Bank live“ für Sparkasse, DKB, N26, ING. PSD2-Abruf ist gedeckelt und Consent läuft ab; das ist kein Burggraben.
- Eigene AISP-/BaFin-Lizenz. Die Lizenz hätte Enable Banking, und der Vertrag ist nicht zu.
- „Eigenes Modell“, proprietäre Daten, Moat durch Feature-Liste.
- Advisors, Team, Ex-Irgendwas. Dein Name im Impressum ist der wahre Cap-Table.
- Sieg gegen Finanzguru oder Finanzfluss. Das Listing verbietet den Vergleich zu Recht.
- „Launch-fertig“, solange Signing, Live-Billing, kommerzielle Bank und Anwaltspass offen sind.
- Zwei Marken oder zwei Gratis-Quotas im selben Gespräch.
- Vorsorge oder Versicherungs-Check als regulierte Beratung. Der Produkttext sagt Orientierung. Dabei bleiben.

Die nächsten 30 Tage stehen in `docs/optimization_playbook.md`.
