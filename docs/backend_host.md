# Backend Soft Launch (günstig, EU)

Ziel: ein HTTPS-API für TestFlight. Bank bleibt Demo, Buddy mit Gemini Free.

Kosten grob: Hetzner CX22 o. ä. (~4 €/Monat) + Domain falls nötig.

## 1. Server

1. Hetzner Cloud → CX22, Ubuntu 24.04, Location **Falkenstein/Nürnberg**
2. A-Record deiner Domain auf die Server-IP (z. B. `api.deinedomain.de`)
3. SSH rein, als root:

```bash
apt update && apt install -y curl ufw
ufw allow OpenSSH && ufw allow 80 && ufw allow 443 && ufw --force enable
```

## 2. Dart + App-Code

```bash
# Dart SDK: https://dart.dev/get-dart (apt-Repo)
apt-get install apt-transport-https
# … Dart installieren, dann:
git clone https://github.com/LuisFrenkler/budget-buddy.git /opt/budgetbuddy
cd /opt/budgetbuddy/backend
dart pub get
```

Privates Repo? Deploy-Key oder per `scp` nur den `backend/`-Ordner hochladen.

## 3. `.env` (Produktion)

```bash
cp .env.example .env
nano .env
```

Mindestens:

```
BIND=0.0.0.0
PORT=8090
PUBLIC_URL=https://api.deinedomain.de
TRUST_PROXY=1
CORS_ORIGINS=
GEMINI_API_KEY=dein_key_von_aistudio.google.com
```

- `CORS_ORIGINS` leer = Flutter-Apps sind ok (kein Browser-CORS).
- Kein `ALLOW_DEMO_BILLING` setzen.
- Stripe / Apple IAP / Enable Banking später — Soft Launch braucht das nicht.

## 4. Caddy (HTTPS)

```bash
apt install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
apt update && apt install -y caddy
```

`/etc/caddy/Caddyfile`:

```
api.deinedomain.de {
        reverse_proxy 127.0.0.1:8090
}
```

```bash
systemctl reload caddy
```

## 5. systemd

`/etc/systemd/system/budgetbuddy.service`:

```
[Unit]
Description=BudgetBuddy API
After=network.target

[Service]
WorkingDirectory=/opt/budgetbuddy/backend
EnvironmentFile=/opt/budgetbuddy/backend/.env
ExecStart=/usr/bin/dart run server.dart
Restart=always
RestartSec=3
User=www-data
Group=www-data

[Install]
WantedBy=multi-user.target
```

```bash
chown -R www-data:www-data /opt/budgetbuddy/backend
systemctl daemon-reload
systemctl enable --now budgetbuddy
curl -sS https://api.deinedomain.de/health
```

Erwartung: JSON mit `"ok": true` (o. ä.).

## 6. App-Build

```bash
BACKEND_URL='https://api.deinedomain.de' ./scripts/ios_testflight.sh
```

Siehe [testflight.md](testflight.md).

## Check

- [ ] `/health` und `/ready` antworten über HTTPS  
- [ ] In der App Login / Register gegen diese URL  
- [ ] Buddy-Frage (Gemini) kommt an  
- [ ] Kein Demo-Plus auf dem öffentlichen Host  
