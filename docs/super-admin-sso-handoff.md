# Handoff — Super Admin SSO reverse-proxy gating

Rails side is done in this branch (see `app/controllers/super_admin/devise/sessions_controller.rb`,
`app/helpers/password_login_guard.rb`, `app/controllers/dashboard_controller.rb`,
`config/installation_config.yml`). This doc is the contract the reverse proxy
(OAuth2-Proxy + Nginx + Keycloak) must satisfy — that piece is being built outside this repo.

## What Rails now does

- **Normal user login**: email/password is shown/accepted only while the
  `ENABLE_EMAIL_PASSWORD_LOGIN` installation config is `true` (Super Admin →
  Settings → same mechanism as the existing Google OAuth/SAML toggles). Flip
  it to `false` once SSO rollout is confirmed — this hides the password form
  on `/app/login` (and the signup link, since signup creates a password
  account) and makes `POST /auth/sign_in` return
  `403 { "message": "Password authentication is disabled. Please use SSO to sign in." }`
  for any request that isn't a valid `sso_auth_token` handoff. This applies to
  **every** user, including account admins — no password fallback is kept.
- **Super Admin login** (`/super_admin`): gated behind env vars, off by
  default. When `SUPER_ADMIN_SSO_ENABLED=true`, the password form and the
  password `POST` are both disabled, and `GET /super_admin` instead:
  1. Requires a shared-secret header to match `SUPER_ADMIN_SSO_SECRET` exactly
     (`ActiveSupport::SecurityUtils.secure_compare`, fails closed if the env
     var is unset).
  2. Reads the identity email header and looks up `SuperAdmin.from_email`.
  3. Signs the matched admin in and redirects to `/super_admin/users`. Any
     failure (secret mismatch, missing header, no matching `SuperAdmin`
     record) renders a plain `403 Forbidden` — there is no fallback to the
     password form once this mode is on.

## Env vars the proxy/host side must set on the Rails app

| Var | Default | Notes |
|---|---|---|
| `SUPER_ADMIN_SSO_ENABLED` | `false` | Set `true` only once the proxy is live in front of `/super_admin`. |
| `SUPER_ADMIN_SSO_EMAIL_HEADER` | `X-Auth-Request-Email` | Header name carrying the authenticated email. Rename if you'd rather not use the OAuth2-Proxy default. |
| `SUPER_ADMIN_SSO_SECRET_HEADER` | `X-Auth-Request-Proxy-Secret` | Header name carrying the shared secret. |
| `SUPER_ADMIN_SSO_SECRET` | *(none — required)* | Shared secret value. Generate something like `openssl rand -hex 32`. Must be injected into Nginx/oauth2-proxy config and into the Rails app's env identically. |

## Non-negotiable requirements for the Nginx/OAuth2-Proxy side

1. **Strip both headers from the client before `auth_request` runs.** Add
   `proxy_set_header X-Auth-Request-Email "";` and the secret header
   equivalent at the top of the `/super_admin` location block, *before* the
   `auth_request` directive populates them from the proxy's response. If this
   step is skipped, anyone can set `X-Auth-Request-Email` themselves and
   spoof a super admin.
2. **Set the secret header only from Nginx/oauth2-proxy config, never from
   anything proxy-controlled by the client.** It should be a static value
   baked into the Nginx config (e.g. via an env var at container start), not
   derived from the Keycloak token.
3. **Enforce the `chatwoot_superadmin` role check at the proxy, not just at
   Chatwoot.** OAuth2-Proxy should reject (403) before Chatwoot is ever hit if
   the authenticated Keycloak user (realm: `auth.314ecorp.tech` per
   `docs/saml-community-edition.md`) lacks the role — Chatwoot's own check
   (`SuperAdmin.from_email`) is a second layer, not a substitute, since it
   only verifies *whether* the email maps to a known super admin, not whether
   Keycloak authorized them for this console.
4. **Make sure Rails/Puma isn't reachable on any path that bypasses this
   Nginx block** (firewall/security-group level). The header trust model
   only holds if there's no way to hit `/super_admin` directly.
5. Email matching is case-insensitive and exact (`User.from_email`
   downcases). Make sure the Keycloak claim used for the email header matches
   the `SuperAdmin` record's `email` column values here.

## Verification checklist once the proxy is in place

- [ ] Hitting `/super_admin` directly (bypassing Nginx, if reachable in a test
      env) does not grant access — confirms header stripping + secret are
      effective.
- [ ] A corporate user authenticated in Keycloak but without the
      `chatwoot_superadmin` role gets `403` from the proxy, never reaches
      Chatwoot.
- [ ] A user with the role and a matching `SuperAdmin` record is signed in
      automatically, no password screen shown.
- [ ] A user with the role but **no** matching `SuperAdmin` record gets a
      plain `403` from Rails (not a password form, not a stack trace).
- [ ] With `SUPER_ADMIN_SSO_ENABLED=true` and `SUPER_ADMIN_SSO_SECRET` unset,
      access is denied (fail-closed check).
