# Ahead — Geschäftsmodell

Stand 15. Nov 2026. Gesprächsunterlage, keine Traction-Folie.

Preise, Trial und Produkt-Quotas stehen in `PlusService` (`lib/services/plus_service.dart`) und in denselben Konstanten auf dem Server: 30 Fragen, 3 Scans, 1 Ziel. Dieselbe Zahl steht in `docs/launch.md`.

**Traction: keine.** Kein Store, keine veröffentlichte Waitlist-Zahl, kein Umsatz, kein D7. Der Demo-Modus der Landing antwortet mit Platz 128 von 412. Das ist fest verdrahtet und keine Pipeline.

## 1. Satz und Job

**Ahead ist der Coach fürs erste Gehalt.** Buddy rechnet mit deinen Zahlen und nennt einen nächsten Schritt. Entscheiden tust du.

Job: Das Gehalt ist da. Welche eine Sache tue ich diese Woche mit dem Geld? Nicht das Haushaltsbuch führen. Nicht das Depot optimieren.

Landing, derselbe Satz: „Was mach ich jetzt mit meinem Gehalt?“ Store-Entwurf enger: Alltagsgeld, nicht Depot-Tracker. App, Landing und der Store-Entwurf heißen Ahead. Rechtstexte und die Package-ID sagen noch BudgetBuddy. Im Gespräch ein Name: Ahead.

## 2. Kunde

ICP: junge Erwachsene in Deutschland rund ums erste eigene Gehalt.

Lebenslagen, die das Produkt schon benennt: erste Abrechnung, erster Job, erste Wohnung, zusammenziehen, WG-Kasse, vergessenes Abo, Notgroschen, Betriebsrente als Frage an die Personalabteilung. Deutsch. Der Monat, nicht das Jahresgespräch mit dem Berater.

Nicht der Kunde: Depot-Optimierer, Haushaltsvorstand mit drei fertig kategorisierten Konten, Bestand von Finanzguru, der einen besseren Saldo will.

DACH ist keine beschlossene Expansion. Eine TAM-Zahl steht hier bewusst nicht.

## 3. Problem und warum jetzt

Die Frage ist konkret und fällt, wenn das Geld ankommt: Stimmt das Netto? Kann ich den Urlaub? Welches Abo bucht noch ab? Reicht das Polster, bevor ich irgendetwas anlege?

Drei vorhandene Antworten daneben:

- Aggregation zeigt, wo das Geld war.
- Reichweite erklärt die Kategorie.
- Ein allgemeines Chat-Modell rät, ohne deine Verträge und ohne ein Gedächtnis, das du bestätigt hast.

Warum jetzt, ohne daraus einen Burggraben zu machen: Eine Antwort ist billig genug, dass 4,99 € nicht an den Token scheitert (Abschnitt 7, Schätzung). Lesezugriff aufs Konto ist über einen lizenzierten Kontoinformationsdienst kaufbar, ohne selbst Zahlungsinstitut zu werden. Beides kann jeder kaufen. Es macht den Solo-Bau möglich. Es beweist nicht, dass diese Kohorte den einen Schritt will und nach Tag 7 zahlt.

## 4. Lösung

Buddy ist der Coach, nicht das Dashboard.

Er sieht rein und raus, sagt es ohne Finanzdeutsch und nennt einen nächsten Schritt. Die Zahlen kommen aus Buchungen, Budgets und Verträgen. Das Modell wählt und erklärt. Die Rechnung läuft in der App, nicht im Kopf des Modells.

Grenzen, die zum Produkt gehören:

- Gedächtnis nur nach „Merken“. Gehalt am 28. zählt erst dann.
- Jede Buchung bestätigt der Nutzer.
- Keine Kontonummern an die KI. Die Zusammenfassung geht nur nach Zustimmung.
- Ist die Gratis-KI alle oder das Netz weg, antwortet Buddy weiter offline aus den Daten auf dem Gerät.
- Er bewegt kein Geld, verkauft keine Fonds und zählt nicht den Kaffee. Die Landing sagt das so.

Vorsorge in der App ist eine grobe Lücke aus Alter, Netto und Wunschrente. Text in der App: Orientierung, keine Beratung.

## 5. Wedge

Kein Store-Text nennt einen Konkurrenten. Hier der Unterschied, inklusive dessen, was Ahead nicht hat.

**Finanzguru** hat die Bank und die Kategorisierung schon. Ahead beansprucht den Satz danach: ein nächster Schritt aus denselben Zahlen, und der Vertrag als Handlung (läuft noch, ist teurer geworden). Den Kontographen hat Ahead nicht. Setzt Finanzguru einen Chat auf die Umsätze, bleibt als Unterschied Ton, bestätigtes Gedächtnis und der Vertragsloop. Gemessen ist davon nichts.

**Finanzfluss** hat Vertrauen, Reichweite und den Weg übers Depot und den Inhalt. Ahead sitzt im Monat des Nutzers, nicht im Video. Ohne Audience ist das kein Angriff. Es ist ein anderes Regal: Alltagsgeld.

**ChatGPT** beantwortet die Frage. Der Ersatz ist real: Zahlen reinkopieren, Rat mitnehmen. Ahead hat die Buchungen, die bestätigten Merker, die Verträge und eine Consent-Grenze. Ahead gewinnt nur, wenn das Kopieren wehtut und der eine Schritt aus den echten Daten besser ist als der allgemeine Rat. Auch das ist ungemessen.

Der Wedge ist der Job, nicht eine Feature-Liste, die ein Incumbent in einem Quartal nicht nachbauen könnte.

## 6. Free und Plus

Free ist das Produkt. Plus ist die Decke darüber. Ob jemand für die Decke zahlt, ist unbekannt. Der Kern (Konto, Budgets, Prognose, Verträge, Notgroschen) bleibt ohne Abo benutzbar. Offline-Buddy antwortet nach dem Kontingent weiter. Die Paywall verkauft mehr vom Gleichen.

| | Free | Plus |
|---|---|---|
| Preis | 0 € | 4,99 €/Monat oder 39,99 €/Jahr |
| Anzeige Jahr | — | 3,33 €/Monat, Ersparnis 33 % gegen zwölf Monatspreise |
| Test | — | 7 Tage, danach das gewählte Intervall |
| KI-Fragen | 30 pro Kalendermonat | Monatsdecke weg |
| Beleg-Scans | 3 pro Monat | Monatsdecke weg |
| Sparziele | 1 | weitere Ziele |
| Einladung | +5 Fragen je Freund, höchstens 3 Freunde (+15) | unverändert, die Monatsdecke gilt nicht |

Quellen der Tabelle: `PlusService.monthlyCents` 499, `yearlyCents` 3999, `yearlyPerMonth` 333, `trialDays` 7, `freeAiQuestions` 30, `freeReceiptScans` 3, `freeGoals` 1. Dieselben Preise und Promo-Codes liegen in `backend/server.dart`. Einladung: `Growth.bonusPerFriend` 5, `rewardedFriends` 3, Waitlist `placesPerFriend` 5.

Promo-Codes verlängern die Testtage, sie ändern den Preis nicht. Dieselben Codes in App und Server: `START14` +14, `BUDDY30` und `FREUND` +30, `CREATOR60` +60, obendrauf auf die 7 Tage beim ersten Checkout.

Widerruf: In der App endet ein Nicht-Store-Abo bei Widerruf innerhalb von 14 Tagen sofort. Store-Käufe laufen über die Erstattung des Stores. Für Woche-1-Umsatz ist das ein Leck, kein Detail.

Drei Quotas, die nicht vermischt werden:

1. **Produkt, eingeloggt.** 30 / 3 / 1 wie oben. Zählt die App. Plus hebt diese drei Deckel. Der Paywall-Text sagt „Buddy ohne Limit“.
2. **Server, jedes Konto, auch Plus.** Default 50 KI-Aufrufe pro Konto und Tag (`AI_DAILY_LIMIT`) und ein Kostenwächter von 0,50 USD pro Konto und Tag (`AI_DAILY_COST_USD`). Das ist eine Missbrauchs-Bremse, kein zweites Preisschild. Für einen normalen Plus-Nutzer ist 50 am Tag faktisch offen gegenüber 30 im Monat. Der Server prüft das Free-Monatskontingent nicht. Ein Client, der die App-Bremse umgeht, läuft bis zum Tagesdeckel.
3. **Landing ohne Konto.** 3 Fragen pro Gerät und Tag, 20 pro IP. Allgemeines Wissen, nicht die Zahlen des Nutzers. Mit dem Free-Kontingent der App hat das nichts zu tun.

Kaufwege im Code: App Store, Google Play, Stripe (Karte, SEPA, PayPal, Klarna, Apple Pay, Google Pay). Live-Billing, Store-Produkte und Verify-Keys sind nicht der Stand dieses Dokuments. `docs/launch.md` führt sie unter MUST vor dem Store-Submit.

## 7. Unit Economics

Alles unter „Schätzung“ ist keine Rechnung aus Produktion. Es gibt keine Nutzer und keine Rechnung eines Modellanbieters in diesem Repo. Nicht als Marge zeichnen. Nicht als Forecast.

**Steht im Code oder in den Ops-Notizen**

- Token-Preise, Default für Haiku, USD pro Million: Input 1, Output 5. Cache-Read ein Zehntel des Input-Preises, Cache-Write das 1,25-Fache. Kommentar im Code: gegen die aktuelle Preisliste prüfen, per Env überschreibbar (`BuddyAgent.prices`).
- Ein Testschritt mit 1.000 Input, 9.000 Cache-Read und 200 Output kostet in dieser Formel 0,0029 USD, also 0,29 US-Cent. Eine Nutzerfrage kann mehrere Schritte sein, Deckel 6.
- Kommentar an der KI-Anbindung: grob 0,1 Cent pro Frage. Kommentar am Tageslimit: 50 Aufrufe × diese Annahme ≈ 5 Cent pro Person und Tag. Der Kostenwächter daneben steht auf 0,50 USD. Die 5 Cent sind die Absicht des Kommentars, die 0,50 USD sind die Bremse, die läuft.
- Hosting-Notiz: Hetzner CX, grob 3–5 € im Monat, EU. Apple Developer Program, Listenpreis etwa 99 € im Jahr, Pflicht vor TestFlight.
- Store-Schnitt ist nicht im Code.

**Schätzung, daraus**

| Posten | Größe | Art |
|---|---|---|
| VPS | ~4 €/Monat | Schätzung aus der Hosting-Notiz |
| Apple Developer | ~8 €/Monat, ~99 €/Jahr | Listenpreis, bevor irgendwer zahlt |
| LLM, Kommentar 0,1 ¢/Frage | 30 Free-Fragen ≈ 3 ¢ | Schätzung, nicht gemessen |
| LLM, Testschritt 0,29 ¢, zwei bis drei Schritte | grob 1 ¢/Frage, 30 Fragen ≈ 0,30 € | Schätzung auf der Preis-Map im Code, kein Median |
| Plus, 100 Fragen in dem zweiten Band | grob 1 € variabel | Schätzung |
| Store-Cut 15 % | 4,24 € von 4,99 €, 33,99 € von 39,99 € | Schätzung, Small-Business-Satz, nicht beantragt |
| Store-Cut 30 % | 3,49 € von 4,99 €, 27,99 € von 39,99 € | Schätzung, Standardsatz |
| Gemini Free Tier | variabel gegen null, bis das Kontingent reißt | trägt einen Soft Launch, keine Marge |
| Support-Minuten, USt, Akquise | offen | keine Zahl |

Der variable Posten, der zählt, ist der Store-Schnitt, nicht das Modell. Web über Stripe wäre billiger. Die App soll im Store kaufen. Die Kartengebühr steht nicht im Repo und wird hier nicht erfunden.

Die 4,24 € und 3,49 € sind Brutto minus Schnitt, ohne Umsatzsteuer. Die schärfere Serviette ist `docs/unit_economics.md`: dort bleibt nach 19 % USt und 15 % Schnitt etwa 3,56 € von 4,99 €, nach 30 % etwa 2,94 €. Dieselbe Serviette setzt eine typische Haiku-Frage auf der öffentlichen Liste vom 15. Nov 2026 bei etwa 0,16 US-Cent an. Die 0,29 Cent oben kommen aus der Preis-Map im Code (`BuddyAgent.prices`, 1 $ / 5 $ je Million), die über dieser Liste liegt. Beide Rechnungen sind Schätzungen. Keine von beiden ist eine Marge.

Infrastruktur allein (VPS plus Apple-Gebühr, grob 12 € im Monat) kippt bei einer Handvoll zahlender Monatskunden, selbst beim 30-%-Schnitt auf dem Brutto. Das sagt nichts darüber, ob jemand zahlt, was ein Aktivierter in Stunden kostet, oder wie viele Minuten Support eine Person frisst.

Steuer: keine Gesellschaft, keine USt-Id. 4,99 € und 39,99 € sind der Sticker in der App. Welcher der beiden Netto-Wege gilt, entscheidet der Händlervertrag, nicht dieses Dokument.

## 8. Go-to-market

Drei Schritte, in der Reihenfolge. Kein vierter Kanal nebenher.

**1. Warteliste.** Steht. E-Mail, eigener Code, fünf Plätze nach vorn pro Person über den Link, in der App fünf Fragen pro Freund bis drei Freunde. Das ist Mechanik. Es ist kein Kanal und keine Zahl. Demo-Plätze werden nicht zitiert.

**2. TestFlight, danach Play Internal.** An Leute, die den Builder nicht kennen. Vorher: Apple Developer. Was die Runde liefern muss, bevor ein Kanal Geld oder Stolz sieht: Signups, Anteil mit einer echten Zahl oder einer Bank, D7, Fragen pro Nutzer, Trial-Start, Paid, Refund. Freunde im TestFlight sind kein Beleg.

**3. Ein Kanal, vier Wochen.** Die Anzeige ist die Gehaltsfrage, nicht ein Feature-Stapel. Eine Fläche. Ergebnis: Zeit oder Euro pro aktiviertem Nutzer. Welche Fläche, ist nicht entschieden. Referral zählt in dieser Rechnung erst, wenn ein Fremder ihn benutzt.

Bank öffentlich erst mit kommerziellem Enable-Banking-Vertrag. Bis dahin Demo oder Warteliste. Die Connect-Rate ist dann ein Aktivierungsmaß, kein Wachstumsmodell.

## 9. Moat

Hypothese, ein Satz: Dieselbe Person bekommt in Woche 4 eine bessere Antwort als in Woche 1, weil bestätigtes Gedächtnis und Verträge im Kontext liegen und weniger Rückfragen brauchen. Gehaltstag, Studio das seit März abbucht, Erhöhung, die der Vertrag sieht.

Zum Moat wird das an dem Tag, an dem der Abstand gemessen ist. Vorher ist der Vorsprung Geschmack und deutscher Ton. Das steht nicht auf einer Folie.

Kein Moat:

- Enable Banking, Gemini, Anthropic. Miete.
- PSD2-Lesezugriff. Consent läuft ab, der Abruf ist gedeckelt.
- Die Feature-Liste, inklusive Depot, Vorsorge und Splits. Die verwässern den Satz.
- Offline-Fallback, Verschlüsselung, „auf Deutsch“. Notwendig, kopierbar.
- Ein Vergleich, den das Store-Listing zu Recht verbietet.

## 10. Risiken und Regulierung

Die Haltung ist das Produkt, nicht eine fehlende Lizenz.

- Kein Zahlungsverkehr, kein eigenes Konto, kein Geld bewegen, kein Fondsverkauf.
- PSD2 nur lesend, geplant über Enable Banking Oy, einen zugelassenen Kontoinformationsdienst in Finnland. Ohne gesetzte Schlüssel läuft im Server die Demo-Bank. Der kommerzielle Vertrag ist nicht der Inhalt dieses Dokuments. Die Landing sagt trotzdem „Nur Lesezugriff auf die Bank“. Der Satz ist wahr oder er wird gestrichen. Beides gleichzeitig geht nicht.
- Keine eigene BaFin-Lizenz und keine eigene AISP-Lizenz. Deckel und Boden derselben Entscheidung: kein Interchange, und kein Zahlungsinstitut, das man nebenbei wird.
- Keine Anlage-, Steuer-, Renten- oder Rechtsberatung. Buddy kann sich irren. Vorsorge und Versicherungs-Inventar bleiben Orientierung und Liste. Das Risiko ist, diesen Text zur Beratung aufzuweiten.
- KI kann in den USA laufen. Auftragsverarbeitung und AGB sind offen (`launch.md`, SHOULD). Vault ist AES mit dem Passwort des Nutzers. Kontonummern gehen nicht ans Modell.
- Firma: eine Person in Hamburg. Kein HRB, keine USt-Id. Für einen Soft Launch tragbar. Für eine Runde fehlt die Gesellschaft und ein Anwaltspass. Der Cap-Table ist der Name im Impressum.
- Zahlungsbereitschaft unbekannt. 4,99 € ist ein App-Store-Preis wie viele andere. Die Gratis-Tiefe plus Offline-Antwort kann die Decke unverkäuflich machen. Dann ist die Geschichte Nutzung, nicht SaaS. Die hübschere nicht aussuchen.
- Im Gespräch eine Zahl und ein Name: 30 / 3 / 1 aus `PlusService`, Marke Ahead. Rechtstexte und die Package-ID sagen noch BudgetBuddy. Die 5-Fragen-Zeile ist aus `launch.md` raus. Beides nicht wieder daneben stellen.
- Metriken sind nicht instrumentiert. Ohne die Zähler aus Abschnitt 8 ist jede Kurve erfunden.
- Distribution ist eine Person, die das Produkt gebaut hat. Das beantwortet nicht, wer die ersten tausend Weekly holt. Ein unfairer Kanal ist nicht dokumentiert.
- Weg zur Venture-Größe: nicht beschrieben. DE-Soft-Launch ist der Plan. Ein Satz „DACH, dann stoppen oder weiter“ fehlt absichtlich, solange er nur eine TAM wäre.

## 11. Was als Nächstes gefragt wird

1. Woher kommen die ersten hundert Fremden, und was kostet einer in Stunden?
2. Von fünfzig echten Trials: wie viele zahlen an Tag 8, wie viele sind in Woche 1 weg, wie viele widerrufen?
3. Was ist die Aktivierung, erste Antwort mit eigener Zahl oder Bank-Connect, und welche Rate gilt, solange Enable Banking nicht kommerziell ist?
4. Warum 4,99 €, wenn dreißig Fragen und der Offline-Buddy den Job ohne Plus tun?
5. Hält „ohne Limit“, wenn der Server jedes Konto bei fünfzig Aufrufen und 0,50 USD am Tag stoppt?
6. Wann ist der Bank-Satz auf der Landing entweder wahr oder weg?
7. Welche Gesellschaft unterschreibt Auftragsverarbeitung und AGB, bevor eine fremde Person Finanzdaten schickt?
8. Welches eine Signal zeigt, dass Woche 4 besser ist als Woche 1, und wann liegt es vor?
9. Was fliegt aus den ersten fünf Minuten (Depot, Vorsorge, Splits), damit der Satz eng bleibt?
10. Welche gemessene Zahl beendet den DE-Soft-Launch: weiter, oder aufhören?
