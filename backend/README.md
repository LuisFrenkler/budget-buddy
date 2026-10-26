# BudgetBuddy Backend (bank and depot sync)

This is a small local server. It lets the app link a real **bank account** through
[Enable Banking](https://enablebanking.com) (PSD2, 2,500+ European banks) and a
**depot** through Parqet. API keys stay on the server and are never stored in the app.

```
[ App ] --http--> [ this server ] --https--> [ Enable Banking -> your bank ]
                                  --https--> [ Parqet ]
```

## Quick start (demo bank, no account needed)

```bash
cd backend
dart pub get
dart run server.dart
```

Without credentials the server runs a **demo bank**. It goes through the same
connect, consent and sync steps as a real bank, using generated data. The consent
page is clearly marked as a demo.

In the app, go to **Profil → Konto & Depot verbinden → Bank auswählen** (or use
**Bankkonto verbinden** on the start screen). Pick a bank and tap
**Zugriff erlauben**. The app notices the granted access by itself, then imports the
balance and the last 90 days of bookings.

## Real banks (free for your own accounts)

1. Sign up at <https://enablebanking.com/sign-in/> and open the Control Panel.
2. Register an application for the **production** environment. Have it generate
   the key pair and download the private key (`.pem`).
   - Add the redirect URL `http://localhost:8090/bank/callback`. If the panel only
     accepts HTTPS, see the redirect notes below.
3. Link your own account in the Control Panel to activate the app. It then runs in
   "restricted" mode, which is free and only sees accounts you have linked.
4. Start the server with:

```bash
export EB_APP_ID=<application id>
export EB_PRIVATE_KEY_PATH=/path/to/<application id>.pem
dart run server.dart
```

The start line now says `Enable Banking (live)`. The bank list in the app shows
real German banks, and the login happens on your bank's own page.

### Redirect notes

After the login, the bank sends the browser to `EB_REDIRECT_URL`. The default is
`http://localhost:8090/bank/callback`. That address must be whitelisted exactly in
the Enable Banking app. If you need HTTPS, expose the server, for example with
`cloudflared tunnel --url http://localhost:8090`. Then set both `PUBLIC_URL` and
`EB_REDIRECT_URL` to the tunnel address.

## AI features (Buddy, optional)

```bash
export ANTHROPIC_API_KEY=...   # from console.anthropic.com
```

With the key, Buddy answers through Claude Opus 5.5 (streamed), reads receipts
and refines quick entries. Requests opt into server-side refusal fallbacks
(`fallbacks: "default"`). Each user can make 150 AI calls per day. Without the key,
the app falls back to offline answers and the offline parser.

| Method | Path | Purpose |
|---|---|---|
| POST | `/ai/chat` | `{finances, history}` → server-sent events `{"t": "..."}`, then `{"done": true}` |
| POST | `/ai/parse` | `{text, categories}` → `{booking}` |
| POST | `/ai/receipt` | `{image (base64), mediaType, categories}` → `{booking}` |

## Depot (Parqet, optional)

```bash
export PARQET_TOKEN=...
export PARQET_PORTFOLIO_ID=...
```

Trade Republic and Scalable Capital have no open API for this. Export the
positions there and import the CSV in the app under **Profil → Depot importieren**.

## How syncing works in the app

- Each booking is saved under the stable id `bank_<account>:<booking id>`. A
  re-sync never creates duplicates and never overwrites a booking you edited.
- New bookings are categorized in two steps:
  1. The category you last gave the same counterparty, so the app learns from your
     corrections.
  2. Otherwise a keyword guess, e.g. REWE → Lebensmittel, DB Vertrieb → Transport
     (see `lib/services/categorizer.dart`).
- Banks only hand out a few months of history. The app therefore keeps an opening
  balance, which makes its Kontostand match the bank's exactly.
- The app syncs by itself on start when the last sync is older than 4 hours. You can
  also tap the bank chip on the Konto tab or pull down to refresh.

## Endpoints

| Method | Path | Purpose |
|---|---|---|
| GET | `/health` | status: `bank` is `live` or `demo`, `parqet` true/false |
| POST | `/auth/register` | `{name, email, password}` → `{token, user}` |
| POST | `/auth/login` | `{email, password}` → `{token, user}` |
| GET | `/auth/me` | the signed-in user |
| POST | `/auth/logout` | ends this session |
| DELETE | `/auth/account` | deletes the user and all of their bank links |
| GET | `/bank/institutions?country=DE` | banks to choose from |
| POST | `/bank/connect` | `{institution}` → `{state, link}`; open `link` to log in |
| GET | `/bank/callback` | redirect target of the bank (code → session) |
| GET | `/bank/status?state=` | `pending`, `linked`, `failed` or `unknown` |
| GET | `/bank/sync?state=&days=90` | balance in cents and normalized bookings |
| POST | `/bank/disconnect` | `{state}`; revokes the session |
| GET | `/parqet/portfolio?id=` | depot positions |
| POST | `/auth/profile` | `{name}`; change the display name |
| POST | `/auth/email` | `{email, password}`; change the email, confirmed with the password |
| POST | `/auth/password` | `{current, next}`; new password, signs out every other device |
| POST | `/splits/share` | `{group, me}`; shares a group, returns its invite code |
| GET | `/splits/preview?code=` | name and members of a group, and who is taken |
| POST | `/splits/join` | `{code, member}`; join as one of the members |
| GET | `/splits/get?id=` | the group's current state (participants only) |
| POST | `/splits/op` | `{id, op}`; `addExpense`, `removeExpense` or `settle`, applied in order |
| POST | `/splits/leave` | `{id}`; leave, or delete for all when you created it |
| GET | `/market/chart?symbol=&range=` | stock and ETF prices for the web app (Yahoo, cached 5 min, no sign-in) |

All `/bank/*` and `/parqet/*` endpoints need `Authorization: Bearer <token>`. A
bank link belongs to the account that created it.

## Security notes

- Passwords are stored as bcrypt hashes. Session tokens are 256-bit random values,
  stored only as their SHA-256, and valid for 30 days. Five wrong passwords lock an
  email for five minutes, and the error does not reveal whether the email exists.

- Secrets come only from environment variables. `.pem` files and `.data/` are
  git-ignored.
- The server binds to `127.0.0.1` only. A link is identified by a random 128-bit
  `state` token that only the app knows.
- Access is read-only. PSD2 consent is valid for up to 180 days, after which the
  app asks you to renew it.
- Before hosting this for other people, add HTTPS, restrict CORS to the app's origin
  and add password reset by email. Enable Banking's free mode is for personal use only.
