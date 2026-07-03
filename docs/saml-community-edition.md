# SAML SSO in Community Edition — Change & Setup Runbook

This document describes how SAML SSO (originally an Enterprise-only feature) was
ported into the OSS/Community tree, and exactly how to apply and configure it on
another database or a running Chatwoot instance (including a production-ready
branch).

---

## 1. Overview

- SAML was moved out of `enterprise/` into the OSS `app/` tree.
- `saml` is now a **free, non-premium, per-account feature flag** (not gated by plan).
- Administrators always keep **password login** (they are never switched to the
  `saml` auth provider), so enabling SAML can never lock admins out.
- The SSO login route works on pure Community installs (gated on SAML being an
  allowed login method, not on the enterprise flag).
- One-click SSO: the login page can initiate SAML directly via URL params
  (`?account_id=` or `?email=`), skipping the manual work-email screen.
- Per-account `kc_idp_hint` support (skips Keycloak's IdP picker) passed through
  omniauth-saml's runtime-params mechanism.

Libraries: **omniauth-saml 2.2.4** wrapping **ruby-saml 1.18.1** (already in the
OSS Gemfile). No new gems required.

---

## 2. File inventory

### New OSS files
| File | Purpose |
|------|---------|
| `app/models/account_saml_settings.rb` | Per-account SAML settings model (validates X.509 cert, generates SP entity id, triggers provider-flip job) |
| `app/policies/account_saml_settings_policy.rb` | Admin-only authorization |
| `app/builders/saml_user_builder.rb` | Find/create user from assertion, role mapping, JIT provisioning |
| `app/controllers/api/v1/accounts/saml_settings_controller.rb` | CRUD for account SAML settings |
| `app/controllers/api/v1/auth_controller.rb` | `saml_login` — initiates SP-initiated SSO |
| `app/jobs/saml/update_account_users_provider_job.rb` | Flips account users between `email`/`saml` provider (skips admins) |
| `app/helpers/saml_authentication_helper.rb` | Password-vs-SAML guard (`reject_saml_user_password_login`) |
| `config/initializers/omniauth_saml.rb` | Multi-tenant `SAML_SETUP_PROC` + `provider :saml` middleware |
| `app/views/api/v1/models/_account_saml_settings.json.jbuilder` | Response partial |
| `app/views/api/v1/accounts/saml_settings/{show,create,update}.json.jbuilder` | Action views |
| `db/migrate/20260703000000_add_idp_hint_to_account_saml_settings.rb` | Adds `idp_hint` column |

### Modified OSS files (backend)
| File | Change |
|------|--------|
| `app/models/account.rb` | `has_one :saml_settings`; `saml_enabled?` |
| `app/controllers/devise_overrides/omniauth_callbacks_controller.rb` | SAML handling (`redirect_callbacks`, `omniauth_success` branch, `omniauth_failure`, `handle_saml_auth`, helpers, `auth_hash`) |
| `app/controllers/devise_overrides/sessions_controller.rb` | `before_action :reject_saml_user_password_login` |
| `app/controllers/devise_overrides/passwords_controller.rb` | SAML password-reset guard |
| `app/controllers/dashboard_controller.rb` | Allow `saml` login method for the `community` plan |
| `config/features.yml` | `saml` → `premium: false` |
| `db/schema.rb` | `idp_hint` column (from migration) |

### Modified OSS files (frontend)
| File | Change |
|------|--------|
| `app/javascript/dashboard/featureFlags.js` | Remove `SAML` from `PREMIUM_FEATURES` |
| `app/javascript/dashboard/routes/dashboard/settings/security/security.routes.js` | Add `INSTALLATION_TYPES.COMMUNITY` |
| `app/javascript/dashboard/routes/dashboard/settings/security/Index.vue` | Add `COMMUNITY` to `shouldShow` |
| `app/javascript/dashboard/routes/dashboard/settings/security/components/SamlSettings.vue` | Optional **IdP Hint** field |
| `app/javascript/dashboard/i18n/locale/en/settings.json` | `IDP_HINT` strings |
| `app/javascript/v3/helpers/RouteHelper.js` | `requireSaml` gate (uses `allowedLoginMethods`) |
| `app/javascript/v3/views/routes.js` | `requireSaml`; pass `account_id`/`email` props |
| `app/javascript/v3/views/login/Saml.vue` | Auto-submit when `account_id`/`email` present |

### Deleted Enterprise files (moved to OSS)
```
enterprise/app/models/account_saml_settings.rb
enterprise/app/policies/account_saml_settings_policy.rb
enterprise/app/builders/saml_user_builder.rb
enterprise/app/controllers/api/v1/accounts/saml_settings_controller.rb
enterprise/app/controllers/api/v1/auth_controller.rb
enterprise/app/jobs/saml/update_account_users_provider_job.rb
enterprise/app/helpers/saml_authentication_helper.rb
enterprise/config/initializers/omniauth_saml.rb
enterprise/app/controllers/enterprise/devise_overrides/passwords_controller.rb
enterprise/app/views/api/v1/models/_account_saml_settings.json.jbuilder
enterprise/app/views/api/v1/accounts/saml_settings/{show,create,update}.json.jbuilder
```

### Trimmed Enterprise files (kept non-SAML logic)
| File | Change |
|------|--------|
| `enterprise/app/models/enterprise/concerns/account.rb` | Removed `has_one :saml_settings` |
| `enterprise/app/models/enterprise/account.rb` | Removed `saml_enabled?` |
| `enterprise/app/controllers/enterprise/devise_overrides/omniauth_callbacks_controller.rb` | Removed SAML branches; kept marketing attribution |
| `enterprise/app/controllers/enterprise/devise_overrides/sessions_controller.rb` | Removed SAML guard; kept audit events |

> Safe because `prepend_mod_with`/`include_mod_with` no-op when the enterprise
> module is absent, and `ChatwootApp.extensions` is empty in a pure-CE build.

---

## 3. Applying to another database / running Chatwoot

### 3.1 Apply the code
Merge/cherry-pick the feature branch (see the commit that accompanies this doc).
No new gems are needed (omniauth-saml / ruby-saml are already present).

### 3.2 Run the migration
The base table `account_saml_settings` is created by the pre-existing upstream
migration `20250825070005_create_account_saml_settings.rb`. This change only adds
the `idp_hint` column:

```bash
bundle exec rails db:migrate
# adds: account_saml_settings.idp_hint (string)
```

If the target DB predates the base table (unlikely on current Chatwoot), that
create migration runs first automatically.

### 3.3 Enable the feature per account
`saml` defaults to **off** per account (free, but opt-in). Enable it via Super
Admin (Account → Features) or the console:

```bash
bundle exec rails runner "Account.find(<ID>).enable_features!('saml')"
```

### 3.4 Environment
- `ENABLE_SAML_SSO_LOGIN` — defaults to `true`. Set to `false` to disable SAML
  installation-wide.
- `FRONTEND_URL` — **important**: the SP Entity ID and ACS URL are derived from
  this. It is read via `GlobalConfigService` (DB `InstallationConfig` first, then
  ENV). Ensure it is the externally reachable base URL, e.g.
  `https://chat.example.com`. To correct a stale DB value:

  ```bash
  bundle exec rails runner "InstallationConfig.find_by(name: 'FRONTEND_URL')&.update!(value: 'https://chat.example.com'); GlobalConfig.clear_cache"
  ```

> There is no global `SAML_KC_IDP_HINT` env — the IdP hint is configured per
> account (see §4).

### 3.5 Configure SAML settings for an account
Via **Settings → Security → SAML** in the dashboard (admin), or the console:

```bash
bundle exec rails runner '
  a = Account.find(<ID>)
  a.enable_features!("saml")
  a.create_saml_settings!(
    sso_url: "https://<keycloak>/realms/<realm>/protocol/saml",
    idp_entity_id: "https://<keycloak>/realms/<realm>",
    certificate: File.read("/path/to/realm_signing_cert.pem"),
    idp_hint: "" # optional upstream IdP alias for kc_idp_hint
  )
'
```

Creating settings enqueues `Saml::UpdateAccountUsersProviderJob` which flips that
account's **non-admin** users to `provider: 'saml'`.

---

## 4. Keycloak configuration (per realm/client)

Create a **SAML client** in the realm that holds your users:

| Keycloak setting | Value |
|------------------|-------|
| Client ID (SP Entity ID) | `<FRONTEND_URL>/saml/sp/<account_id>` |
| Valid Redirect URI / ACS | `<FRONTEND_URL>/omniauth/saml/callback?account_id=<account_id>` |
| Name ID format | `email` (force) |
| Client signature required (`saml.client.signature`) | **OFF** (we send unsigned requests) |
| Sign Documents / Sign Assertions | ON (verified against `certificate`) |

Chatwoot side (SAML settings):
- `sso_url` = `https://<keycloak>/realms/<realm>/protocol/saml`
- `idp_entity_id` = `https://<keycloak>/realms/<realm>`
- `certificate` = the **realm's IdP signing cert** (X.509 PEM) from
  `…/realms/<realm>/protocol/saml/descriptor` — **not** the client's SP cert.

### Skipping Keycloak's IdP picker
Two options:
1. **Per-account IdP Hint** field → sent as `kc_idp_hint` via
   `idp_sso_service_url_runtime_params` (library-built URL). The value must be the
   exact **Identity Provider alias** in that realm. `kc_idp_hint` support on the
   SAML endpoint is Keycloak-version-dependent.
2. **Identity Provider Redirector** (Keycloak Browser flow → Default IdP): auto-
   forwards on a plain SAML request; version-independent. Recommended if
   `kc_idp_hint` is rejected.

---

## 5. Login entry points

- Standard: `/app/login` → "Login via SSO" → `/app/login/sso` (enter work email).
- One-click direct: `/app/login/sso?account_id=<id>` or
  `/app/login/sso?email=<email>` — auto-submits, skipping the email screen.
- Admins should log in with **password** on `/app/login` (they are never SAML-only).

---

## 6. Troubleshooting (issues encountered & resolutions)

| Symptom | Cause | Fix |
|---------|-------|-----|
| Keycloak 400, SP Entity ID shows `0.0.0.0` | `FRONTEND_URL` `InstallationConfig` stale; SP entity id generated from it | Update `InstallationConfig` FRONTEND_URL + `GlobalConfig.clear_cache`; fix existing record's `sp_entity_id` |
| Keycloak 400 "Invalid requester" | Client "Client signature required" ON, Chatwoot sends unsigned request | Turn OFF client signature required (or implement SP request signing) |
| Redirect back → `access-denied`, `Devise::OmniauthCallbacksController#failure` | Wrong `certificate` (SP client cert instead of realm IdP cert) → signature verify fails | Store the realm IdP signing cert from the SAML descriptor |
| 500 in `SamlUserBuilder` (`split` on nil) | IdP sends no `email` attribute; email only in NameID | Builder falls back to NameID (`saml_email`); optionally add email attribute mapper in Keycloak |
| Admin can't log in with password ("wrong credentials") | Admin `provider` flipped to `saml`; DTA password auth only matches `provider: 'email'` | Admins are never converted now; reset any stuck admin: `User.where(provider:'saml') ... update_all(provider:'email')` for admins |
| Keycloak 400 "Invalid Request" with `kc_idp_hint` | Hint string-appended to base URL / invalid alias | Pass via `idp_sso_service_url_runtime_params`; ensure alias exists in the realm; or use IdP Redirector |
| SSO email page redirects to a different user | Keycloak IdP session reused (SSO); email on Chatwoot page is only for IdP discovery | Log out of Keycloak / use incognito; or configure ForceAuthn |

### One-off data fixes used during bring-up (instance-specific, not code)
```bash
# Correct FRONTEND_URL config + existing SP entity id
bundle exec rails runner '
  InstallationConfig.find_by(name: "FRONTEND_URL")&.update!(value: "http://localhost:3000"); GlobalConfig.clear_cache
  s = AccountSamlSettings.first; s&.update_column(:sp_entity_id, "http://localhost:3000/saml/sp/#{s.account_id}")
'
# Reset an admin locked out after provider flip
bundle exec rails runner 'User.from_email("admin@example.com").update_column(:provider, "email")'
```

---

## 7. Validation performed
- `bundle exec rails zeitwerk:check` → All is good (no constant collisions).
- `bundle exec rubocop` on all changed Ruby → 0 offenses.
- `pnpm eslint` on changed Vue/JS → no new errors.
