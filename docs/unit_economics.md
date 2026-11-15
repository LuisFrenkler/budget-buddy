# Ahead Plus — Unit Economics

Stand 15. November 2026. Serviette zu der Frage, ob 4,99 € trägt. Keine Nutzungs-Logs. Cent-Zahlen zur KI sind Schätzungen aus der Prompt-Größe und der öffentlichen Preisliste, jedes Mal als Schätzung markiert.

## Break-even

Nach 19 % deutscher Umsatzsteuer und 15 % Store-Anteil bleiben von 4,99 € **3,56 €** im Monat. Hosting liegt bei 100 Zahlenden unter 5 % dieser Auszahlung.

Eine typische Buddy-Frage liegt auf der Haiku-5.5-Liste bei etwa **0,16 US-Cent**, auf Sonnet 5.5 bei etwa **3 US-Cent** (Schätzung, Form unten). Arbeitswert der Tabellen: **1,5 Euro-Cent** je Frage, das Mittel aus beiden, mit 1 USD = 0,92 €. Davon bezahlt die Monats-Auszahlung rund **240 Fragen**. Der Tagesdeckel im Server greift davor.

4,99 € trägt, solange ein Zahler bei einigen Dutzend Fragen im Monat bleibt und der Alltag auf Haiku liegt. Die Kohorte kippt, wenn **rund ein Drittel der Zahler** jeden Tag am Sonnet-Deckel hängt: etwa **9 €** Modellkosten gegen **3,56 €** Auszahlung. Auf dem Jahrestarif (2,38 € Auszahlung im Monat) reicht dafür **etwa ein Fünftel**.

30 Gratis-Fragen kosten unter demselben Arbeitswert **0,45 €**, wenn jemand das Kontingent leer macht. Ab etwa **sieben** solchen Free-Nutzern pro Zahler ist der Deckungsbeitrag weg. Solange Free auf dem Gemini-Free-Tier läuft, ist diese Zeile 0 €. Das Risiko ist dann der Stopp, wenn Googles Kontingent voll ist.

## Was der Code verkauft

Quelle: `PlusService`, `backend/server.dart`.

| | |
| --- | --- |
| Monat | 4,99 € brutto (`monthlyCents` 499) |
| Jahr | 39,99 € brutto (`yearlyCents` 3999), Anzeige 3,33 €/Monat |
| Trial | 7 Tage, 0 €. Promo-Codes legen 14–60 freie Tage obendrauf |
| Free | 30 KI-Fragen, 3 Beleg-Scans, 1 Sparziel pro Monat. Einladungen erhöhen die Fragen |
| Plus | Fragen, Scans und Ziele ohne Produktlimit |
| Server, alle Konten | 50 Fragen/Tag (`AI_DAILY_LIMIT`) und 0,50 $ kodierte Tageskosten (`AI_DAILY_COST_USD`) |

Die 30 stehen im Client. Der Server prüft sie nicht. Free und Plus laufen in denselben Tagesdeckel.

## Was eine Frage kostet

Schätzung, kein Meter aus Produktion. Der Agent schickt System-Prompt plus Werkzeugschema (im Quelltext grob 4.000 bzw. 19.000 Zeichen, zusammen in der Größenordnung **8.000 Tokens** Prefix inklusive kurzem Kontext). Eine normale Frage sind zwei Schritte: Werkzeug, dann kurze Antwort. Der Prefix wird einmal in den 5-Minuten-Cache geschrieben und im zweiten Schritt gelesen. Output zusammen etwa 700 Tokens. Eine schwere Frage: vier Schritte, etwa 6.000 Output-Tokens, wachsender frischer Input. `output_config.effort` ist `medium` auf Haiku und `high` auf Sonnet; Thinking zählt als Output. `max_tokens` ist 8.000, `maxSteps` ist 6. Prompts dieser Größe bleiben unter 100.000 Tokens, also im günstigen Haiku-Band.

Listenpreise, abgerufen 15. Nov 2026 (USD pro 1 Mio. Tokens). Haiku 5.5 bis 100k: Input 0,10, Output 0,50, Cache-Write 0,125, Cache-Read 0,01. Sonnet 5.5: Input 2, Output 10, Cache-Write 2,50, Cache-Read 0,10. Gemini 3.5 Flash, letzte veröffentlichte Paid-Liste: Input 1,50, Output 9. Quelle: [Anthropic Pricing](https://platform.claude.com/docs/en/about-claude/pricing), [Haiku 5.5](https://platform.claude.com/docs/en/models/haiku-5-5/overview). Gemini ist der Default in `Ai`, wenn kein Anthropic-Key gesetzt ist; der Free Tier berechnet 0 $, bis Google ablehnt.

| Form | Haiku 5.5 | Sonnet 5.5 | Gemini 3.5 Flash, paid, ohne Cache |
| --- | ---: | ---: | ---: |
| Boden (ein Schritt, Cache-Treffer, kurzer Output) | 0,02 ¢ | — | — |
| Typisch (zwei Schritte) | 0,16 ¢ | 3,0 ¢ | 3,2 ¢ |
| Schwer (vier Schritte, viel Thinking) | 0,6 ¢ | 11 ¢ | — |

Cent in USD. „—“ heißt: nicht gerechnet, die Zelle würde die Entscheidung nicht ändern. Der Router `pickModel` legt Fragen über 160 Zeichen und ein breites Muster (unter anderem warum, Jahr, Plan, Wohnung, Kredit) auf Sonnet. Der Anteil ist ungemessen. Deshalb der Arbeitswert 1,5 Euro-Cent als Mitte, und die Sonnet-Spalte als die teure Hälfte.

`BuddyAgent.prices` steht noch auf 1 $/5 $ für Haiku 5.5 und 3 $/15 $ für Sonnet 5.5. Das ist etwa das Zehnfache der Haiku-Liste und das Anderthalbfache der Sonnet-Liste (Haiku 4.5 lag bei 1 $/5 $). Der Kommentar in `ai.dart` („etwa 0,1 Cent“) trifft die heutige Haiku-Liste besser als die Map. `costUsd` und der 0,50-$-Deckel rechnen mit der Map. Wer den Deckel jeden Tag ausreizt, zahlt bei Listenpreisen ungefähr **1,40 € im Monat auf Haiku** und **9 € im Monat auf Sonnet**.

Beleg-Scans (Bild, Free gedeckelt auf 3) und eine spätere Enable-Banking-Gebühr pro Konto fehlen in allen Cent-Zahlen.

## Hosting

`docs/backend_host.md`: ein Hetzner CX22 in Falkenstein oder Nürnberg, grob 4 € im Monat, plus Domain. In den Szenarien unten stecken **15 € Fixkosten** bis 1.000 Zahlende (Server, Domain, Apple Developer 99 € im Jahr) und **50 €** bei 10.000. Beides ist klein gegen die Auszahlung. Ein größerer VPS ändert die Schlusszeile nicht.

## Was vom Preis übrig bleibt

Annahme für den Store in Deutschland: Apple und Google sind Händler, ziehen 19 % USt vom Bruttopreis und danach ihre Provision ab, und überweisen den Rest. Das ist die übliche Mechanik, keine Steuerberatung. 15 % ist das Band unter 1 Mio. $ Umsatz (Small Business bzw. Googles erste Million). 30 % ist der Listen-Satz darüber bzw. ohne Programm.

| Tarif | Brutto | Nach USt | Auszahlung 15 % | Auszahlung 30 % | davon pro Monat |
| --- | ---: | ---: | ---: | ---: | ---: |
| Monat | 4,99 € | 4,19 € | 3,56 € | 2,94 € | wie links |
| Jahr | 39,99 € | 33,61 € | 28,56 € | 23,52 € | 2,38 € / 1,96 € |

Stripe im Web (Karte, SEPA, Klarna) ist ein anderer Vertrag: Gebühr plus eigene USt, hier nicht als Basis. Der Trial überweist 0 €.

## Deckungsbeitrag bei 100 / 1.000 / 10.000 Zahlenden

Annahme, Basis: nur Monatstarif, 15 % Cut, 30 Fragen pro Zahler und Monat, 1,5 Euro-Cent je Frage, kein Free-Verbrauch, Trial schon vorbei. 30 Fragen sind das Free-Kontingent und damit eine lesbare Mitte, kein gemessener Plus-Schnitt.

LLM = 0,45 € je Zahler. Deckungsbeitrag vor Fixkosten = 3,56 − 0,45 = **3,11 €**.

| Zahlende | Auszahlung | LLM | Fix | Übrig | je Zahler |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 100 | 356 € | 45 € | 15 € | 296 € | 2,96 € |
| 1.000 | 3.564 € | 450 € | 15 € | 3.099 € | 3,10 € |
| 10.000 | 35.640 € | 4.500 € | 50 € | 31.090 € | 3,11 € |

Dieselbe Last, andere Auszahlung, je Zahler und Monat vor Fixkosten:

| | Auszahlung | LLM | Übrig |
| --- | ---: | ---: | ---: |
| Monat, 30 % | 2,94 € | 0,45 € | 2,49 € |
| Jahr, 15 % | 2,38 € | 0,45 € | 1,93 € |
| Jahr, 30 % | 1,96 € | 0,45 € | 1,51 € |

30 % und der Jahrestarif lassen diese Mitte positiv. Der Puffer bis zur Null ist die Fragenzahl: Monat 15 % rund 240, Monat 30 % rund 200, Jahr 15 % rund 160, Jahr 30 % rund 130 Fragen zu 1,5 Cent.

Stress, jeder Zahler jeden Tag am Sonnet-Deckel (9 € LLM, Monat 15 %):

| Zahlende | Auszahlung | LLM | Fix | Übrig |
| ---: | ---: | ---: | ---: | ---: |
| 100 | 356 € | 920 € | 15 € | −579 € |
| 1.000 | 3.564 € | 9.200 € | 15 € | −5.651 € |
| 10.000 | 35.640 € | 92.000 € | 50 € | −56.410 € |

Anteil am Deckel, ab dem die Mischung aus „30 Fragen, 1,5 Cent“ und „Deckel-Sonnet“ null wird: etwa **35 %** der Zahler auf Monat 15 %, etwa **22 %** auf Jahr 15 %.

## Free-Tier, 30 Fragen

Dieselbe Cent-Spanne, ein Nutzer, der die 30 wirklich stellt. Gemini-Free-Tier: 0 €, danach Fehlermeldung statt Rechnung (`quotaMessage`).

| Modell-Annahme | 30 Fragen |
| --- | ---: |
| Haiku typisch | 0,04 € |
| Arbeitswert 1,5 Cent | 0,45 € |
| Sonnet typisch | 0,83 € |
| Sonnet schwer, 10 Euro-Cent | 3 € |
| Tagesdeckel, einen Monat, Sonnet-Liste | 9 € |

Der letzte Wert ist das, was ein Konto auf dem Server tatsächlich anrichten kann. Die 30 sind die Produktregel.

Bei 3,11 € Deckungsbeitrag je Zahler (Basis oben) tragen 100 Zahlende rund **660** Free-Nutzer mit vollen 30 Fragen auf dem Arbeitswert, also etwa sieben pro Zahler, nach Abzug der Fixkosten. Wer im Free nur ein paar Fragen stellt, bewegt die Grenze kaum. Wer sie leer macht und auf Sonnet landet, bewegt sie sofort.

## Was wahr sein muss, damit 4,99 € funktioniert

1. **Der Alltag bleibt auf Haiku 5.5 in der Nähe von 0,10 $ / 0,50 $.** Sobald `pickModel` einen großen Teil auf Sonnet legt, gilt die 3-Cent-Spalte, und rund 130 solche Fragen fressen die Monats-Auszahlung. Der Anteil ist heute eine Vermutung.
2. **Thinking bleibt kurz.** Ein Schritt, der in die Nähe von 8.000 Output-Tokens läuft, kostet auf Sonnet grob 8 US-Cent plus Input. Sechs solche Schritte sind ein Vielfaches von 4,99 €. Der kodierte Tagesdeckel ist die Bremse, und er rechnet mit den alten Sätzen.
3. **Der Zähler wird an die Liste angeglichen.** Bis dahin heißt 0,50 $ am Tag auf Haiku real etwa 5 US-Cent und auf Sonnet etwa 33 US-Cent. Der Deckel bremst Haiku früh und Sonnet spät. Die teure Lücke ist die späte.
4. **15 % Store-Cut.** 30 % lässt die Mitte positiv und verkürzt die Fragen bis zur Null von etwa 240 auf etwa 200. Beides setzt voraus, dass 4,99 € und 39,99 € Bruttopreise sind und die USt vor der Provision abgeht.
5. **Free bleibt billig.** Entweder das Gemini-Free-Tier trägt den Soft Launch, oder volle 30er-Nutzer bleiben unter etwa sieben pro Zahler. Der Tag, an dem der Anthropic-Key auch für Free gilt, ist der Tag, an dem die 0,45 € real werden.
6. **Der Jahrestarif wird mit seiner Auszahlung gerechnet, nicht mit 3,33 €.** 3,33 € ist der Bruttopreis geteilt durch zwölf. Ankommen tun 2,38 € oder 1,96 €.
7. **Trial und Promos bleiben menschlich.** Sieben Tage am Sonnet-Deckel sind grob 2 € bei 0 € Umsatz. Vertretbar. Eine Bot-Kohorte auf demselben Deckel ist ein eigener Posten. Promo-Codes verlängern die freie Zeit auf bis zu 67 Tage.
8. **Support und Gründerzeit stehen außerhalb.** Eine Viertelstunde Hilfe pro Zahler und Monat kostet mehr als die API in der Basis-Tabelle. Bei 10.000 Zahlenden sind die 31.000 € übrig nur wahr, wenn kaum jemand schreibt und niemand eine Bank-Gebühr pro Konto dazukommt.

## Was diese Serviette nicht weiß

- Tokens, Schritte und Modellmix echter Fragen.
- Trial zu Paid, Refunds, Monat gegen Jahr.
- Das zahlenmäßige Limit des Gemini-Free-Tiers.
- Ob `gemini-3.5-flash` noch zu dem Satz 1,50 $ / 9 $ abgerechnet wird. Die Id ist seit Oktober 2026 von Google als weitergeleitet beschrieben; der Code nennt sie trotzdem als Default.
- Enable Banking, E-Mail, Sentry, Beleg-Bilder.
