# BudgetBuddy

Persönliche Finanz-App in **Flutter** — Konto, Budgets, Verträge, Depot und Prognose in einer App.  
Daten liegen lokal auf dem Gerät; optional Konto mit verschlüsselter Cloud-Sicherung und echter Bankanbindung (PSD2).

<p align="center">
  <img src="docs/images/bb_readme_hero.jpg" alt="BudgetBuddy — Start mit Vermögen und Monatsprognose" width="720">
</p>

## Screenshots

<p align="center">
  <img src="docs/images/bb_readme_start.jpg" alt="Start: Vermögen und noch frei" width="140">
  <img src="docs/images/bb_readme_forecast.jpg" alt="Monats-Simulator Was wäre wenn" width="140">
  <img src="docs/images/bb_readme_buddy.jpg" alt="Buddy, KI-Finanzcoach" width="140">
  <img src="docs/images/bb_readme_konto.jpg" alt="Konto und Umsätze" width="140">
  <img src="docs/images/bb_readme_contracts.jpg" alt="Verträge und Abos" width="140">
  <img src="docs/images/bb_readme_depot.jpg" alt="Depot" width="140">
</p>

## Highlights

**Monatsprognose & Simulator**
- „Diesen Monat noch frei“ aus Einkommen, Fixkosten, Sparzielen und bisherigem Tempo
- **Was wäre wenn…?** — Abos auslassen, Einmalkauf setzen, Sparrate trimmen; Δ und Tempo live, nichts wird gespeichert

**Buddy (KI-Finanzcoach)**
- Fragen zu Ausgaben, Sparzielen, Verträgen — Antworten mit echten Zahlen aus der App
- Beleg-Scan und Schnellerfassung in Alltagssprache („Döner 8,50 gestern“)
- Offline-Antworten auf dem Gerät, wenn keine KI erreichbar ist
- Datenschutz: nur nach Einwilligung, nur eine Zusammenfassung (keine IBAN), Schlüssel nur auf dem Server

**Bank & Kategorien**
- PSD2-Anbindung (Enable Banking, read-only), Demo-Bank zum Ausprobieren
- Automatische Kategorien, lernende Händlerregeln, SEPA-Müll in Titeln wird bereinigt
- Kontostand bleibt zum Bankstand kalibriert (Opening Balance)

**Konto, Budgets, Verträge**
- Umsätze, Budgets mit Ampel, Monatsanalyse
- Abos/Verträge aus wiederkehrenden Zahlungen inkl. Preiserhöhung

**Depot & Vermögen**
- Portfolio mit Kursen, Allokation, Trade-Republic-Import
- Gesamtvermögen (Konto + Depot) mit interaktivem Chart

**Sicherheit & Sync**
- Registrierung, biometrische App-Sperre, Beträge verbergen
- Vault: AES-256-GCM, Schlüssel aus dem Passwort (Server speichert nur Ciphertext)

## Tech-Stack

| Bereich | Technik |
|---|---|
| App | Flutter / Dart |
| Lokal | Hive |
| Sicherheit | local_auth, flutter_secure_storage, bcrypt / Session-Hashes serverseitig |
| Backend | Dart-HTTP-Server (Bank, Depot, Vault, KI-Proxy) |
| Integrationen | Enable Banking (PSD2), Finnhub (Kurse), optional Parqet, serverseitige LLM-API |
| Tests | `flutter_test` (Unit- & Widget-Tests) |

## Struktur

```
lib/          # UI, Services, Modelle
backend/      # API: Bank, Depot, Vault, Buddy
test/         # Tests
landing/      # Landingpage
docs/         # Bilder, Launch-/Legal-Notizen
```

## Starten

Voraussetzung: [Flutter SDK](https://docs.flutter.dev/get-started/install).

```bash
flutter pub get
flutter run
```

Tests:

```bash
flutter test
```

Web-Build:

```bash
tool/build_web.sh
python3 tool/serve_web.py   # http://127.0.0.1:8765
```

Backend: siehe [backend/README.md](backend/README.md).

> Die App-Oberfläche ist auf Deutsch.

Die Schrift Inter liegt unter der SIL Open Font License bei (`assets/fonts/Inter-OFL.txt`).

## Autor

**Luis Frenkler** — Flutter-App von Architektur bis Soft-Launch (Bank-Sync, Vault, Prognose, Buddy, Depot).

Repository: [github.com/LuisFrenkler/budget-buddy](https://github.com/LuisFrenkler/budget-buddy)
