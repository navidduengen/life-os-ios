# Backend-Vertrag für die native App

Die App erwartet die folgenden Endpunkte im Life-OS-Backend (`navidduengen/life-os-prototype`). Sie setzen ADR-031-004 §2 und Schritt 5 der Umsetzungsreihenfolge um („Sanctum-Bearer-Tokens mit Scopes und Gerätekopplung, sobald die erste native App kommt“). Heute läuft `/api/v1` nur mit Session-Cookie und CSRF; ohne diese Endpunkte kann die App nur den Demo-Modus.

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

Ablauf: Ist der Nutzer nicht angemeldet, läuft der normale Web-Login (WorkOS, später OIDC mit Pocket ID) und kommt danach hierher zurück. Dann erzeugt der Server einen **Einmal-Code** (zufällig, nur gehasht gespeichert, 60 Sekunden gültig, einmal einlösbar), gebunden an `user_id`, `code_challenge` und `device_name`, und leitet weiter:

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

- Access-Token: Sanctum Personal Access Token, kurzlebig (Vorschlag 15 Minuten), Name = `device_name`, Abilities z. B. `study:read`, `study:write`, `tasks:*`, `calendar:read`.
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
- Abilities pro Route prüfen (`ability:tasks:write` usw.).
- Geräte in den Einstellungen anzeigen und einzeln widerrufen (`/api/v1/settings/devices`, ADR-031-004 §2).

## 6. Tresor-Entsperrung (später)

Für Health und Finance, nach ADR-031-004 §4:

1. `POST /api/v1/unlock/device-keys` – App registriert den Public Key (P-256) eines Secure-Enclave-Schlüssels, nutzbar nur nach Face ID (`biometryCurrentSet`). Eintrag in `unlock_credentials` mit `kind = device_key`.
2. `POST /api/v1/unlock/challenge` mit `{ "app": "health" }` → `{ "challenge": "…", "expires_in": 60 }`.
3. `POST /api/v1/unlock` mit `{ "app", "credential_id", "challenge", "signature" }` → Server prüft die ECDSA-Signatur und setzt die Entsperrung für dieses Token und diese App für z. B. 10 Minuten.
4. Ohne Entsperrung antworten Vault-Routen mit `423` und `code: step_up_required`. Die App behandelt das bereits als eigenen Fehlerfall.

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
