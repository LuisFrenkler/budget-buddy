# TestFlight Soft Launch (BudgetBuddy)

## Braucht man die 99 € Apple-Developer-Lizenz?

**Ja.** TestFlight und App Store Connect setzen die Mitgliedschaft im
[Apple Developer Program](https://developer.apple.com/programs/) voraus
(~99 USD / Jahr). Ohne sie kannst du die App nur per Kabel auf *dein*
Gerät installieren (begrenzte Profile), aber **nicht** an Freunde über
TestFlight verteilen.

Im Xcode-Projekt steht bereits `DEVELOPMENT_TEAM = 65L7B43466` und
`PRODUCT_BUNDLE_IDENTIFIER = com.luisfrenkler.budgetBuddy`. Wenn dieses
Team zu einem aktiven Developer-Abo gehört, bist du für Builds startklar.

## Was die App schon hat

- Bundle-ID iOS: `com.luisfrenkler.budgetBuddy`
- Version in `pubspec.yaml`: `1.0.0+1` (`+1` = Build-Nummer für TestFlight)
- Face ID- und Foto-Nutzungstexte in `ios/Runner/Info.plist`
- Export-Compliance-Flag `ITSAppUsesNonExemptEncryption = false` (nur HTTPS/TLS)

## Blocker vor dem ersten Upload

| Muss | Status |
|------|--------|
| Apple Developer Program aktiv | du (99 €/Jahr) |
| App in App Store Connect angelegt | du |
| Straße, PLZ/Ort, Datenschutzbehörde in `lib/legal/legal_info.dart` | du |
| Datenschutz + Impressum als öffentliche HTTPS-URL | erledigt: `docs/legal/` → GitHub Pages (URL unten) |
| Production-Backend `https://…` (siehe `docs/launch.md`) | du |
| Build mit `BACKEND_URL` auf dieses Backend | Build-Befehl unten |

Für Soft Launch: **Bank nur Demo oder Waitlist**, Plus über Store-Sandbox oder
erstmal dezent — kein EB-Commercial nötig.

## App einmalig in App Store Connect anlegen

1. [developer.apple.com](https://developer.apple.com) → Account → Mitgliedschaft aktiv  
2. [appstoreconnect.apple.com](https://appstoreconnect.apple.com) → **Meine Apps** → **+** → Neue App  
3. Plattform iOS, Name **BudgetBuddy**, Bundle-ID **com.luisfrenkler.budgetBuddy**  
4. SKU z. B. `budgetbuddy1`, Sprache Deutsch  
5. Unter **App-Datenschutz** die Privacy-URL eintragen:
   `https://luisfrenkler.github.io/budget-buddy/legal/datenschutz.html`
   (Impressum: `…/legal/impressum.html`)  
6. Unter **Preise** erstmal kostenlos (Abo später über IAP)

## Build (IPA für TestFlight)

Auf dem Mac mit Xcode und eingeloggtem Apple-ID-Team:

```bash
cd /Users/luisfrenkler/Budget_Buddy/budget_buddy
BACKEND_URL='https://api.DEINE-DOMAIN.de' ./scripts/ios_testflight.sh
```

Oder manuell:

```bash
export BACKEND_URL='https://api.DEINE-DOMAIN.de'
flutter pub get && (cd ios && pod install)
flutter build ipa --release --dart-define=BACKEND_URL="$BACKEND_URL"
```

Die IPA liegt unter `build/ios/ipa/*.ipa`.

Alternativ: Xcode → `ios/Runner.xcworkspace` → Schema **Runner** →
**Any iOS Device** → **Product → Archive** → **Distribute App** →
**App Store Connect** → **Upload**.

Nach dem Upload:

1. App → TestFlight → auf Verarbeitung warten (oft 15–60 Min)  
2. Export-Compliance ggf. bestätigen (App nutzt nur HTTPS)  
3. Interne Tester = schnell; externe Gruppe = oft kurzes Review  
4. Freunde: App **TestFlight** installieren + Einladungs-Link  

## Checkliste erster Freundes-Build

1. [ ] Developer-Abo aktiv  
2. [ ] `legal_info.dart` ohne `[…]`-Platzhalter  
3. [ ] Privacy-URL erreichbar und in App Store Connect eingetragen  
4. [ ] Backend HTTPS live, `/health` ok, CORS auf die App eingeschränkt  
5. [ ] `flutter build ipa` mit `BACKEND_URL`  
6. [ ] Upload → TestFlight → dich selbst als Tester  
7. [ ] 5–20 Freunde einladen  
8. [ ] Feedback sammeln (Crash, Login, Buddy, Bank-Demo)

## Was Cursor / dieses Repo nicht für dich kann

- Die 99 € bezahlen oder dein Apple-Konto anlegen  
- Die IPA ohne deine Apple-ID hochladen  
- Deinen VPS buchen  

Code, Checkliste und Build-Befehl sind hier vorbereitet; der Rest ist einmalig
bei Apple und Hosting.
