# Release: Build, Signing, TestFlight

Stand 2026-10-01. Hält fest, was für einen TestFlight-Build real geprüft ist und was nur
mit Apple-Konto, Mac oder Gerät geht.

## Geprüft (ohne Mac, in einer Linux-Sandbox)

| Was | Ergebnis | Grundlage |
| :--- | :--- | :--- |
| Login-Vertrag App ↔ Backend | passt (Pfade, Felder, PKCE, Rotation, Logout) | statischer Abgleich, `docs/backend-vertrag.md` |
| `PrivacyInfo.xcprivacy` | vorhanden, Plist gültig | neu, Grund `CA92.1` für UserDefaults |
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
6. **Datenschutzangaben** in App Store Connect: Die App überträgt Daten nur an den
   eigenen Server des Nutzers. `NSPrivacyCollectedDataTypes` ist leer; vor der Einreichung
   prüfen, ob Apple das für einen selbst betriebenen Server so akzeptiert.
7. **Server-Adresse**: TestFlight-Tester brauchen einen erreichbaren HTTPS-Server mit
   aktuellem Backend (Native-Auth-Migration ausgeführt).

## iPad und Mac

- iPad: Seitenleisten-Navigation, alle Orientierungen (`project.yml`).
- Mac: Mac Catalyst, Sandbox + Netzwerk-Client, kein HealthKit (`LifeOS-Mac.entitlements`).
  Für die Mac-Verteilung über TestFlight ist ein eigener Mac-Build-Upload nötig.
