# Release: Build, Signing, TestFlight

Stand 2026-10-01. Hält fest, was für einen TestFlight-Build real geprüft ist und was nur
mit Apple-Konto, Mac oder Gerät geht.

## Geprüft (ohne Mac, in einer Linux-Sandbox)

| Was | Ergebnis | Grundlage |
| :--- | :--- | :--- |
| Login-Vertrag App ↔ Backend | passt (Pfade, Felder, PKCE, Rotation, Logout) | statischer Abgleich, `docs/backend-vertrag.md` |
| `PrivacyInfo.xcprivacy` | vorhanden, Plist-Syntax gültig; Inhalt s. „Datenschutz“ | Required-Reason-API UserDefaults mit `CA92.1`; Datenerhebung **noch nicht deklariert** |
| Swift-Code | **nicht kompiliert** (kein Swift/Xcode in der Sandbox) | lokal auf dem Mac nachholen, s. u. |

Automatische Swift-/iOS-Builds sind pausiert (`docs/actions-budget.md`). `ci.yml` läuft nur
per `workflow_dispatch` und nur nach Navids Freigabe.

## Lokal auf dem Mac prüfen (vor jedem TestFlight-Upload)

```bash
brew install xcodegen
xcodegen generate
(cd Packages/LifeOSKit && swift test)
xcodebuild -scheme LifeOS -destination 'generic/platform=iOS Simulator' build
xcodebuild -scheme LifeOS -destination 'platform=macOS,variant=Mac Catalyst' build
```

Dann gegen einen Testserver (nicht Produktion): Login über das Anmeldefenster, Gerät
bestätigen, Heute/Aufgaben laden, eine Aufgabe anlegen, abmelden und prüfen, dass das Gerät
in den Web-Einstellungen als widerrufen erscheint.

## Braucht Apple-Konto oder Hardware (offen)

1. **Team**: `DEVELOPMENT_TEAM` in `project.yml` ist leer. Team-ID eintragen (kein Secret)
   oder in Xcode unter *Signing & Capabilities* setzen.
2. **App-ID** `app.lifeos.ios` im Developer-Portal mit Push Notifications, HealthKit
   (inkl. Clinical Health Records, Background Delivery). Mac Catalyst nutzt dieselbe ID
   (`DERIVE_MACCATALYST_PRODUCT_BUNDLE_IDENTIFIER = NO`).
3. **App Store Connect**: App anlegen, Bundle-ID wählen, Exportkonformität ist über
   `ITSAppUsesNonExemptEncryption = NO` beantwortet (nur Standard-TLS).
4. **APNs-Schlüssel** (.p8) anlegen und in Azure Key Vault ablegen (Namen siehe
   `docs/backend-vertrag.md` §8). `aps-environment` steht auf `development`; beim
   Archivieren für TestFlight setzt das Distribution-Profil `production`. Backend dann
   `APNS-ENVIRONMENT=production`.
5. **HealthKit Clinical Records**: verlangt bei der Review eine Begründung; Texte stehen in
   `project.yml` (`NSHealthClinicalHealthRecordsShareUsageDescription`).
6. **Datenschutz:** siehe eigener Abschnitt unten. Vor App-Store-Einreichung muss die
   Deklaration entschieden sein.
7. **Server-Adresse**: TestFlight-Tester brauchen einen erreichbaren HTTPS-Server mit
   aktuellem Backend (Native-Auth-Migration ausgeführt).

## Datenschutz: Manifest und App-Store-Angaben

**Required-Reason-APIs** (Apple: „Describing use of required reason API“): Gefunden per
Code-Suche nur `UserDefaults` (App-Einstellungen, Server-Adresse, Health-Sync-Anker in
`AppModel`, `PushManager`, `HealthSyncManager`, `HealthImport`). Deklariert ist `CA92.1`
(Lesen/Schreiben nur von Daten derselben App, keine App Group). Andere Kategorien
(Dateizeitstempel, System-Uptime, Speicherplatz, aktive Tastaturen) kommen per Suche
nicht vor. Die Apple-Seite war maschinell nicht lesbar: Reason-Code vor der Einreichung
manuell gegen die Doku prüfen und die Suche wiederholen, wenn Code dazukommt. Auch
eingebundene Pakete brauchen eigene Manifeste; `LifeOSKit` ist eigener Code ohne
Drittanbieter.

**Datenerhebung** (`NSPrivacyCollectedDataTypes` und „App Privacy“ in App Store Connect):
Ein selbst betriebener Server heißt **nicht** automatisch „keine Datenerhebung“. Apple
definiert „collect“ als Übertragung vom Gerät, die dir oder Partnern Zugriff länger als
für die Anfrage nötig erlaubt (app-privacy-details). Die App überträgt dauerhaft
gespeichert an den Life-OS-Server: Gesundheitsdaten (HealthKit, Clinical Records),
Fitness, Kontodaten (E-Mail, Name), Inhalte (Aufgaben, Notizen, Dokumente), Geräte-Token
für Push, Gerätename. Ob das als Erhebung durch den Entwickler gilt, hängt davon ab, wer
den Server betreibt und Zugriff hat (nur der Nutzer selbst oder der Anbieter der App).
Das ist eine Produkt- und Rechtsentscheidung, keine technische.

Bis dahin ist `NSPrivacyCollectedDataTypes` im Manifest leer, und das ist **nicht** als
geprüfte Aussage zu lesen. Vor der App-Store-Einreichung (nicht nötig für interne
TestFlight-Tester):

1. Betriebsmodell festlegen (wer betreibt den Server, wer hat Zugriff).
2. Daraus pro Datentyp entscheiden: erhoben ja/nein, mit Identität verknüpft, Zweck
   „App-Funktionalität“, kein Tracking.
3. Manifest und App-Store-Connect-Angaben identisch befüllen, die Begründung hier ablegen.

## Abmelden und Geräteverlust

Abmelden widerruft das Gerät nur, wenn der Server erreichbar ist (best effort, siehe
`docs/backend-vertrag.md` §4). Offline oder bei Fehlern werden die Tokens nur lokal
gelöscht. Runbook bei Verlust oder Diebstahl: im Web unter Einstellungen › Geräte das
Gerät widerrufen; das beendet Access- und Refresh-Token sofort.

## iPad und Mac

- iPad: Seitenleisten-Navigation, alle Orientierungen (`project.yml`).
- Mac: Mac Catalyst, Sandbox + Netzwerk-Client, kein HealthKit (`LifeOS-Mac.entitlements`).
  Für die Mac-Verteilung über TestFlight ist ein eigener Mac-Build-Upload nötig.
