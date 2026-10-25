# BudgetBuddy — Plan: Konto- & Depot-Anbindung

Stand: 2026-06. Dieser Plan beschreibt, wie aus BudgetBuddy (heute 100 % lokal,
Hive) eine App mit **echter Bankkonto- und Depot-Synchronisation** wird.

## Kernaussage

Eine echte Anbindung lässt sich **nicht rein in der App** lösen: API-Schlüssel
und OAuth-Token dürfen nie im Client liegen, und Browser blocken viele APIs per
CORS. Es braucht daher einen **kleinen Backend-Server** als Vermittler
(App → eigenes Backend → Aggregator/Bank). Das ist der eine, unvermeidbare
Architektur-Schritt.

```
[ BudgetBuddy App ] --HTTPS--> [ eigenes Backend ] --API--> [ Aggregator ] --> [ Bank / Broker ]
                                   (hält Secrets,
                                    Token, Refresh)
```

## 1. Bankkonto (Umsätze + Saldo) — Open Banking / PSD2

**Aggregatoren** (einer reicht):
- **GoCardless Bank Account Data** (ex-Nordigen) — kostenlose Stufe, deckt
  deutsche Banken (Sparkasse, DKB, ING, N26 …). Bester Start.
- Alternativen: Tink (Visa), finAPI, Klarna Kosma, Enable Banking, FinTS/HBCI.

**Ablauf:**
1. Nutzer wählt Bank → Backend startet beim Aggregator eine „Requisition".
2. Redirect zur Bank-Login-Seite, Nutzer bestätigt per SCA (TAN/App).
3. Aggregator liefert dem Backend Zugriff (Consent ~90 Tage gültig).
4. Backend holt **Saldo + Umsätze**, normalisiert sie und liefert sie der App.
5. App zeigt sie an / matcht sie auf BudgetBuddy-Kategorien.

**Grenzen:** Nicht sekündlich „live" — PSD2 erlaubt ohne erneutes Login ca.
**4 Abrufe/Tag**. Nach 90 Tagen muss der Nutzer den Consent erneuern.

**Recht/Compliance:** Um es **anderen Nutzern** anzubieten, brauchst du eine
**AISP-Lizenz** ODER du nutzt das **Agenten-/Umbrella-Modell** eines lizenzierten
Anbieters (GoCardless deckt das ab). Für reine **Eigennutzung** genügt die
GoCardless-Gratisstufe. Dazu: DSGVO (Einwilligung, Löschkonzept), Verschlüsselung
der Token (at rest), TLS überall.

## 2. Depot (Positionen) — schwieriger

- Die meisten **Retail-Broker (Trade Republic, Scalable, Comdirect)** haben
  **keine offene API**.
- **Aggregatoren:** Parqet-API (liest dein Depot), Wealthica. Manche Banken
  liefern **Depotbestände auch über PSD2**.
- **Realistisch heute schon nutzbar (ohne Backend):**
  - ✅ **Manuelle Eingabe + Live-Kurse** (bereits gebaut: Krypto live keylos,
    US-Aktien live mit Finnhub-Key/am Gerät).
  - ✅ **Broker-CSV-Import** (bereits gebaut: Profil → „Depot importieren (CSV)") —
    der pragmatische „Depot verbinden"-Weg ohne Server.

## 3. Backend — Vorschlag

- **Stack:** kleines Node-/Dart-/Go-Backend ODER Serverless (Cloud Functions).
- **Auth:** Firebase Auth / Supabase (Nutzer-Login).
- **Secrets:** Aggregator-Keys nur als Env-Variablen am Server.
- **Speicher:** verschlüsselte Token; optional Postgres für Umsatz-Cache.
- **Jobs:** täglicher Refresh (Cron) im Rahmen der PSD2-Limits.
- Dieselbe Backend-Schicht trägt auch den **Finnhub-Proxy** für Aktien-Kurse
  (löst das CORS-/Key-Thema aus #3 sauber).

## 4. Phasen & Aufwand

| Phase | Inhalt | Aufwand | Kosten |
|---|---|---|---|
| A (fertig) | Manuell + Live-Kurse + CSV-Import | – | 0 € |
| B | Backend + Finnhub-Proxy (Aktien live überall) | klein | Hosting ~5 €/Mon |
| C | GoCardless-Anbindung (Bank-Umsätze, eigenes Konto) | mittel | 0 € (Gratisstufe) |
| D | Veröffentlichung mit Bank-Sync für alle | groß | AISP/Umbrella + Recht |

## Empfehlung

1. **Jetzt:** CSV-Import + manuelles Depot + Live-Kurse nutzen (alles vorhanden).
2. **Nächster echter Schritt:** Phase B (kleines Backend als Proxy) — bringt
   sofort Aktien-Live-Kurse überall und ist die Basis für alles Weitere.
3. **Bank-Sync (Phase C/D)** als eigenes Projekt, wenn die App so weit ist.
