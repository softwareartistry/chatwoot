# Handoff Brief — SAML SSO for Chatwoot Community Edition

Paste this into a new Claude session to resume.

## Context
Repo: Chatwoot (Rails 7.1 + Vue 3), branch work done on `develop` (not production-ready).
Goal: bring SAML SSO (Enterprise-only) into the Community/OSS tree, wired to a
Keycloak IdP (`auth.314ecorp.tech`), and streamline the login flow.

Local dev: rbenv Ruby 3.4.4, Postgres 14 (+pgvector built for pg14), Redis via brew,
`overmind start -f Procfile.dev`, app at `http://localhost:3000`. Seed admin
`john@acme.inc` / `Password1!`. Full runbook: `docs/saml-community-edition.md`.

## What's done (working end-to-end)
- SAML moved from `enterprise/` → OSS `app/`; enterprise duplicates deleted/trimmed.
- `saml` is a free per-account feature flag (`config/features.yml` premium:false).
- Login/callback/token-exchange verified against Keycloak.
- **Admins never converted to `provider:'saml'`** → keep password login (avoids
  lockout; DTA password auth only matches `provider:'email'`).
- SSO route open to pure-CE (`requireSaml` gate on `allowedLoginMethods`).
- One-click SSO via `/app/login/sso?account_id=<id>` (or `?email=`) auto-submit.
- Per-account **IdP Hint** → `kc_idp_hint`, passed via omniauth-saml
  `idp_sso_service_url_runtime_params` (NOT string-appended — that caused Keycloak 400).
- Global `SAML_KC_IDP_HINT` env fallback removed (per-account only).

## Key architectural decisions
- Library-native param passing for `kc_idp_hint` (ruby-saml builds/sign-safe URL).
- Admin exemption implemented at the source (provider-flip job + builder skip admins),
  plus a defense-in-depth guard in `SamlAuthenticationHelper`.
- SP Entity ID / ACS derived from `FRONTEND_URL` (via `GlobalConfigService` →
  `InstallationConfig` first, then ENV). Cert must be the **realm IdP signing cert**.
- Keycloak client: "Client signature required" OFF (unsigned AuthnRequest);
  Sign Documents/Assertions ON.

## Open items / not done
- No automated specs (project convention: only when asked). Consider request specs
  for `auth#saml_login`, callback, builder, and the admin-password safeguard.
- `kc_idp_hint` on Keycloak's SAML endpoint is version-dependent; realm `test23`
  works with alias `penknife-google-basic`. If a realm rejects it, use Keycloak's
  Identity Provider Redirector instead.
- Multi-tenant `idp_hint` is a single string column; fine for one IdP per account.

## Immediate next steps (candidates)
1. Add request specs for the SAML flow + admin-password safeguard.
2. Optionally wire the main login page "Login via SSO" button to a default
   `?account_id=` for true one-click.
3. Port to the production-ready branch (see file inventory in
   `docs/saml-community-edition.md`).

## Gotchas already solved (don't re-debug)
- 400 entity-id mismatch → FRONTEND_URL `InstallationConfig` was `0.0.0.0`.
- 400 "Invalid requester" → client signature required was ON.
- access-denied/#failure → wrong cert (SP cert vs realm IdP cert).
- 500 in builder → assertion had no email attribute → fall back to NameID.
- Admin lockout → provider flipped to saml → admins now exempt.
- kc_idp_hint 400 → must go through runtime params, not URL append.
