# BudgetBuddy Backend (bank, depot and payments)

This is a small local server. It lets the app link a real **bank account** through
[Enable Banking](https://enablebanking.com) (PSD2, 2,500+ European banks) and a
**depot** (Trade Republic and others) through Parqet Connect, and takes Plus payments
through Stripe (web) or the App Store and Google Play (apps). API keys stay on the server and are never stored in the app.

```
[ App ] --http--> [ this server ] --https--> [ Enable Banking -> your bank ]
                                  --https--> [ Parqet ]
```

## Configuration

Keys go into `backend/.env` (git-ignored). Copy `.env.example` to `.env` and
fill in what you use; environment variables with the same name take precedence.
Restart the server after a change.

The server listens on localhost only. In production put a reverse proxy
(Caddy, nginx) in front that adds the client address to `X-Forwarded-For`:
the login and sign-up limits per address read it.

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

Enable Banking only redirects to `https` addresses. For running on your own Mac
the server therefore also answers on `https://localhost:8443` once a local
certificate exists:

```bash
brew install mkcert
mkcert -install          # once: lets the browser trust local certificates (asks for your password)
cd backend && mkdir -p .data/tls
mkcert -cert-file .data/tls/localhost.pem -key-file .data/tls/localhost-key.pem localhost 127.0.0.1
```

Register `https://localhost:8443/bank/callback` as the redirect URL in the
Enable Banking application and put the same address into `.env` as
`EB_REDIRECT_URL`. On a public server use its own address instead
(`PUBLIC_URL` and `EB_REDIRECT_URL`).

## AI features (Buddy, optional)

```bash
export ANTHROPIC_API_KEY=...   # from console.anthropic.com
```

With the key, Buddy answers through Claude Haiku 5.5 (streamed, about 0.1 cent a
question), reads receipts, refines quick entries and turns what the user tells it
into entries. Each user can make 50 AI calls per day. Without an Anthropic key a
`GEMINI_API_KEY` (free, 20 requests a day per model) runs the same features on
Gemini Flash; without either, or when the quota is used up, the app falls back to
offline answers and the offline parser.

| Method | Path | Purpose |
|---|---|---|
| POST | `/ai/chat` | `{finances, history}` → server-sent events `{"t": "..."}`, then `{"done": true}` |
| POST | `/ai/parse` | `{text, categories}` → `{booking}` |
| POST | `/ai/entries` | `{text, image?, categories, accounts, depots}` → `{reply, entries}` |
| POST | `/ai/receipt` | `{image (base64), mediaType, categories}` → `{booking}` |

## Depot: Trade Republic and other brokers (Parqet Connect)

Trade Republic, Scalable and most other brokers have no open interface for
depots. [Parqet](https://parqet.com) syncs them (Autosync) and lets other apps
read the result with the user's consent through
[Parqet Connect](https://developer.parqet.com): OAuth 2.0 with PKCE, scope
`portfolio:read`. The user links their broker with Parqet once, then allows
BudgetBuddy to read it. BudgetBuddy never sees the broker login.

```
[ Trade Republic ] --Autosync--> [ Parqet ] --OAuth, read only--> [ this server ] --> [ App ]
```

Without configuration the server runs a **demo depot** with the same steps.
For real depots:

1. Sign in at <https://developer.parqet.com/console> and create an integration
   (name, logo, scope `portfolio:read`).
2. Add the redirect URL `http://localhost:8090/depot/callback` (or your public
   address, see `PARQET_REDIRECT_URL`).
3. Start the server with:

```bash
export PARQET_CLIENT_ID=<client id>
export PARQET_CLIENT_SECRET=<only if the integration has one>
dart run server.dart
```

In the app: **Profil → Bank & Depot verbinden → Mit Parqet verbinden**. The
positions arrive with ISIN, shares, buy price and current price. Every sync
updates them; sold positions disappear. Positions added by hand stay untouched.

The Trade Republic **cash account** (balance, card payments, interest) is a
normal bank account and goes through the bank connection above. Without Parqet,
the Trade Republic CSV export can be imported under
**Profil → Import, Export & Backup → Depot importieren**.

## Plus payments (Stripe)

The app never sees card or bank details. It asks the server for a Stripe
Checkout page, the user pays there, and the server records who has Plus.
Payment method, plan changes and invoices live in Stripe's customer portal.
Without `STRIPE_SECRET_KEY` the server runs a **demo checkout** that never
charges anything.

1. Create a Stripe account (business details, bank account for payouts).
2. Create one product "BudgetBuddy Plus" with two recurring prices:
   4,99 € monthly and 39,99 € yearly. Note both price ids (`price_...`).
3. In *Settings → Payment methods*, switch on what you want to offer: cards,
   PayPal, SEPA Direct Debit, Apple Pay, Google Pay, Klarna.
4. In *Settings → Billing → Customer portal*, allow updating the payment method,
   switching between the two prices and viewing invoices.
5. Start the server with:

```bash
export STRIPE_SECRET_KEY=sk_test_...      # test mode first, sk_live_... later
export STRIPE_PRICE_MONTHLY=price_...
export STRIPE_PRICE_YEARLY=price_...
export STRIPE_WEBHOOK_SECRET=whsec_...    # optional, see below
dart run server.dart
```

The entitlement is updated three ways, so it works with and without webhooks:
on the return from checkout, from webhooks, and by re-reading the subscription
when the app asks and the copy is older than 30 minutes. For webhooks, point
Stripe at `<PUBLIC_URL>/stripe/webhook` with the events
`customer.subscription.created`, `.updated` and `.deleted`. Locally:
`stripe listen --forward-to localhost:8090/stripe/webhook`.
`dart run tool/check_webhook_signature.dart` checks the signature verification.

Promo codes (`BUDDY30`, `FREUND`, `CREATOR60`, `START14`) add free days on top of
the 7-day trial. Anyone who had Plus before gets no second trial. The 14-day
withdrawal cancels at once and refunds what was paid. Deleting an account
cancels its subscription.

## Plus in the iPhone and Android app (App Store, Google Play)

Apple and Google require their own in-app purchase for digital subscriptions,
so the apps buy Plus through the store (`in_app_purchase`,
`lib/services/store_purchases.dart`) and the web app through Stripe.

The store takes the payment, **the server decides**: after every purchase,
restore or renewal the app sends the store's id for it to `/plus/store`
(Apple: the transaction id, Google: the purchase token). The server asks Apple
or Google itself with its own credentials (`lib/store_billing.dart`) and only
that answer unlocks Plus. It checks that the purchase belongs to this app and
to one of the two products, keeps a subscription on one BudgetBuddy account
only, and re-reads it with the store when the app asks and the copy is older
than 30 minutes (renewals, cancellations, refunds). A purchase is finished
with the store only after the server has seen it, so one that could not be
checked comes back on the next start. Without credentials for a store, its
purchases are refused: nothing unverified ever unlocks Plus.

Guests can buy too (Apple does not allow forcing a sign-up first). The app then
keeps the store id and has the server check it again on each start. Signing in
later moves the subscription to the account.

Cancelling, changing the plan, receipts and refunds happen in the store; the
app's *Mein Abo* page links there. Promo codes become Apple offer codes and
Google promo codes, created in the consoles.

### Products (both stores, same ids)

| Product id | Price | Trial |
|---|---|---|
| `budgetbuddy_plus_monthly` | 4,99 € / month | 7 days free (introductory offer) |
| `budgetbuddy_plus_yearly` | 39,99 € / year | 7 days free (introductory offer) |

Keep the store prices equal to the web prices; the app shows the store's own
price once it has loaded. Other ids: set `PLUS_PRODUCT_MONTHLY` /
`PLUS_PRODUCT_YEARLY` on the server and change `StorePurchases.ids` in the app.

### App Store Connect

1. Sign the *Paid Applications Agreement* and add tax and bank details
   (*Business*). Without it no product loads, not even in the sandbox.
2. *Your app → Monetization → Subscriptions*: create a subscription group
   "BudgetBuddy Plus" with the two products above, each with prices for all
   countries, a localized name and description, and an *introductory offer*:
   free, 1 week, new subscribers.
3. *Users and Access → Integrations → In-App Purchase*: generate a key. Download
   the `.p8` (only possible once) and note the key id and the issuer id.
4. In Xcode add the capability *In-App Purchase* to the Runner target.
5. Test with a sandbox account (*Users and Access → Sandbox*) or a TestFlight
   build. The server asks production first and then the sandbox, so both work
   with the same configuration.

### Google Play Console

1. Set up a payments profile (*Settings → Payments profile*). The app needs a
   real application id; `com.example.*` is rejected by Google Play, so change
   `applicationId` in `android/app/build.gradle.kts` first.
2. Upload a build to a testing track once; products can only be created for an
   app that declares the billing permission (the plugin adds it).
3. *Monetize → Subscriptions*: create the two products above, each with one
   auto-renewing base plan (monthly / yearly) and an offer *free trial, 7 days,
   new customers only*.
4. In Google Cloud create a service account and a JSON key; enable the
   *Google Play Android Developer API*. In the Play Console (*Users and
   permissions*) invite the service account's email with *View financial data*
   and *Manage orders and subscriptions*. Permissions can take up to a day.
5. Add testers under *Settings → License testing*; their purchases are free and
   renew every few minutes.

### Server configuration

```bash
# keep the keys in backend/.data/ (git-ignored)
export APPLE_BUNDLE_ID=com.luisfrenkler.budgetBuddy
export APPLE_ISSUER_ID=...                     # App Store Connect issuer id
export APPLE_KEY_ID=...                        # In-App Purchase key id
export APPLE_PRIVATE_KEY_PATH=.data/SubscriptionKey_XXXX.p8
export GOOGLE_PACKAGE_NAME=...                 # the application id
export GOOGLE_SERVICE_ACCOUNT_PATH=.data/play-service-account.json
dart run server.dart
```

At start the server prints which stores it can check (`Stores: apple,google`).
`/health` reports the same under `stores`. `dart test` in `backend/` covers how
Apple's and Google's answers are read.

Not built yet: Apple's *App Store Server Notifications* and Google's *Real-time
developer notifications*. They would tell the server about renewals and refunds
the moment they happen; until then the 30-minute re-read covers them.

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
| GET | `/health` | status: `bank`, `depot` and `billing` are each `live` or `demo`; `stores` lists the stores it can check |
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
| POST | `/depot/connect` | → `{state, link}`; open `link` to allow access at Parqet |
| GET | `/depot/callback` | redirect target of Parqet (code → tokens) |
| GET | `/depot/status?state=` | `pending`, `linked`, `failed` or `unknown` |
| GET | `/depot/sync?state=` | positions with ISIN, shares, buy and current price |
| POST | `/depot/disconnect` | `{state}`; forgets the tokens |
| GET | `/plus/status` | this account's Plus, or `null` (`?fresh=1` re-reads Stripe) |
| POST | `/plus/checkout` | `{plan, promo?}` → `{url}` of the payment page |
| GET | `/plus/return` | where the payment page returns to |
| POST | `/plus/portal` | → `{url}` of Stripe's customer portal |
| POST | `/plus/cancel` | `{cancel}`; cancel at the period end, or take it back |
| POST | `/plus/withdraw` | the 14-day withdrawal: ends now and refunds |
| POST | `/stripe/webhook` | Stripe events, checked against `STRIPE_WEBHOOK_SECRET` |
| POST | `/plus/store` | `{platform: apple\|google, id}` → `{plus}`; a store purchase, checked with the store |
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

All `/bank/*`, `/depot/*` and `/plus/*` endpoints except the browser pages
(callbacks, demo pages, return) and `/plus/store` need `Authorization: Bearer <token>`.
`/plus/store` also answers guests, without saving anything for them. A bank or
depot link belongs to the account that created it.

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
