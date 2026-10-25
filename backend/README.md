# BudgetBuddy Backend (Konto- & Depot-Sync)

A small local proxy so the app can link a real **bank account** (GoCardless /
PSD2) and **depot** (Parqet) without ever keeping secrets in the client.

```
[ App ] --http--> [ this server ] --https--> [ GoCardless / Parqet ]
```

## 1. Get free credentials

**Bank (GoCardless Bank Account Data):**
1. Sign up at <https://bankaccountdata.gocardless.com> (free, no card).
2. User Secrets → create a secret → note the **Secret ID** and **Secret Key**.

**Depot (Parqet) — optional:**
- A Parqet **API token** and your **portfolio id** (from your Parqet account).

## 2. Run the server

```bash
cd budget_buddy
export GOCARDLESS_SECRET_ID=...      # required for the bank link
export GOCARDLESS_SECRET_KEY=...
export PARQET_TOKEN=...              # optional, for the depot
export PARQET_PORTFOLIO_ID=...       # optional
dart run backend/server.dart
```

It listens on `http://localhost:8090`. Check it: `curl http://localhost:8090/health`.

## 3. Run the app pointing at it

The app defaults to `http://localhost:8090`. To override:

```bash
flutter run -d chrome --dart-define=BACKEND_URL=http://localhost:8090
```

Then in the app: **Profil → Live-Verbindung → Konto & Depot verbinden**.
- **Bank verbinden** → pick your bank → log in at the bank → back in the app
  tap **Umsätze importieren**.
- **Parqet-Depot laden** → pulls your positions into the depot.

## Endpoints

| Method | Path | Purpose |
|---|---|---|
| GET | `/health` | status + which integrations are configured |
| GET | `/gc/institutions?country=DE` | list banks |
| POST | `/gc/requisition` | `{institutionId, redirect}` → consent link |
| GET | `/gc/transactions?requisitionId=` | normalized booked transactions |
| GET | `/parqet/portfolio?id=` | depot positions |

## Notes

- Secrets are read from env vars only — never commit them.
- PSD2 consent lasts ~90 days; bank data refreshes up to ~4×/day.
- For production, host this behind HTTPS and restrict CORS to your app origin.
- Parqet's response shape varies by plan; `/parqet/portfolio` maps the common
  fields and may need a small tweak for your account.
