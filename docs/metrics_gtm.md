# Ahead — Metriken und ein Kanal

Stand 15. Nov 2026. Was Seed- und YC-Partner vor der Bewerbung sehen wollen: eine Nordstern-Zahl, sechs Zähler, ein Kanal, ein Montagsblatt. Kein Cohort-Tool, kein Analytics-SDK. Personenbezogene Daten bleiben, wo sie schon sind (Waitlist-Mail in `growth.json`, Bank im Session-Store). Die Zähler selbst tragen keine Mail, keinen Namen, keine Frage, keinen Betrag, keine IBAN.

## Nordstern

**Aktivierte diese Kalenderwoche.**

Aktiviert heißt: Buddy hat dieser Person zum ersten Mal eine Antwort mit einem echten Euro-Betrag gegeben. `340 €`, `€4.99`. Nicht `0,00 €`, nicht die Maske `•••••• €`, nicht der Hilfetext, der nur den Plus-Preis nennt.

Der Satz, den du sagst: „Diese Woche haben N Leute zum ersten Mal eine Zahl zu ihrem Geld bekommen.“ N ist die Anzahl neuer `activated`, nicht die Waitlist.

## Sechs Zähler

Tag auf dem Telefon: lokaler Kalendertag. Tag auf dem Server: UTC. Nicht in eine Quote mischen.

| Zähler | Definition | Nenner |
| --- | --- | --- |
| `waitlist_signup` | Neue Mail. Dieselbe Mail noch einmal (`already`) zählt nicht. | — |
| `activated` | Erste Buddy-Antwort mit einer Euro-Zahl ungleich null. Einmal pro Installation. | — |
| `d1` | App geöffnet am Kalendertag nach dem Aktivierungstag. | Aktivierte dieses Kohortentags |
| `d7` | App geöffnet am siebten Kalendertag nach der Aktivierung. Wer Tag 1 auslässt, kann Tag 7 trotzdem schaffen. | Dieselbe Kohorte, erst wenn sie sieben Tage alt ist |
| `trial_start` | Plus liegt auf dem Gerät und `inTrial` ist wahr (7 Tage, `PlusService.trialDays`). | Aktivierte, sobald die Kohorte groß genug für eine Quote ist |
| `paid` | Dieselbe Subscription ist nicht mehr in der Probezeit und `invoices` hat ein Datum, das schon war. Kündigen in der Probezeit ist kein `paid`. | `trial_start` derselben Kohorte |

**`bank_connect`**, solange die Bank im Produkt ist: der Server hat die Session nach dem Bank-Callback gespeichert. Demo-Bank (kein `EB_APP_ID`) nicht als Connect an Investoren geben. Kein Nenner, bis Connect für Fremde offen ist. Steht der Enable-Banking-Vertrag nicht, ist die Zelle „nicht live“, nicht 0 als Erfolg.

D1/D7 hängen am Aktivierungstag, nicht an der Waitlist. Wer nie eine Zahl bekam, ist keine Retention.

## Wo es im Code hängt

Gleicher Zeilenbau überall: `product_event 2026-11-16 waitlist_signup`.

**Schon angeschlossen**

- Waitlist: `backend/server.dart`, `POST /waitlist/join`, nur wenn `already` nicht wahr ist. Zählen kannst du auch die Einträge in `backend/.data/growth.json` (`joinedAt`). Die Datei enthält Mails. Zählen, nicht weitergeben.
- Bank: `backend/server.dart`, `_callback`, nachdem die Session gespeichert ist. Eine Zeile, ohne Bankname und ohne IBAN.
- Trial und Paid: `PlusService._store`. Trial, solange `inTrial`. Paid, wenn die Probezeit vorbei ist und eine Zahlungsfrist schon erreicht wurde. Einmal pro Installation (`lib/services/product_events.dart`). Stripe und die Stores bleiben die Zahl, die du zitierst. Der Demo-Checkout ohne `STRIPE_SECRET_KEY` ist kein Umsatz.
- D1/D7: `ProductEvents.noteOpen` in `main`, nach dem Öffnen der Settings-Box. Tut nichts, bis `activated` den Anker-Tag geschrieben hat.

**Noch nicht angeschlossen: `activated`**

`BuddyService.ask` wird gerade um die App-Hilfe (`BuddyAppGuide`) erweitert. Dort jetzt eine Zeile reinzuschreiben kollidiert mit dieser Änderung. Der Aufruf, sobald `ask` stillsteht:

```dart
await ProductEvents.noteAnswer(text);
```

Nur für die fertige Antwort von LocalBuddy, dem Agenten oder `/ai/chat`. Nicht für `BuddyAppGuide`: der zitiert `4,99 €` und würde sonst jede Preisfrage als Aktivierung zählen. Kommt im Stream `BuddyService.restart` (`\u0000restart`), zählt nur der Text danach.

`ProductEvents.send` ist null. Nichts verlässt das Telefon, bis ein `POST /events` existiert. Bis dahin stehen `activated`, `d1`, `d7`, `trial_start` und `paid` nur auf dem jeweiligen Gerät (`debugPrint` und die Settings-Keys `pe_*`). Im Montagsblatt steht dort „nicht erhoben“, nicht eine Schätzung.

Referral als Kanal zählt erst, wenn `ref` auf einem fremden Gerät ankommt. Unbekannte Codes speichert `Growth.join` nicht.

## Ein Kanal, vier Wochen

**Instagram Reels. Ein Konto. Nur der Satz „Was mach ich mit meinem Gehalt?“.**

Kein zweites Netz, keine Ads, kein Subreddit. Der Satz ist einer, den jemand am Zahltag laut sagt. Reels ist der Ort, an dem er schon weitergegeben wird, und eine Person kann ihn ohne Budget posten.

Attribution: ein echter Code, deiner aus der Waitlist oder aus `/invite`. Unbekannte `ref`s fallen weg. Bio-Link: Landing mit `?ref=DEINCODE`. Neue Zeilen in `growth.json` mit diesem `ref` sind der Kanal. Ohne `ref` ist unzugeordnet und zählt nicht als Reel.

Beispiel auf dem Bildschirm als Beispiel beschriften. Die fest verdrahteten Demo-Plätze der Landing nicht zeigen.

- **16.–22. Nov.** Vier Reels, werktags. Erstes Bild: der Satz, gesprochen. Zweites: eine Zahl. Letztes: „Link in der Bio, Warteliste.“ Die zweite Zeile wechselt, der Satz nicht: Miete, Dispo, was übrig bleibt, Sparrate.
- **23.–29. Nov.** Die zweite Zeile behalten, die Signups mit dem Code gebracht hat. Vier weitere in der Form. Jeden Kommentar mit einer Frage beantworten, demselben Satz, ohne zweiten Link. Null Signups: die zweite Zeile wechseln, nicht den Kanal.
- **30. Nov.–6. Dez.** Zahltag ist Montag, der 30. Drei Reels: Freitag der 27. („Montag kommt Gehalt“), Montag der Satz, Dienstag „was übrig ist“. Das Reel mit den meisten Signups anpinnen.
- **7.–13. Dez.** Kein neues Motiv. Den Gewinner zweimal neu posten. Freitag aufschreiben: Stunden, Signups mit dem Code, Aktivierte — und wenn Aktivierte noch „nicht erhoben“ sind, die Entscheidung nur auf Signups stützen und das dazuschreiben. Unter 20 Signups mit dem Code: Kanal stoppen. TikTok nicht in derselben Woche aufmachen. Die eine Zahl: Stunden pro Signup.

## Montagsblatt (20 Minuten, von Hand)

Neue Zeilen seit letztem Montag. Leer lassen, was du nicht gezählt hast.

1. **Waitlist.** Einträge mit `joinedAt` in der Woche, davon mit deinem Reel-`ref`. Quelle: Server-Log `product_event` und `growth.json`. Mails nicht in das Blatt, nicht in ein Deck.
2. **Aktiviert.** Erst wenn `noteAnswer` hängt und `send` auf einen Server zeigt. Bis dahin: „nicht erhoben“.
3. **D1.** Anteil der Leute, die vor 8–14 Tagen aktiviert wurden und `d1` haben. Kohorte jünger als ein Tag: „zu früh“.
4. **D7.** Dieselbe Regel, Kohorte mindestens sieben Tage alt. Sonst „zu früh“. Woche 1 hat kein D7.
5. **Trial.** Stripe-Subscriptions, die diese Woche auf `trialing` gegangen sind, plus Probezeiten in App Store Connect. Demo-Checkout nicht mitzählen. Das eigene Telefon nicht mitzählen.
6. **Paid.** Von `trialing` auf `active`, abzüglich Refunds und Widerrufe derselben Woche. Probezeit ist nicht Paid. Stripe und Store addieren, nicht mitteln.
7. **Bank.** Zeilen `bank_connect` im Server-Log. Ohne Enable-Banking-Vertrag: „nicht live“.

Craches, NPS und „Freunde im TestFlight“ stehen nicht auf dem Blatt.

## Was du mit diesen Zahlen nicht sagst

- Eine Kurve, solange Aktivierte „nicht erhoben“ sind. Waitlist-Größe ist kein WAU.
- Die Demo-Plätze der Landing, eine Bank, die nicht live ist, Refunds, die du nicht abgezogen hast.
- Dass D7 die Waitlist misst. Der Nenner ist die Aktivierungskohorte.
- Zwei Kanäle oder einen Creator, bevor die vier Wochen Freitag haben.
