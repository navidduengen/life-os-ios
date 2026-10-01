# Entscheidungen für die Apps

Öffentlicher Auszug aus dem Projektgedächtnis im Backend-Repo
(`life-os-prototype/docs/life-os/projektgedaechtnis.md`). Hier steht nur, was für die
Apple-Apps gilt und nichts Privates enthält. Verbindlich sind die ADRs im Backend-Repo.
Ersetzte Entscheidungen bleiben zur Nachvollziehbarkeit stehen.

Stand: 2026-10-01, 21:00 UTC.

## Gültig

| Entscheidung | Quelle |
| --- | --- |
| Jede Funktion soll auf Web, iPhone, iPad und Mac verfügbar sein. Die Apple-Apps liegen gemeinsam in diesem Repo (SwiftUI, Mac über Catalyst) und sprechen dieselbe `/api/v1` wie das Web. | ADR-031-001, Projektgedächtnis |
| Vor größeren UI-Entscheidungen Varianten oder Mockups zeigen. | Projektgedächtnis |
| Offline als dünner Client: lesen und erfassen offline, volles Offline-Bearbeiten erst bei Bedarf. | ADR-031-003 |
| Login nur im System-Anmeldefenster (`ASWebAuthenticationSession`), nie in einer WebView. PKCE, Access-Token 15 Minuten, rotierender Refresh-Token 60 Tage, Geräte einzeln widerrufbar. | ADR-031-004 §2, `docs/backend-vertrag.md` |
| Web-Login: Laravel-eigene Passkeys, optional Auth0; nur eingeladene oder zugeordnete Konten. | ADR-031-004 (2026-10-01), Backend-PR #20 |
| App-Tokens bekommen Scopes pro Bereich; Konto-, Admin- und Integrationsrouten sind für App-Tokens gesperrt. | ADR-031-004 §2, Backend-PR #32 (noch nicht gemergt) |
| Health und Finance sind Tresor-Apps: Der Server erzwingt die Entsperrung (Geräteschlüssel aus der Secure Enclave nach Face ID). Face ID nur in der App reicht nicht. Abschaltbar, solange nicht alle Clients entsperren können. | ADR-031-002, ADR-031-004 §4, Backend-PR #25 |
| Secrets (z. B. APNs-Schlüssel) liegen in Azure Key Vault; im Repo stehen nur Namen. | ADR-031-005 |
| Automatische Swift-Tests und iOS/Mac-Builds sind pausiert; lokal oder per manuellem Lauf prüfen. | `docs/actions-budget.md` |
| Neue Abhängigkeiten nur mit ausdrücklicher Freigabe. | AGENTS.md im Backend-Repo |

## Ersetzt

| Alt | Ersetzt durch | Datum |
| --- | --- | --- |
| Web-Login über WorkOS AuthKit | OIDC mit Pocket ID (ADR-031-004 §1) | 2026-09-30 |
| Pocket ID / Tinyauth als Login | Laravel-Passkeys + optional Auth0 | 2026-10-01 |
| APNs-Schlüssel in Doppler | Azure Key Vault | 2026-10-01 |
| „Backend hat keine App-Login-Endpunkte, nur Demo-Modus“ | Endpunkte auf Backend-main | 2026-10-01 |

## Offen

- Datenschutzangaben für den App Store hängen vom Betriebsmodell des Servers ab (siehe
  `docs/release.md`, Abschnitt Datenschutz).
- Sichtbarkeit dieses Repos (öffentlich) liegt bei Navid und wird nicht eigenständig
  geändert.
