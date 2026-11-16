# Ahead — Die nächsten 30 Tage

Stand 15. Nov 2026. Für dich, montags. Kein Pitch. Zeitraum: 16. November bis 15. Dezember.

Der Kanal bleibt der eine aus `docs/metrics_gtm.md`. Dieses Blatt benennt den Loop, hält die Aktivierung fest, setzt acht Tests in diese Wochen und sagt, was liegen bleibt. Die zehn Züge in `docs/investor_readiness.md` gelten weiter. Hier sind die ersten drei ausgearbeitet: Fremde bis zur Zahl, die Zähler, die schon definiert sind, ein Kanal über vier Wochen. Bank-Satz, Preisnagel bei fünfzig Trials, Gesellschaft und Anwalt laufen daneben. Sie sind kein neunter Test.

Die Latte, in Ahead-Sätzen:

- Wiederkommen aus eigenem Antrieb. D7 auf der Aktivierungskohorte ist die Zahl, an der so ein Produkt hängt. Waitlist-Größe hängt woanders.
- Jemand, der dich nicht kennt, schickt den Satz weiter. Fünf Plätze auf der Warteliste sind Mechanik.
- Der Loop hat einen Namen, den du laut sagen kannst.
- Zahlen ist ein Beleg an echten Trials. 4,99 € auf der Folie ist keiner.
- Die Aktivierung ist die Handlung, nach der die Leute bleiben. Die Strecke, die du kürzst, liegt zwischen Mail oder Installation und dieser Handlung.

Haltung, nicht Zitat: organische D7, Weitererzählen, ein benannter Loop, ein Beleg fürs Geld. Die Handlung, die das Wiederkommen verursacht, sitzt vor der Retention. Der Nutzen kommt vor der Kasse, der Chat ist das, was weitergehen kann, Free und Plus passen in zwei Sätze. Preise, Quotas, Zähler: `docs/business_model.md`, `docs/unit_economics.md`, `docs/metrics_gtm.md`.

## 1. Der Loop

**Das Gehalt oder die Rechnung löst eine Frage aus, Buddy nennt eine Euro-Zahl und einen Schritt, die nächste Frage kommt mit dem nächsten Geld.**

| | |
| --- | --- |
| Auslöser | Zahltag, Abbuchung, „reicht das“. Auf dem Reel derselbe Satz: „Was mach ich mit meinem Gehalt?“ |
| Handlung | Eine Frage. Die Zahlen tippt die Person, solange die Bank nicht kommerziell live ist. |
| Lohn | Eine Euro-Zahl ungleich null und ein nächster Schritt. Entscheiden tut sie. |
| Wiederkehr | Die nächste Geldsache. Dieselbe Woche oder der nächste Zahltag. |

Depot, Vorsorge und Splits stehen in diesem Satz nicht. In den ersten fünf Minuten auch nicht.

## 2. Aktivierung

**Primär, steht.** `activated`: Buddy hat dieser Installation zum ersten Mal eine Antwort mit einem echten Euro-Betrag gegeben. `340 €`, `€4.99`. Null, die Maske und der Hilfetext, der nur den Plus-Preis nennt, bleiben draußen. Nenner und Code: `docs/metrics_gtm.md`. Der Nordstern bleibt „Aktivierte diese Kalenderwoche“.

**Sekundär, Vorschlag, noch kein Zähler.** Zwei getrennte Dinge:

1. **Zweite Frage.** Eine weitere Buddy-Antwort mit einer Euro-Zahl innerhalb von sieben Kalendertagen nach `activated`. Das ist der Kandidat für die Handlung, die das Wiederkommen verursacht. Die erste Zahl kann das Aha sein. Die zweite Frage ist die Gewohnheit.
2. **D7.** Die App ist am siebten Kalendertag nach der Aktivierung offen. D7 ist der Ausgang, an dem du den Kandidaten misst. Aktiviert bleibt die erste Euro-Zahl.

Den Nordstern tauschst du erst, wenn zwei Gruppen da sind, jede mit mindestens zehn Personen, deren Aktivierung sieben Tage zurückliegt, und der D7-Anteil der zweiten Frage höher liegt, ohne dass du dafür eine Tabelle brauchst. Darunter bleibt es eine Notiz neben dem Blatt. Steht die zweite Frage in keinem Log, heißt die Zelle „nicht erhoben“.

`d1` bleibt der Frühindikator. Er entscheidet den Nordstern nicht.

## 3. Acht Tests

Reihenfolge ist die Entscheidung, die die nächste freigibt. Dein Telefon zählt nicht. Leute, die dich kennen, zählen nicht. Demo-Plätze zählen nicht. Die Tests lesen Zähler, die schon definiert sind.

**1. Onboarding. Fremde bis zur ersten Euro-Zahl.**
TestFlight, danach Play Internal, an Leute, die dich nicht kennen. Der erste Screen stellt die Gehaltsfrage. Gehalt, Miete oder ein Abo, getippt, reichen für die Antwort. Depot, Vorsorge und Splits liegen nicht in den ersten fünf Minuten.
Weiter, sobald du jede Woche den Anteil Installation → `activated` aufschreiben kannst, auch bei kleiner Zahl.
Solange der Anteil „nicht erhoben“ ist, kommt kein weiterer Screen in den ersten Lauf.

**2. Kanal. Ein Reel-Konto, ein Satz, ein Code.**
Der Plan vom 16. Nov bis 13. Dez in `docs/metrics_gtm.md` ist dieser Test. Vier Wochen, Bio-Link mit `?ref=`, nur Zeilen in `growth.json` mit diesem `ref`.
Weiter mit dem Motiv, das Signups mit dem Code bringt.
Am 13. Dez unter 20 solcher Signups ist der Kanal zu. TikTok, Ads und ein zweites Netz bleiben in dieser Woche zu. Die Zahl an dem Freitag: Stunden pro Signup mit Code.

**3. Onboarding. Die zweite Frage in derselben Sitzung.**
Nach der ersten Euro-Zahl eine Folgezeile. Eine. Abo, was übrig bleibt, oder Notgroschen. Dieselbe Lebenslage.
Weiter, sobald du bei den Fremden siehst, wer eine zweite Zahl bekommen hat.
Liegt der D7-Anteil der zweiten Frage nicht über der Gruppe mit einer Frage, und sind beide Gruppen groß genug aus Abschnitt 2, bleibt der Nordstern die erste Zahl. Vorher schreibst du „zu früh“. Die Folgezeile ist dann eine Notiz, kein Fehlschlag.

**4. Paywall. Die Zahl kommt vor dem Preis.**
Free ist benutzbar, bevor Plus erscheint: Konto, Budgets, Prognose, Verträge, Notgroschen, 30 Fragen. 4,99 € und der Text, der nur den Preis nennt, kommen nach `activated`.
Weiter, wenn Aktivierte entstehen und der erste Kontakt ein Schritt ist.
Ein Trial ohne vorherige Zahl zählt nicht als Zahlungsbereitschaft. Den Preis ziehst du dafür nicht nach vorn.

**5. Paywall. Free und Plus in zwei Zeilen.**
Ein Screen, nachdem die Zahl da ist. Free: 30 Fragen, 3 Belege, 1 Ziel, der Schritt bleibt. Plus: derselbe Buddy ohne diese Monatsdecke, 4,99 € im Monat oder 39,99 € im Jahr, 7 Tage. Ob 4,99 € trägt, steht in `docs/unit_economics.md`. Dieser Test ändert den Preis nicht. `START14`, `BUDDY30`, `FREUND` und `CREATOR60` bleiben draußen.
Weiter, indem du `trial_start` und `paid` nur unter Aktivierten notierst, dazu Widerruf und Kündigung in Woche 1.
Unter 50 echten Trials ist jede Preisgeschichte „zu früh“. Dreißig Tage können darunter liegen. Das ist ein Ergebnis.

**6. Referral. Ein Name.**
Jede fremde Person mit einer Zahl, bis zu fünf: wem schickst du das, mit Namen. Der Platz-Bonus und die fünf Extra-Fragen bleiben aus dieser Frage heraus.
Weiter nur, wenn mindestens eine Person einen konkreten Menschen nennt.
Nennt niemand jemanden, baust du keine Share-Fläche. Dann wird der Loop nicht weitererzählt, und das schreibst du so auf.

**7. Referral. Der Satz sitzt auf der Antwort.**
Eine Zeile unter der Euro-Zahl: die Frage, ohne den Betrag. Link mit `ref`. Gezählt wird ein `ref`, der auf einem fremden Gerät ankommt und dort bis `activated` kommt.
Weiter, wenn ein Fremder auf diesem Weg eine eigene Zahl bekommt.
Ohne dieses `activated` zitierst du keinen Koeffizienten.

**8. Kanal. Eine Zeile zum Zahltag, von Hand.**
Am 27. und 30. Nov und am 1. Dez schreibst du den Leuten mit einer Zahl selbst eine Zeile: Montag kommt das Gehalt, eine Frage. Die Reels dieser Tage stehen schon im Kanalplan. Ein Push kommt nicht dazu.
Weiter, wenn du die Öffnung gegen das Aktivierungsdatum legen kannst.
D7 schreibst du für Kohorten, die sieben Tage alt sind. Jünger heißt „zu früh“.

## 4. Was liegen bleibt

Drei Bauten, die sich aus fremden Kassen und aus dem eigenen Satz anbieten. In diesen 30 Tagen sind sie falsch.

**Gehaltsvorschuss.** Der Chat kann der Eingang sein. Das Geschäft danach, Geld vor dem Zahltag gegen eine Tempo-Gebühr, ist ein anderes: Auszahlung, Kredit, ein Konto dahinter. Ahead bewegt kein Geld, hält keins und nimmt keine Gebühr für Tempo. Übernommen wird die Reihenfolge, Nutzen vor der Kasse. Der Vorschuss wäre eine Lizenz, die hier nicht liegt.

**Fonds-Marktplatz.** Vergleich, Broker, Affiliate, ein Depot-Abschluss. Das ist Reichweite und Provision. Ahead hört bei einem Schritt auf. Eine Vermittlung macht aus „du entscheidest“ einen Abschluss. Der offene Beleg ist fünfzig Trials auf 4,99 €, kein zweiter Umsatzstrom.

**BaFin-Beratung.** Anlage, Steuer, Rente oder Versicherung als Rat, der die Entscheidung ersetzt. Vorsorge in der App bleibt die grobe Lücke, der Satz bleibt Orientierung. Eine eigene Beratungserlaubnis, eine eigene AISP-Lizenz oder ein Zahlungsinstitut stehen auf derselben Liste. Eine leere D7 ist kein Grund, sie zu öffnen.

Dieselben Wochen frisst auch: ein zweiter Kanal, ein Cohort-Tool, ein Analytics-SDK, eine Preisänderung, ein Push-System, Ausbau von Depot, Vorsorge oder Splits, die Demo-Bank als `bank_connect`. Der Enable-Banking-Vertrag bleibt die Entscheidung auf der Landing, wahr oder gestrichen.

## 5. Montagsblatt

Zwanzig Minuten. Dasselbe Blatt wie in `docs/metrics_gtm.md`. Dieselben Zeilen, dieselben Nenner. „Nicht erhoben“ und „zu früh“ bleiben stehen.

| Zeile | Zähler | Welcher Test sie liest |
| --- | --- | --- |
| Waitlist | `waitlist_signup`, davon mit Reel-`ref` | 2 |
| Aktiviert | `activated`, sonst „nicht erhoben“ | 1, Nenner für 3, 4, 5 |
| D1 | Anteil, aktiviert vor 8–14 Tagen | Frühsignal |
| D7 | Anteil, Kohorte mindestens sieben Tage alt | 3 und 8. In Woche 1: „zu früh“ |
| Trial | Stripe `trialing` plus App Store Connect, ohne Demo, ohne dein Telefon | 5 |
| Paid | von `trialing` auf `active`, abzüglich Refund und Widerruf derselben Woche | 5. Unter 50 Trials keine Preiszeile |
| Bank | `bank_connect` im Server-Log | „nicht live“, solange der Vertrag nicht steht |

Neben das Blatt, nicht hinein und nicht ins Deck: wer eine zweite Zahl bekommen hat, und ob jemand einen Namen genannt hat. Beides wird kein Zähler, solange es nicht im Code hängt. Crashes, NPS und Freunde im TestFlight bleiben draußen.

Freitag, 13. Dez, eine Entscheidung:

- Unter 20 Signups mit Code: Kanal zu. Der nächste Kanal öffnet in dieser Woche nicht.
- Aktivierte immer noch „nicht erhoben“: die Tests haben nicht angefangen. Über Retention steht dann nichts.
- D7 da, die zweite Frage hebt ihn nicht: der Loop ist ein einmaliges Aha. Die Geschichte ist Nutzung.
- Trials da, an Tag 8 zahlt niemand, Woche 1 ist Kündigung oder Widerruf: die Geschichte ist Nutzung. Der Preis bleibt stehen, bis fünfzig echte Trials da sind oder dieser Satz trägt.

## Was du danach sagst

Die Zeile auf dem Blatt. Eine Kurve aus der Waitlist, ein Koeffizient ohne fremdes `activated`, ein Moat aus dem Ton, ein Vorschuss, ein Fonds oder eine Beratung ersetzen diese Zeile nicht. Leer ist ein Ergebnis. Der nächste Bau ist der, den die Zeile verlangt.
