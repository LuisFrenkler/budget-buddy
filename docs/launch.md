# Launch checklist (DE)

Produkt-Kern (Auth, Vault, Buddy, Splits, Plus-Logik, Bank/Depot-Demo) ist launch-fähig.
Store-Submit braucht noch die Ops-/Legal-Punkte unten.

## Was schon läuft

- Konto: Register / Login / Profil / Löschen
- Lokale Finanzen + Cloud-Vault (AES, LWW)
- Buddy KI (Consent, Quotas, Offline-Fallback)
- Geteilte Ausgaben (Code + E-Mail-Suche)
- Plus-Gates, Stripe-Web + Store-Verify-Hooks
- Vermögen / Notgroschen / Vorsorge (lokal, jetzt auch in Backup/Vault)
- Profilbild (lokal + Vault-Sync)

## Günstigste Online-KI

1. Nur `GEMINI_API_KEY` setzen (Anthropic leer lassen) → Gemini Flash Free Tier.
2. Free-App: 5 Buddy-Fragen/Monat — Free-Tier reicht für Soft Launch.
3. Später Plus-Last: `ANTHROPIC_API_KEY` (Haiku, ~0,1 ¢/Frage).

## Günstigstes Hosting

- Hetzner CX (~3–5 €/Monat, EU) + Caddy/nginx (HTTPS)
- `.env`: `BIND=0.0.0.0`, `PUBLIC_URL=https://api…`, `TRUST_PROXY=1`,
  `CORS_ORIGINS=…`, `GEMINI_API_KEY=…` (kein `ALLOW_DEMO_BILLING` ohne Absicht)
- App-Builds: `--dart-define=BACKEND_URL=https://api…`
- Backend: Vault OCC+Locks, Concurrency-Cap, Graceful Shutdown, `/ready`

## MUST vor Store-Submit

1. `lib/legal/legal_info.dart` ausfüllen + Datenschutz/Impressum hosten
   (`https://luisfrenkler.github.io/budget-buddy-legal/datenschutz.html`)
2. Android: Release-Signing (nicht Debug) — Package ist jetzt `com.luisfrenkler.budgetbuddy`
3. `INTERNET` ist im Main-Manifest (erledigt)
4. Production-Backend HTTPS + CORS einschränken
5. Stripe live / IAP-Produkte + Apple/Google Verify-Keys
6. Bank öffentlich? → Enable Banking kommerziell, sonst Bank hinter Waitlist/Demo
7. Store: Screenshots (Buddy first), Privacy-URL, Abo-Gruppe, 7-Tage-Trial

## SHOULD kurz danach

- Passwort-Reset oder klarer Hinweis „Vault stirbt mit Passwort“
- Crash-Reporting (Sentry) + CI (`flutter test` / `dart test`)
- Anwaltspass AGB/Datenschutz (KI / US-Transfer)

## Soft Launch Pfad (2 Wochen)

1. Gemini + kleiner EU-VPS — **Anleitung:** [backend_host.md](backend_host.md)
2. TestFlight / Play Internal (Freunde) — **Schritt für Schritt:** [testflight.md](testflight.md)
   (Apple Developer Program ~99 €/Jahr ist Pflicht für TestFlight)
3. Bank nur Demo oder Waitlist
4. Plus mit Store-Sandbox
5. Dann Public + EB commercial wenn Nachfrage da ist
