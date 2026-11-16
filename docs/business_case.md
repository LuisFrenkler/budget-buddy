# Ahead — Investor Business Case

**Stand:** November 2026 · **Stage:** Pre-Seed / Soft Launch · **Markt:** DACH, Fokus DE  
**Produkt:** Ahead (ehem. BudgetBuddy) — KI-Finanzcoach „Buddy“ für junge Erwachsene

> **Investment-These:** Die meisten deutschen Money-Apps zeigen *was du hast*. Ahead beantwortet *was du als Nächstes tun kannst* — mit den echten Zahlen des Nutzers, in den Momenten, die bei 18–30 entscheiden (Urlaub, Umzug, erster Job, Abos). Das ist kein weiteres Multibanking; das ist eine Entscheidungs-Schicht darüber.

---

## 1. Executive Summary

| | |
|---|---|
| **Problem** | Junge Erwachsene in DE tracken Geld in Banking-Apps, treffen Kauf-/Lebensentscheidungen aber weiterhin mit Bauchgefühl oder generischem ChatGPT ohne ihre Zahlen. |
| **Lösung** | **Buddy** — chat-first Coach, der Ausgaben, Budgets, Abos und Szenarien *des Nutzers* nutzt. Offline-fähig, consent-gated Cloud-KI, keine IBANs an Modelle. |
| **Keil (Wedge)** | *„Frag Buddy, bevor du buchst.“* — Affordability + Abo-Druck + Monats-Prognose. Bank/Depot sind Datenquellen, nicht das Produkt. |
| **Modell** | Freemium → **Ahead Plus** 4,99 €/Monat bzw. 39,99 €/Jahr (7 Tage Trial). |
| **Status** | End-to-end Produkt (Flutter + Dart-Backend + Vault + PSD2-Pfad + Buddy-Agent) soft-launch-fähig; Store-/Legal-/Bank-Ops noch offen. |
| **Ask (Vorschlag)** | **150–250 k€ Pre-Seed** für 12–18 Monate: Go-to-Market, Trust/Legal, kommerzielle Bankanbindung, Conversion-Loop Buddy→Plus. |

Warum Investoren jetzt einsteigen: **Produkt und Positionierung sind gebaut**, der Markt (Gen Z + Open Banking + KI) ist heiß, aber **noch niemand in DE besitzt klar den „Decision Coach“-Slot** — Finanzguru besitzt Tracking/Verträge, Finanzfluss besitzt Content/Depot. Ahead zielt auf die Lücke dazwischen.

---

## 2. Problem

### Was heute passiert

1. **Überblick ohne Entscheidung.** Banking- und Multibanking-Apps (Hausbank, Finanzguru, Copilot) beantworten „Was habe ich?“ — selten „Kann ich mir X leisten, ohne mein Polster zu killen?“
2. **Generische KI ohne Kontext.** ChatGPT/Claude kennen keine echten Umsätze, Abos und Budgets. Nutzer copy-pasten Screenshots — unsicher, ungenau, nicht handlungsfähig.
3. **Lebensphasen-Stress.** Erster Job, Umzug, WG, Jobwechsel: hohe finanzielle Unsicherheit, wenig Beratung, die sich junge Leute leisten oder der sie vertrauen.
4. **Abo-Leakage.** Streaming, Fitness, Tools — Preiserhöhungen und „vergessene“ Verträge sind Alltag; Erkennung allein reicht nicht, wenn niemand zum Kündigen/Umplanen nudgt.

### Evidenz (Markt, nicht Traction)

- ~95 % der 16–29-Jährigen in DE nutzen Online-Banking (Bitkom Digital Finance 2025).
- 82 % der Gen Z nutzen die Banking-App zur Finanzkontrolle; Multibanking-Apps nur ~8 % (ING/Visa). → **Raum für eine Schicht über der Hausbank**, die nicht „noch eine Bank-App“ sein muss.
- Finanzguru kommuniziert ~1,5 Mio. Nutzer und eine sehr breite Zielgruppe — Beweis, dass DE Personal Finance massenmarkttauglich ist; gleichzeitig Fokus auf Konten/Verträge, nicht auf Coach-Entscheidungen.

---

## 3. Lösung & Produkt

### Kernprodukt: Buddy

Buddy ist ein **tool-using Agent** mit den Finanzdaten des Nutzers:

- Fragen wie „Kann ich mir 800 € Urlaub leisten?“ → Rechnung aus Restbudget, Abos, Zielen
- Was-wäre-wenn-Simulator (Abos pausieren, Einmalausgaben, Sparrate)
- Natürliche Erfassung („Döner 8,50 gestern“) und Beleg-Scan
- Abo-/Vertragserkennung inkl. Preisanstieg
- Proaktive Tipps und **Next-Step-Buttons** (nicht nur Text)
- Offline-Fallback (`LocalBuddy`) wenn keine Cloud-KI / kein Consent
- Privacy by design: lokale Hive-Daten, optional AES-Vault, keine IBANs in KI-Summaries

### Bewusst sekundär

PSD2-Bank (Enable Banking), Depot, Splits, grobe Rentenlücke — **Kontext für Buddy**, nicht Store-Hero. Das schützt vor Feature-Parity-Krieg gegen Finanzguru/Copilot.

### Marke

**Ahead** — „Your buddy for money and the future.“ Früher BudgetBuddy; Repositionierung auf Coach-first ist Teil der Investment-Story (Klarheit vor Feature-Liste).

---

## 4. Markt

Alle Größen sind **Annäherungen mit Annahmen** — für Investorengespräche als Modell, nicht als auditierte Zahlen.

### TAM (DACH Personal Finance Apps / Coaching-Schicht)

| Ebene | Definition | Größenordnung |
|---|---|---|
| **TAM** | Online-Banking-Nutzer DE mit Smartphone-First Finanzen (~47 Mio. laut Finanzguru-Branchenlogik; Bitkom: 86 % Online-Banking gesamt) | sehr groß, nicht unser Fokus |
| **SAM** | 18–34 in DE, die aktiv Ausgaben steuern / budgetieren wollen (~10–12 Mio. Altersgruppe; konservativ 25–35 % „money-interested“ ≈ **2,5–4 Mio.**) | Kernadresse |
| **SOM (36 Monate)** | 0,5–1,5 % von SAM als registrierte Nutzer ≈ **15–40 k**; davon 8–15 % Paying Plus | Early scale |

### Warum der Timing stimmt

| Treiber | Bedeutung für Ahead |
|---|---|
| Gen Z = App-native Banking | Kein Erklärungsaufwand für Mobile-first |
| KI-Erwartung | Nutzer akzeptieren Chat als Interface — aber wollen *eigene* Zahlen |
| Abo-Wirtschaft | Hoher wiederkehrender Schmerz, den Buddy greifbar macht |
| Privacy-Diskurs DE | Local-first + Consent ist Verkaufsargument, nicht nur Compliance |
| Lücke im Wettbewerb | Tracking und Content sind besetzt; **Decision Coach** noch nicht |

---

## 5. Wettbewerb & Differenzierung

| Spieler | Stärke | Lücke vs. Ahead |
|---|---|---|
| **Finanzguru** | Banken, Verträge, Marke, Capital | Dashboard/Verträge-first; KI ist Begleiter, nicht Entscheidungs-Keil |
| **Finanzfluss Copilot** | Content-Marke, Vermögen/Depot | Anleger-lastig; teurer PLUS; wenig „Alltags-leisten“ |
| **AI Money / ähnliche** | KI-Eingabe, Belege | Weniger tiefes Finance-OS (Budgets, Szenarien, Vault, Agent-Tools) |
| **MoneyCoach** | Apple-Ökosystem, Privacy | Kein Android; kein chat-first Coach für DE-Lebensphasen |
| **Hausbank-Apps** | Tägliche Habit | Kein plattformübergreifender Coach, kein „kann ich mir X“ |
| **ChatGPT** | Starke Konversation | Kennt die Zahlen nicht; keine Buchung, kein Abo-Graph |

### Moat-Pfad (was Investoren hören wollen)

1. **Datennetzwerk-Effekt im Kleinen:** gelernte Händlerregeln, Abo-Graph, Kategorie-Coach → bessere Antworten mit der Zeit  
2. **Lebensphasen-Playbooks** (Produktisierung von Umzug / erster Job / WG) — Content+Agent, schwer nur mit Multibanking zu kopieren  
3. **Vertrauen:** local-first, ehrliche Disclaimers, DE UX — Wechselkosten steigen mit Vault + Historie  
4. **Nicht:** „mehr Banken als Finanzguru“ — das gewinnen wir nicht und brauchen wir für den Keil nicht

**Positionierungssatz fürs Pitch-Deck:**  
*Ahead is the money decision layer for young adults in Germany — Buddy answers with your numbers, before you spend.*

---

## 6. Geschäftsmodell

### Preise (live im Produkt)

| | Free | Ahead Plus |
|---|---|---|
| Preis | 0 € | **4,99 €/Monat** oder **39,99 €/Jahr** (~3,33 €/Monat) |
| Trial | — | 7 Tage |
| Buddy KI | 5 Fragen / Monat | unbegrenzt |
| Belege | 3 Scans | unbegrenzt |
| Sparziele | 1 | unbegrenzt |
| Offline-Buddy, Budgets, Abos | ja | ja |

### Unit Economics (Modell — Annahmen markiert)

| Annahme | Wert | Kommentar |
|---|---|---|
| Blended ARPU Paying | ~4,20 €/Monat | Mix Monat/Jahr |
| Gross margin Ziel | 70–85 % | nach LLM + Bank-API + Store-Fees |
| LLM-Kosten/aktive Plus-Frage | ~0,001–0,01 € | Gemini Flash / Haiku-Pfad |
| CAC Ziel (organisch + Creator) | 8–20 € | Early; paid social später testen |
| Payback Ziel | < 4 Monate | bei ≥10 % Free→Plus der aktiv Fragenden |
| Churn Ziel Jahr 1 | < 8 % Monat (Monatstarif) / deutlich niedriger Jahr | Coach-Habit + Abo-Alerts |

**Hebel:** Nicht „mehr Features“, sondern **Fragen die konvertieren** (Affordability, Abo-Druck) und Playbooks die Retention erzeugen.

### Erweiterte Revenue-Optionen (Phase 2+, nicht Pre-Seed-Kern)

- B2B2C (Arbeitgeber / Uni / Genossenschaftsbanken White-Label Coach)  
- Affiliate nur wo trust-kompatibel (z. B. Tagesgeld-Vergleich) — bewusst nachrangig, um Coach-Glaubwürdigkeit zu schützen  

---

## 7. Go-to-Market

### ICP

- 18–30 Jahre, DE, erstes eigenes Gehalt oder Jobwechsel  
- Nutzt schon Banking-App, führt aber kein diszipliniertes Haushaltsbuch  
- Fragt sich konkret: Urlaub, Technik-Kauf, WG-Umzug, „wo geht mein Geld hin?“  

### Motion (12 Monate)

1. **Soft Launch:** TestFlight / Play Internal → Freundeskreis + Creator-Codes (`CREATOR60`, `BUDDY30`)  
2. **Content-Wedge:** kurze Clips „Buddy rechnet live“ (TikTok/Reels/Shorts) — eine Frage, eine Zahl, ein CTA  
3. **Campus & Community:** Unis, Azubi-Netzwerke, WG-Gruppen — Splits als Viralschleife  
4. **ASO:** Untertitel *KI-Coach für dein Alltagsgeld*; Screenshots Buddy-first  
5. **Bank:** Demo/Waitlist bis Nachfrage; dann Enable Banking commercial — nicht als Launch-Blocker für den Coach-Keil  

### North-Star-Metriken

| Metrik | Warum |
|---|---|
| Wöchentliche Buddy-Fragen / User | Engagement am Keil |
| „Affordability“-Fragenanteil | Product-Market-Fit Signal |
| Free→Plus Conversion (Tag 7 / Tag 30) | Monetarisierbarkeit |
| Abo erkannt → Aktion (Pause/Kündigungshinweis) | Outcome, nicht Vanity |
| D7 / D30 Retention | Habit |

---

## 8. Traction & Status (ehrlich)

**Was gebaut und getestet ist**

- Flutter-App (iOS/Android/Web-Pfad), Dart-Backend  
- Auth, lokales Finance-OS, Cloud-Vault (AES-256-GCM)  
- Buddy (Cloud + Offline), Quotas, Consent, Actions, Entries  
- Verträge/Abos, Budgets, Prognose/Simulator, Sparziele, Splits  
- Plus-Gates, Stripe-Web + Store-Verify-Hooks  
- Umfangreiche UX-Härte + Testsuite (laut Launch-/UX-Docs launch-nah)

**Was noch fehlt für Public Scale**

- Store-Submit Ops (Signing, Live-IAP, Privacy/Impressum final)  
- Kommerzielle PSD2-Produktion  
- Messbare externe Traction (Downloads, Paying, Retention) — **Pre-Seed-Realität**  
- Marken-Rollout Ahead in Landing/Store (README bereits repositioniert)

Investoren investieren hier in **Execution + Keil-Klarheit**, nicht in bereits skalierte ARR.

---

## 9. Team

**Luis Frenkler** — Solo-Founder, Full-Stack: Flutter-Client, Backend, Vault, Bank-Sync, Buddy-Agent, Soft-Launch-Pfad.

**Pre-Seed-Implikation:** Capital finanziert vor allem *Distribution, Trust und Tempo* — und optional erste kritische Rollen (Growth/Content oder Teilzeit Legal/Compliance), nicht ein Rewrite des Produkts.

---

## 10. Ask, Use of Funds, Meilensteine

### Ask (Vorschlag zum Pitch)

**150–250 k€** als Pre-Seed (SAFE/Equity nach Gespräch), Runway **12–18 Monate**.

| Verwendung | Anteil | Wofür |
|---|---|---|
| Go-to-Market & Creator | 35–45 % | Clips, Creator-Deals, ASO, Campus |
| Trust & Legal | 15–20 % | Anwalt AGB/Datenschutz/KI, Impressum, Store-Compliance |
| Infrastructure & Bank | 15–20 % | EU-Hosting, Enable Banking commercial, Monitoring |
| Product (Keil vertiefen) | 15–25 % | Lebensphasen-Playbooks, Proaktivität, Conversion-Loops |
| Buffer | 5–10 % | Apple Dev, Reserven |

### 18-Monats-Meilensteine (für Diligence)

| Zeitraum | Ziel |
|---|---|
| 0–3 Mon. | Public Soft Launch Ahead-Brand; 1.000 registrierte Nutzer; Buddy-Fragen als NS |
| 3–9 Mon. | 10 k registriert; ≥8 % der aktiven Fragenden auf Plus-Trial; erste Creator-Pipeline |
| 9–18 Mon. | 25–40 k registriert; belastbare Unit Economics; Seed-ready mit Retention-Story |

*(Zahlen sind Ziele/Modelle, keine Zusagen.)*

---

## 11. Risiken & Mitigation

| Risiko | Mitigation |
|---|---|
| Feature-Krieg gegen Finanzguru | Keil halten; nicht Bankenliste optimieren |
| KI = austauschbar | Eigene Tools, Offline, Playbooks, Outcomes messen |
| Regulierung / „Beratung“ | Klare Disclaimers; keine Anlage-/Rechtsberatung; Orientierung statt Advice |
| Bank-API-Kosten | Coach ohne Bank nutzbar; Bank hinter Nachfrage |
| Solo-Founder-Key-Person | Runway + dokumentierter Code; erste Hire entlang GTM |
| Markenverwirrung BudgetBuddy/Ahead | Einheitlicher Ahead-Rollout in Store + Landing (Priorität) |

---

## 12. Warum jetzt / warum Ahead

1. **Produkt existiert** — nicht nur Slideware.  
2. **Klarer Keil** gegen besetzte Incumbents.  
3. **Struktureller Rückenwind:** Gen Z × KI × Abo-Wirtschaft × Privacy.  
4. **Kapitaleffizienter Early Path:** Soft Launch ohne sofortigen Bank-CapEx; LLM-Kosten kontrollierbar.  
5. **Upside:** Decision Layer kann später B2B2C und tiefere Life-Stage-Produkte tragen, ohne den Kern zu verraten.

---

## Anhang A — One-Pager Pitch

**Ahead** hilft jungen Erwachsenen in Deutschland, Geld-Entscheidungen *mit ihren echten Zahlen* zu treffen.  
**Buddy** antwortet auf „Kann ich mir das leisten?“, erkennt Abos und simuliert den Monat — privat, auf Deutsch, chat-first.  
Wir verkaufen nicht Multibanking. Wir verkaufen **Klarheit vor dem Kauf**.  
**Plus 4,99 €/Monat.** Pre-Seed **150–250 k€**, um Distribution und Trust hinter ein bereits gebautes Produkt zu legen.

## Anhang B — Quellen (Auswahl)

- Bitkom, Digital Finance 2025 (Online-Banking-Penetration)  
- ING / Visa Gen-Z-Banking-Analyse (App-Nutzung zur Finanzkontrolle)  
- Branchenberichte zu Finanzguru-Nutzerzahlen / Personal-Finance-App-Rankings DE  
- Interne Produkt-/Launch-Docs: `docs/launch.md`, `docs/store_listing_de.md`, README

## Anhang C — Verwandte Docs

- **Pitch Deck (Guy Kawasaki 10 / WHU MiE):** [pitch_deck.md](pitch_deck.md) · [pitch_deck.html](pitch_deck.html) · [Luis_Frenkler_PitchDeck.pdf](Luis_Frenkler_PitchDeck.pdf)  
- Produktpositionierung & Tech: [README](../README.md)  
- Soft-Launch: [launch.md](launch.md)  
- Store-Listing DE: [store_listing_de.md](store_listing_de.md)
