# Ahead online bringen (Hetzner)

Ergebnis: drei Adressen mit HTTPS auf einem kleinen Server in Deutschland.

| Adresse | Was |
|---|---|
| `https://DOMAIN` | Landingpage mit Warteliste und „Frag Buddy“ |
| `https://app.DOMAIN` | die Web-App |
| `https://api.DOMAIN` | der Ahead-Server (Buddy, Konten, Warteliste, Bank) |

Kosten: Server ca. 6 € im Monat, Domain ca. 5–15 € im Jahr, KI nach Verbrauch.

## 0. Testphase ohne Server: der eigene Mac

Für ein paar Wochen mit wenigen Testern reicht der Mac:

```sh
brew install cloudflared              # einmalig
cp backend/.env.example backend/.env  # einmalig, KI-Schlüssel selbst eintragen
tool/mac_testserver.sh
```

Das Skript startet den Server, macht ihn über einen kostenlosen Cloudflare-Tunnel
mit HTTPS erreichbar und zeigt den `flutter run`-Befehl für das iPhone. Die
Adresse ändert sich bei jedem Start, und ist der Mac zu, ist Buddy offline.
Für TestFlight und den App Store deshalb den richtigen Server unten nehmen.

## 1. Domain kaufen

Bei INWX, Hetzner oder einem anderen Anbieter. Danach in den DNS-Einstellungen
vier Einträge anlegen, alle auf die IP aus Schritt 2:

| Typ | Name | Wert |
|---|---|---|
| A | `@` | Server-IP |
| A | `www` | Server-IP |
| A | `app` | Server-IP |
| A | `api` | Server-IP |

## 2. Server anlegen

1. <https://console.hetzner.cloud> → neues Projekt → **Server hinzufügen**
2. Standort **Falkenstein** oder **Nürnberg**, Image unter **Apps: Docker CE**
3. Typ **CX23** (oder **CAX11**, ARM) reicht für den Start. Sind beide nicht bestellbar, einen anderen deutschen Anbieter mit 2 Kernen und 4 GB nehmen
4. Deinen SSH-Schlüssel hinzufügen (`cat ~/.ssh/id_ed25519.pub`, sonst vorher `ssh-keygen -t ed25519`)
5. Unter **Firewalls** eine Firewall mit eingehend TCP 22, 80, 443 und UDP 443 anlegen

## 3. Geheimnisse auf den Server (einmalig)

Auf dem Mac, im Ordner `budget_buddy`:

```sh
cp backend/.env.example deploy/.env
# deploy/.env öffnen und mindestens ANTHROPIC_API_KEY eintragen
# Enable Banking: .pem nach deploy/keys/ legen, EB_PRIVATE_KEY_PATH=/app/keys/<datei>.pem
ssh root@SERVER-IP "mkdir -p /opt/ahead/deploy/keys"
scp deploy/.env root@SERVER-IP:/opt/ahead/deploy/.env
scp deploy/keys/*.pem root@SERVER-IP:/opt/ahead/deploy/keys/   # nur wenn vorhanden
```

`deploy/.env` und `deploy/keys/` sind von Git ausgeschlossen. Den API-Schlüssel nie in den Chat oder ins Repo schreiben.

## 4. Veröffentlichen

```sh
DOMAIN=deine-domain.de SERVER=root@SERVER-IP deploy/publish.sh
```

Das baut die Web-App gegen `https://api.DOMAIN`, lädt Server, App und Landingpage hoch
und startet alles. Für jedes Update denselben Befehl noch einmal.

## 5. Prüfen

- `https://api.DOMAIN/health` zeigt `"ai":true` und `"guest":true`
- Landingpage: E-Mail eintragen → echter Platz auf der Warteliste
- „Frag Buddy“ auf der Landingpage antwortet mit KI (3 Fragen pro Tag ohne Konto)
- App: Konto anlegen, Buddy fragen

## Bank, Zahlungen, App Stores

- Enable Banking: als Redirect-URL `https://api.DOMAIN/bank/callback` eintragen
- Stripe-Webhook: `https://api.DOMAIN/stripe/webhook`
- Details stehen in `backend/README.md`

## Sicherung

Alle Daten liegen im Docker-Volume `ahead-data`. Eine Kopie ziehen:

```sh
ssh root@SERVER-IP "docker run --rm -v deploy_ahead-data:/d -v /root:/b debian tar czf /b/ahead-data.tgz -C /d ."
scp root@SERVER-IP:/root/ahead-data.tgz .
```

Zusätzlich in der Hetzner-Konsole **Backups** für den Server einschalten (20 % Aufpreis).
