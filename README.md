# BudgetBuddy

A personal finance app built with **Flutter** that brings your budget and your investment portfolio together in one place. All data is stored locally on the device. Nothing leaves the phone unless you explicitly connect a bank account.

<p align="center">
  <img src="docs/images/hero.png" alt="BudgetBuddy app" width="420">
</p>

## Screenshots

<p align="center">
  <img src="docs/images/screen_home.png" alt="Home" width="200">
  <img src="docs/images/screen_stats.png" alt="Statistics and insights" width="200">
  <img src="docs/images/screen_categories.png" alt="Spending by category" width="200">
  <img src="docs/images/screen_depot.png" alt="Portfolio" width="200">
</p>

## Features

**Budgeting**
- Track income and expenses by category, grouped by month, with search, editing and swipe-to-delete with undo
- Monthly budgets per category with progress bars
- Recurring transactions (e.g. rent, salary) that are generated automatically, including any that came due while the app was closed
- Statistics per month with an income vs. expenses chart for the last six months
- Automatic insights comparing this month's spending to last month
- Achievement badges (first transaction, €100 saved, 50 transactions, 7 days tracked)

**Portfolio**
- Depot overview with total value, gain/loss, value chart and allocation donut
- Built-in search for well-known stocks, ETFs and crypto, with live prices via the Finnhub API
- Import of positions from a **Trade Republic** transaction export: buys and sells are aggregated into net positions with an average buy price

**Data & Security**
- Import transactions or positions from CSV
- CSV export and full JSON backup / restore
- App lock with Face ID / fingerprint / device PIN, re-locks when the app goes to the background
- Dark and light mode, onboarding on first launch
- Demo mode with six months of realistic sample data to explore the app instantly

**Optional live sync**
A small Dart backend acts as a proxy to link a real bank account (GoCardless, PSD2) and a Parqet depot, so API secrets never live in the app. See [backend/README.md](backend/README.md).

## Tech Stack

| Area | Technology |
|---|---|
| App | Flutter, Dart |
| Storage | Hive (local NoSQL database) |
| Security | local_auth (biometrics / device credentials) |
| Data | CSV import/export, JSON backup |
| APIs | Finnhub (prices), GoCardless Bank Account Data, Parqet |
| Backend | Dart HTTP server (`backend/server.dart`) |
| Testing | flutter_test – 76 unit and widget tests |

## Project Structure

```
lib/
├── models/     # Transaction, Budget, Holding, Recurring, Badge
├── screens/    # Home, Budget, Stats, Depot, Profile, Onboarding, ...
├── services/   # Database, importers, backup, prices, insights, auth
├── utils/      # Theme, money formatting, instrument list
└── widgets/    # Charts, cards, search sheet
backend/        # Optional proxy server for bank and depot sync
test/           # Unit and widget tests
landing/        # Landing page for the app
```

## Getting Started

Requires the [Flutter SDK](https://docs.flutter.dev/get-started/install).

```bash
flutter pub get
flutter run
```

Live prices are optional. To enable them, pass a free [Finnhub](https://finnhub.io) API key:

```bash
flutter run --dart-define=FINNHUB_KEY=your_key
```

Run the tests:

```bash
flutter test
```

> The app's user interface is in German.
