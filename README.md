# Life OS für iPhone, iPad und Mac

Native Client für [Life OS](https://github.com/navidduengen/life-os-prototype): eine SwiftUI-App für iPhone, iPad und Mac (über Mac Catalyst) aus einem Code. Sie spricht dieselbe `/api/v1`-JSON-API wie die Web-App.

| | iPhone | iPad / Mac |
| :--- | :--- | :--- |
| Navigation | Tab-Leiste: Heute, Aufgaben, Kalender, Posteingang, Apps | Seitenleiste wie „Leiste links“ im Web |
| Heute | Termine, überfällige und heute fällige Aufgaben, Demnächst, zuletzt bearbeitet | gleich |
| Aufgaben | Liste mit Filter, Abhaken, Statuswechsel per Wischen, neue Aufgabe | gleich |
| Kalender | Monats-Agenda, Filter-Chips nach Quelle, Termin-Details | gleich |
| Posteingang | Liste mit Typ-Filter | gleich |
| Health, Finance | gesperrt, bis der Server Face-ID-Entsperrung prüft | gleich |
| Apple Health | Import von 207 Datentypen, pro Typ oder Gruppe wählbar, im Hintergrund (Konto › Apple Health) | auf dem Mac nicht verfügbar |
| Mitteilungen | Termine, fällige Aufgaben, ausgelesene Befunde; erst sichtbar, wenn der Server Push einschaltet | gleich |
| Study Hub | Platzhalter mit Link in die Web-App | gleich |

Ohne Server läuft die App im **Demo-Modus** mit Beispieldaten („Demo ohne Server ansehen“ auf dem Login-Bildschirm).

## Aufbau

```
App/                    SwiftUI-App (iOS 17+, Mac Catalyst 14+)
  Sources/AppModel.swift      Zustand: Server, Anmeldung, aktivierte Apps
  Sources/Features/           Bildschirme
  Sources/Design/             Farben, 44-pt-Maß, Ladezustände
  Sources/Health/             Apple-Health-Import (HealthKit, nur iPhone/iPad)
  Sources/Push/               Push-Mitteilungen
Packages/LifeOSKit/     Swift Package ohne UI: Modelle, API-Client, Login, Health-Katalog, Demo-Daten
scripts/health_types.py Quelle des Apple-Health-Katalogs für App und Web
docs/backend-vertrag.md API-Vertrag mit dem Backend (Login, Scopes, Push)
docs/release.md         Signing, TestFlight, was lokal geprüft werden muss
docs/entscheidungen.md  Produkt- und Technikentscheidungen, die die Apps betreffen
project.yml             XcodeGen-Projektdefinition
```

`LifeOSKit` ist bewusst UI-frei, damit Modelle, Token-Logik und Dekodierung ohne Simulator getestet werden können und später ein Widget oder eine Watch-App sie mitnutzen kann.

## Loslegen

Voraussetzungen: Xcode 16 oder neuer, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
xcodegen generate      # erzeugt LifeOS.xcodeproj (nicht eingecheckt)
open LifeOS.xcodeproj
```

Im Schema `LifeOS` ein iPhone, iPad oder „My Mac (Mac Catalyst)“ wählen und starten. Für ein echtes Gerät unter *Signing & Capabilities* dein Team eintragen.

Tests des Kerns:

```bash
cd Packages/LifeOSKit && swift test
```

## Anmeldung

Die App folgt ADR-031-004 aus dem Life-OS-Repo:

- Login nur im Anmeldefenster des Systems (`ASWebAuthenticationSession`), nie in einer WebView. Dort läuft der normale Web-Login von Life OS (ADR-031-004; welcher Anbieter, entscheidet das Backend, siehe dort), danach bestätigt man das Gerät.
- Danach tauscht die App einen Einmal-Code plus PKCE gegen einen Bearer-Token pro Gerät. Access-Token 15 Minuten, Refresh-Token rotierend (60 Tage), beide im Schlüsselbund (nur dieses Gerät). Scopes pro Bereich kommen mit life-os-prototype#32 (noch nicht auf main), siehe Backend-Vertrag §5. Abmelden widerruft das Gerät nur, wenn der Server erreichbar ist (best effort, §4).
- Tresor-Apps (Health, Finance) werden erst angezeigt, wenn der Server sie per Geräteschlüssel aus dem Secure Enclave nach Face ID entsperrt. Eine reine Face-ID-Abfrage in der App reicht laut ADR nicht.

**Stand (2026-10-01):** Das Backend auf `life-os-prototype` main hat die Endpunkte (`NativeAuthController`, `NativeAppTokens`, Migration `2026_10_01_210000_create_native_app_auth_tables`, Test `NativeAppTokensTest`). Die App kann sich also gegen einen echten Server anmelden; der Demo-Modus bleibt für Vorführungen ohne Server. Vertrag und Abgleich: [`docs/backend-vertrag.md`](docs/backend-vertrag.md). Release-Voraussetzungen (Signing, TestFlight): [`docs/release.md`](docs/release.md).
