# Backend-Vertrag für die native App

Die App erwartet die folgenden Endpunkte im Life-OS-Backend (`navidduengen/life-os-prototype`). Sie setzen ADR-031-004 §2 und Schritt 5 der Umsetzungsreihenfolge um („Sanctum-Bearer-Tokens mit Scopes und Gerätekopplung, sobald die erste native App kommt“).

**Stand 2026-10-01: umgesetzt** auf `life-os-prototype` main (`NativeAuthController`, `NativeAppTokens`, `NativeAuthCode`/`NativeRefreshToken`/`NativeDevice`, Migration `2026_10_01_210000_create_native_app_auth_tables`, `ValidateCsrfTokenUnlessBearer`, Test `tests/Feature/Auth/NativeAppTokensTest.php`). Abschnitte 1–5 gelten; Abweichungen vom ursprünglichen Entwurf sind unten markiert. Frühere Aussage „Endpunkte fehlen, nur Demo-Modus“ ist überholt.

Abgleich Client ↔ Server (statisch geprüft, 2026-10-01, prototype `9a99396`, iOS `5034e34`): Pfade, JSON-Feldnamen (snake_case), PKCE-Längen (Verifier 43 Zeichen, Challenge 43), `state`, Antwort `{access_token, refresh_token, expires_in}`, Fehlercodes (400 bei Code, 401 bei Refresh) und Logout passen.

Alle Antworten sind JSON, Fehler im bekannten Envelope `{ "message", "errors"? }`.

## 1. Login starten

`GET /auth/native/authorize`

| Parameter | Wert |
| :--- | :--- |
| `redirect_uri` | genau `lifeos://auth/callback` (Allowlist, keine anderen Schemes) |
| `code_challenge` | Base64URL(SHA-256(verifier)), ohne `=` |
| `code_challenge_method` | `S256` (einzig erlaubter Wert) |
| `state` | zufällig, wird unverändert zurückgegeben |
| `device_name` | z. B. „iPhone von Navid“, für die Geräteliste in den Einstellungen |

Ablauf: Ist der Nutzer nicht angemeldet, läuft der normale Web-Login (`redirect()->guest()` → Login → `redirect()->intended()`; welcher Anbieter, legt ADR-031-004 fest) und kommt danach hierher zurück. *Umgesetzt mit Zwischenschritt:* Der Server zeigt eine Bestätigungsseite („Life OS App anmelden?“), erst nach „Anmelden“ (`POST /auth/native/authorize`) kommt der Code. Dann erzeugt der Server einen **Einmal-Code** (zufällig, nur gehasht gespeichert, 60 Sekunden gültig, einmal einlösbar), gebunden an `user_id`, `code_challenge` und `device_name`, und leitet weiter:

```
302 Location: lifeos://auth/callback?code=<code>&state=<state>
```

Bei Abbruch oder fehlender Berechtigung: `lifeos://auth/callback?error=access_denied&state=<state>`.

Die Web-Session, die dabei entsteht, wird nicht an die App weitergegeben; die App öffnet das Anmeldefenster ephemer.

## 2. Code gegen Tokens tauschen

`POST /auth/native/token`

```json
{ "code": "…", "code_verifier": "…", "device_name": "iPhone von Navid" }
```

Prüfung: Code existiert, nicht abgelaufen, noch nicht eingelöst, `SHA-256(code_verifier)` passt zur gespeicherten Challenge. Danach Code sofort entwerten.

```json
{ "access_token": "…", "refresh_token": "…", "expires_in": 900 }
```

- Access-Token: Sanctum Personal Access Token, 15 Minuten, Name = `device_name`. *Umgesetzt:* Abilities `<bereich>:read` und `<bereich>:write` für die Bereiche in `NativeAppTokens::NATIVE_AREAS` (session, app-modules, home, today, tasks, notes, calendar, inbox, search, documents, links, health, finance, push, vault, settings.devices).
- Refresh-Token: eigener zufälliger Wert, nur gehasht gespeichert, an dasselbe Gerät gebunden, lange gültig (Vorschlag 60 Tage gleitend).

## 3. Erneuern

`POST /auth/native/refresh` mit `{ "refresh_token": "…" }` → gleiche Antwort wie oben.

- **Rotation:** Jeder Refresh-Token ist nur einmal gültig. Wird ein bereits benutzter Token erneut vorgelegt, alle Tokens dieses Geräts widerrufen (Diebstahl-Erkennung).
- Ungültig oder widerrufen → `401`.

Die App serialisiert Refreshes, schickt also nie zwei gleichzeitig.

## 4. Abmelden

`DELETE /auth/native/token` mit `Authorization: Bearer <access_token>` → `204`. Widerruft Access- und Refresh-Token des Geräts.

## 5. `/api/v1` mit Bearer-Token

- `auth:sanctum` statt nur `auth` auf der `/api/v1`-Gruppe, damit Session (Web) und Bearer (App) beide funktionieren.
- CSRF gilt nur für Cookie-Requests. Requests mit `Authorization: Bearer` und ohne Session-Cookie dürfen keinen `419` bekommen.
- Abilities pro Route prüfen. *Umgesetzt:* `EnsureTokenAbility` auf der ganzen `/api/v1`-Gruppe leitet die Ability aus dem Routennamen ab (`api.v1.tasks.store` → `tasks:write`; GET = `read`, sonst `write`; Einstellungen pro Unterbereich, z. B. `settings.devices:read`). Fehlt sie, `403`. Für App-Tokens gesperrt: Study, Sammlungen, Ressourcen, Integrationen, Onboarding und alle Einstellungen außer Geräte (Passwort, Profil, Admin, KI-Provider). Braucht die App einen neuen Bereich, muss er in `NATIVE_AREAS` ergänzt werden; sonst bekommt sie 403.
- Geräte in den Einstellungen anzeigen und einzeln widerrufen (`/api/v1/settings/devices`, ADR-031-004 §2).

## 6. Tresor-Entsperrung (später)

Für Health und Finance, nach ADR-031-004 §4:

1. `POST /api/v1/unlock/device-keys` – App registriert den Public Key (P-256) eines Secure-Enclave-Schlüssels, nutzbar nur nach Face ID (`biometryCurrentSet`). Eintrag in `unlock_credentials` mit `kind = device_key`.
2. `POST /api/v1/unlock/challenge` mit `{ "app": "health" }` → `{ "challenge": "…", "expires_in": 60 }`.
3. `POST /api/v1/unlock` mit `{ "app", "credential_id", "challenge", "signature" }` → Server prüft die ECDSA-Signatur und setzt die Entsperrung für dieses Token und diese App für z. B. 10 Minuten.
4. Ohne Entsperrung antworten Vault-Routen mit `423` und `code: step_up_required`. Die App behandelt das bereits als eigenen Fehlerfall.

## 7. Apple Health (umgesetzt in `life-os-prototype`, Branch `claude/apple-health-import`)

| Endpunkt | Zweck |
| :--- | :--- |
| `POST /api/v1/health/apple-health/import` | `{samples: [...], deleted: [UUID]}`, je höchstens 500. Upsert pro Nutzer auf `external_id` (HealthKit-UUID). |
| `GET /api/v1/health/apple-health/types` | Pro Datentyp Anzahl, Zeitraum, letzter Wert (Web-Übersicht). |
| `GET /api/v1/health/apple-health/samples` | Einträge eines Typs, paginiert. |
| `GET /api/v1/health/apple-health/daily` | Tageswerte (Summe, Durchschnitt, Min, Max, Dauer) in Berliner Zeit. |
| `DELETE /api/v1/health/apple-health` | Alles oder `?type=` löschen. |

Die App schickt Metadaten-Schlüssel schon in snake_case und FHIR-JSON von Gesundheitsakten als Text (`fhir_json`), weil der JSON-Encoder sonst auch Schlüssel in Wörterbüchern umschreibt. Der Typ-Katalog (207 Typen) kommt aus `scripts/health_types.py` und wird für App und Web erzeugt:

```bash
python3 scripts/health_types.py ../life-os-prototype
```

Der Import ist nur schreibend. Sobald die Tresor-Entsperrung (Abschnitt 6) steht, sollten die lesenden Apple-Health-Endpunkte hinter `app.unlocked:health`; der Import braucht dann nur einen Token mit Scope `health:import`.

## 8. Push-Mitteilungen (umgesetzt, standardmäßig aus)

Schalter im Backend: `PUSH_NOTIFICATIONS_ENABLED=true` **und** APNs-Schlüssel (`APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_PRIVATE_KEY` mit dem Inhalt der `.p8`-Datei, `APNS_BUNDLE_ID`, `APNS_ENVIRONMENT`). Erst dann meldet `GET /api/v1/push/config` `enabled: true`. Die App zeigt vorher keine Push-Einstellungen, fragt keine Erlaubnis ab und registriert kein Gerät. Das Feature lässt sich also ohne App-Update später einschalten.

| Endpunkt | Zweck |
| :--- | :--- |
| `GET /api/v1/push/config` | `enabled` und die Arten von Mitteilungen |
| `POST/DELETE /api/v1/push/devices` | Gerätetoken registrieren oder abmelden (`409`, solange Push aus ist) |
| `GET/PATCH /api/v1/push/preferences` | Arten an- und abschalten |
| `POST /api/v1/push/test` | Testmitteilung an alle eigenen Geräte |

Gesendet wird: Termin in 15 Minuten (alle 5 Minuten geprüft), morgendliche Liste fälliger Aufgaben (07:30, `PUSH_DIGEST_TIME`), „Befund ausgelesen“ nach dem Auslesen eines Bluttests. Texte nennen nie Werte, weil sie auf dem Sperrbildschirm stehen. Jede Erinnerung geht pro Nutzer nur einmal raus (`push_deliveries`).

Zum Einschalten in Apple Developer: App-ID `app.lifeos.ios` mit Push Notifications und HealthKit (inkl. Clinical Health Records und Background Delivery), einen APNs-Schlüssel anlegen und in **Azure Key Vault** eintragen (führende Secret-Quelle, ADR-031-005 im Backend-Repo; Vault-Namen mit `-`: `APNS-KEY-ID`, `APNS-TEAM-ID`, `APNS-PRIVATE-KEY`, `APNS-BUNDLE-ID`, `APNS-ENVIRONMENT`, `PUSH-NOTIFICATIONS-ENABLED`). Früher stand hier Doppler; das ist ersetzt. Für TestFlight/App Store `APNS_ENVIRONMENT=production` und in `App/LifeOS.entitlements` `aps-environment` auf `production`.

## Was die App sonst vom Backend nutzt

| Endpunkt | Bildschirm |
| :--- | :--- |
| `GET /api/v1/session` | Konto |
| `GET /api/v1/app-modules` | Apps, Seitenleiste |
| `GET /api/v1/today` | Heute |
| `GET /api/v1/tasks`, `POST /api/v1/tasks`, `PATCH /api/v1/tasks/{id}/transition` | Aufgaben |
| `GET /api/v1/calendar?month=YYYY-MM` | Kalender |
| `GET /api/v1/inbox` | Posteingang |

Wunsch an die API: `icon`, `accent`, `order` und `tagline` aus `module.json` auch in `/api/v1/app-modules` ausliefern. Bis dahin pflegt die App diese Werte in `AppModuleCatalog` doppelt.
