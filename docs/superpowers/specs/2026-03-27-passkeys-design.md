# Passkey Authentication — Design Spec

**Date:** 2026-03-27
**Status:** Approved

---

## Overview

Add WebAuthn passkey support to Scientia Cognita, allowing users to sign in using device biometrics (Touch ID, Face ID, Windows Hello) or device PIN without typing a password. Multiple passkeys can be registered per user, managed from the account settings page.

---

## Goals

- Users can sign in with a passkey from the login page (discoverable credentials — no email required)
- After signup, users are gently prompted to add a passkey via a dismissable banner
- Users can register multiple passkeys, rename them, and delete them from the settings page
- Passkeys coexist with existing auth methods (magic link, password) — no method is removed

---

## Non-Goals

- Passkeys do not replace or deprecate magic link or password authentication
- No MFA / step-up auth using passkeys (out of scope)
- No FIDO2 security key (cross-platform authenticator) special-casing — they work but are not a design target
- No admin-initiated passkey removal (admin can delete a user's account, which cascades)

---

## Dependency

Add `{:wax_, "~> 0.6"}` to `mix.exs`. `wax_` is the actively-maintained Elixir WebAuthn library. Verify function signatures against the exact version resolved at `mix lock` time — `wax_` has had API changes across minor versions.

`wax_` handles:
- Challenge generation (`Wax.new_registration_challenge/1`, `Wax.new_authentication_challenge/1`)
- Attestation verification on registration (`Wax.register/3`)
- Assertion verification on login (`Wax.authenticate/6`)
- AAGUID metadata for device name detection

---

## Data Model

### New table: `user_passkeys`

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| `id` | integer | PK | |
| `user_id` | integer | NOT NULL, FK → users(id), on_delete: delete_all | |
| `credential_id` | binary | NOT NULL | WebAuthn credential ID from authenticator |
| `public_key` | binary | NOT NULL | CBOR-encoded COSE public key |
| `sign_count` | integer | NOT NULL, default: 0 | Increments on each use; replay protection |
| `authenticator_attachment` | string | | `"platform"` or `"cross-platform"`, detected at registration |
| `label` | string | | Auto-detected device name, user-editable |
| `last_used_at` | utc_datetime | | Updated on each successful authentication |
| `inserted_at` | utc_datetime | NOT NULL | |
| `updated_at` | utc_datetime | NOT NULL | Updated when label is renamed |

**Indexes:**
- `unique_index(:user_passkeys, [:credential_id])` — credential IDs are globally unique
- `index(:user_passkeys, [:user_id])`

### New Ecto schema: `Accounts.UserPasskey`

Changesets:
- `creation_changeset/2` — validates `credential_id`, `public_key`, `sign_count`, `authenticator_attachment`, `label`, `user_id`
- `label_changeset/2` — validates `label` only (for rename)

### New context functions on `Accounts`

```elixir
list_passkeys(user)                      # returns [%UserPasskey{}], ordered by inserted_at desc
get_passkey_by_credential_id(cred_id)    # returns %UserPasskey{} preloaded with :user, or nil
user_has_passkeys?(user)                 # returns boolean — cheap existence check for banner plug
register_passkey(user, attrs)            # {:ok, passkey} | {:error, changeset}
update_passkey_label(passkey, label)     # {:ok, passkey} | {:error, changeset}
delete_passkey(user, passkey_id)         # {:ok, passkey} | {:error, :not_found | :unauthorized}
update_passkey_after_auth(passkey, sign_count, last_used_at)  # internal, called after successful auth
```

---

## App Config

Add to `config/config.exs`:

```elixir
config :scientia_cognita, :webauthn,
  origin: "http://localhost:4000",
  rp_id: "localhost",
  rp_name: "Scientia Cognita"
```

`config/prod.exs` overrides `origin` and `rp_id` with the production domain.

`config/test.exs` overrides `origin` and `rp_id` to match the values embedded in pre-computed WebAuthn test fixtures (typically `"http://localhost"` / `"localhost"`).

The `origin/0` and `rp_id/0` helper functions live as private functions on `UserPasskeyController`, reading from `Application.get_env/2`.

---

## Server Flow

### Registration (user already logged in)

1. `GET /users/passkeys/challenge/register`
   - Requires authenticated user
   - Calls `Wax.new_registration_challenge([attestation: "none", origin: origin()])`
   - Stores challenge struct in session under `:wax_registration_challenge`
   - Returns JSON: `{challenge, user_id, user_name, rp_id, rp_name}`

2. Browser JS calls `navigator.credentials.create(options)` with `residentKey: "required"`, `userVerification: "preferred"`, `attestation: "none"`

3. `POST /users/passkeys`
   - Requires authenticated user
   - Retrieves and clears `:wax_registration_challenge` from session
   - Calls `Wax.register(attestation_object, client_data_json, challenge)`
   - Extracts `credential_id`, `public_key`, `sign_count` from result
   - Reads `authenticatorAttachment` from the request body (provided by JS from `credential.authenticatorAttachment`)
   - Detects label from AAGUID metadata where possible; falls back to `"Passkey (added #{Date.utc_today()})"`
   - Calls `Accounts.register_passkey(user, attrs)`
   - On success: JSON `{ok: true}` — JS redirects to `/users/settings`
   - On failure: JSON `{error: "..."}` — JS shows inline message

### Authentication (user not logged in)

1. `GET /users/passkeys/challenge/authenticate`
   - No auth required
   - Calls `Wax.new_authentication_challenge([origin: origin()])` — omitting `:allow_credentials` enables the discoverable credential flow
   - Stores challenge struct in session under `:wax_authentication_challenge`
   - Returns JSON: `{challenge}`

2. Browser JS calls `navigator.credentials.get({publicKey: {challenge, allowCredentials: [], userVerification: "preferred"}})` — OS presents account picker

3. `POST /users/passkeys/authenticate`
   - No auth required
   - Retrieves and clears `:wax_authentication_challenge` from session
   - Decodes `credential_id` from request body (base64url)
   - Calls `Accounts.get_passkey_by_credential_id(credential_id)` to find passkey + user
   - If not found: return JSON error (see Error Handling)
   - Calls `Wax.authenticate(credential_id, auth_data, sig, client_data_json, challenge, [{credential_id, passkey.public_key}])` — the 6th argument provides the known public key for the looked-up credential
   - Updates `sign_count` and `last_used_at` via `Accounts.update_passkey_after_auth/3`
   - Calls `UserAuth.log_in_user(conn, user)` — same as existing auth paths

### Session clearing interaction

`UserAuth.log_in_user/2` calls `renew_session/2` which invokes `clear_session/1`. This is intentional (prevents session fixation). The WebAuthn challenge is read from session and cleared **before** `log_in_user` is called — no conflict there. The banner dismiss key (`:passkey_banner_dismissed`) is also cleared on login; this is acceptable because the banner only shows when the user has no passkeys, and a user logging in via passkey already has one registered.

### Challenge Storage

Challenges stored in the Plug session:
- `:wax_registration_challenge` — cleared on use (success or failure) during registration
- `:wax_authentication_challenge` — cleared on use during authentication

Challenges are single-use and must be cleared regardless of success or failure to prevent replay.

---

## New Routes

```elixir
# Authenticated — passkey management
scope "/", ScientiaCognitaWeb do
  pipe_through [:browser, :require_authenticated_user]

  get    "/users/passkeys/challenge/register", UserPasskeyController, :registration_challenge
  post   "/users/passkeys",                    UserPasskeyController, :register
  patch  "/users/passkeys/:id",                UserPasskeyController, :update_label
  delete "/users/passkeys/:id",                UserPasskeyController, :delete
  delete "/users/passkeys/banner-dismiss",     UserPasskeyController, :dismiss_banner
end

# Unauthenticated — passkey login
scope "/", ScientiaCognitaWeb do
  pipe_through [:browser]

  get  "/users/passkeys/challenge/authenticate", UserPasskeyController, :authentication_challenge
  post "/users/passkeys/authenticate",            UserPasskeyController, :authenticate
end
```

**Route ordering note:** The `DELETE /users/passkeys/banner-dismiss` route must be declared before `DELETE /users/passkeys/:id` to avoid `:id` capturing `"banner-dismiss"`.

---

## New Controller: `UserPasskeyController`

Actions:
- `registration_challenge/2` — generates + returns registration challenge JSON
- `register/2` — verifies attestation, saves passkey, returns JSON
- `authentication_challenge/2` — generates + returns authentication challenge JSON
- `authenticate/2` — verifies assertion, logs user in
- `update_label/2` — updates passkey label, returns JSON
- `delete/2` — deletes passkey (with ownership check), returns JSON
- `dismiss_banner/2` — sets `:passkey_banner_dismissed` in session, returns JSON `{ok: true}` — JS hides the banner client-side

Private helpers:
- `origin/0` — returns `Application.get_env(:scientia_cognita, :webauthn)[:origin]`
- `rp_id/0` — returns `Application.get_env(:scientia_cognita, :webauthn)[:rp_id]`

All management actions (`register`, `update_label`, `delete`) verify `passkey.user_id == current_scope.user.id`.

---

## JS Layer

**New file:** `assets/js/passkeys.js`

Two exported functions, wired up via event listeners in `app.js`. All `fetch` calls include the CSRF token header: `headers: {"x-csrf-token": document.head.querySelector("meta[name=csrf-token]").content}`.

### `registerPasskey()`
1. `fetch GET /users/passkeys/challenge/register` → challenge JSON
2. Base64url-decode challenge and user ID
3. `navigator.credentials.create({publicKey: {challenge, rp: {id, name}, user: {id, name, displayName}, pubKeyCredParams: [{type: "public-key", alg: -7}, {type: "public-key", alg: -257}], authenticatorSelection: {residentKey: "required", userVerification: "preferred"}, attestation: "none"}})`
4. Base64url-encode `id`, `rawId`, `response.clientDataJSON`, `response.attestationObject`
5. Include `credential.authenticatorAttachment` in the POST body
6. `fetch POST /users/passkeys` with JSON body + CSRF header
7. On `{ok: true}`: `window.location = "/users/settings"`
8. On error: show inline error message near button

### `authenticatePasskey()`
1. `fetch GET /users/passkeys/challenge/authenticate` → challenge JSON
2. `navigator.credentials.get({publicKey: {challenge, allowCredentials: [], userVerification: "preferred"}})`
3. Base64url-encode assertion fields (`id`, `rawId`, `response.authenticatorData`, `response.clientDataJSON`, `response.signature`, `response.userHandle`)
4. `fetch POST /users/passkeys/authenticate` with JSON body + CSRF header → server redirects on success via `window.location`
5. On `NotAllowedError`: reset button silently (user cancelled)
6. On other error: show inline error near button

No external JS dependencies.

---

## UI Changes

### Login page (`lib/scientia_cognita_web/controllers/user_session_html/new.html.heex`)

Add a "Sign in with passkey" button at the **top** of the page, above the existing magic link and password forms, separated by `<div class="divider">or</div>` dividers.

Button: `btn btn-primary w-full` with a passkey SVG icon (fingerprint or key outline). On click, calls `authenticatePasskey()`, disables button during request, re-enables on error.

### Settings page (`lib/scientia_cognita_web/controllers/user_settings_html/edit.html.heex`)

Add a new **Passkeys** section below the existing password section, separated by `<div class="divider" />`.

Section contains:
- Serif heading "Passkeys" + subtitle text
- List of registered passkeys: icon (laptop if `authenticator_attachment == "platform"`, phone-like otherwise, defaulting to generic passkey icon) + label + "Last used X ago · Added Y" metadata + rename icon-button + delete icon-button
- "Add a passkey" outlined button (`btn btn-outline btn-primary btn-sm`)

Rename: clicking the pencil icon opens an inline edit (input replaces the label text, save/cancel).
Delete: clicking trash icon sends `DELETE /users/passkeys/:id` via JS fetch with CSRF header after `confirm()`.

Empty state (no passkeys yet): show subtitle "No passkeys registered yet." with only the "Add a passkey" button.

### Post-signup banner

The banner is rendered in the `Layouts.app` function component (`lib/scientia_cognita_web/components/layouts.ex`), which already receives `current_scope` as an assign. A new `:show_passkey_banner` assign is added to the component:

```elixir
attr :show_passkey_banner, :boolean, default: false
```

This assign is set by a `fetch_passkey_banner/2` plug defined in `lib/scientia_cognita_web/user_auth.ex` (alongside the other auth plugs) and called from the `:browser` pipeline in `router.ex`:

```elixir
# in user_auth.ex
def fetch_passkey_banner(conn, _opts) do
  if scope = conn.assigns[:current_scope] do
    dismissed = get_session(conn, :passkey_banner_dismissed)
    has_passkeys = Accounts.user_has_passkeys?(scope.user)
    assign(conn, :show_passkey_banner, !dismissed && !has_passkeys)
  else
    assign(conn, :show_passkey_banner, false)
  end
end
```

`Accounts.user_has_passkeys?/1` runs `Repo.exists?(from p in UserPasskey, where: p.user_id == ^user.id)` — a single cheap existence check. The plug guards against `nil` scope so it is safe for unauthenticated requests.

Banner styling: `bg-sc-primary-pale border border-primary/20`, passkey icon, headline "Add a passkey for one-tap sign-in", body text, "Set up" link to `/users/settings#passkeys`, dismiss `×` button that calls `DELETE /users/passkeys/banner-dismiss` via fetch with CSRF header.

`dismiss_banner/2` sets `put_session(conn, :passkey_banner_dismissed, true)` and returns JSON `{ok: true}` — JS hides the banner client-side.

---

## Error Handling

| Scenario | Handling |
|----------|----------|
| User cancels OS prompt (`NotAllowedError`) | JS resets button silently — no error shown |
| `Wax.register/3` rejects attestation | JSON `{error: "Could not verify passkey. Please try again."}` |
| Duplicate credential ID | DB unique constraint → JSON `{error: "This passkey is already registered."}` |
| `Accounts.get_passkey_by_credential_id` returns nil | JSON `{error: "No passkey found. Try another sign-in method."}` — no user enumeration since lookup is by credential, not email |
| `Wax.authenticate/6` fails signature check | JSON `{error: "Passkey verification failed."}` |
| `sign_count` regression | `wax_` emits a warning; login still proceeds. **Rationale:** many platform authenticators (e.g. iCloud Keychain) always return `sign_count = 0`, making strict regression enforcement produce false positives. Log at `:warning` level for visibility. |
| Delete: passkey belongs to another user | `{:error, :unauthorized}` → 403 JSON |

---

## Testing

- `Accounts` context: unit tests for all new functions with Ecto sandbox
- `UserPasskeyController`: controller tests using pre-computed WebAuthn fixtures that bypass the JS layer — requires matching `origin` and `rp_id` set in `config/test.exs`
- Registration and authentication flows tested by injecting pre-built fixture attestation/assertion objects with known keypairs
- Banner plug: unit test for `fetch_passkey_banner/2` — renders when no passkeys, does not render when passkeys exist or session is dismissed

---

## File Inventory

| File | Action |
|------|--------|
| `mix.exs` | Add `wax_` dependency |
| `config/config.exs` | Add webauthn config block |
| `config/prod.exs` | Add production origin/rp_id |
| `config/test.exs` | Add test origin/rp_id to match WebAuthn fixtures |
| `priv/repo/migrations/TIMESTAMP_create_user_passkeys.exs` | New migration |
| `lib/scientia_cognita/accounts/user_passkey.ex` | New schema |
| `lib/scientia_cognita/accounts.ex` | New context functions |
| `lib/scientia_cognita_web/controllers/user_passkey_controller.ex` | New controller |
| `lib/scientia_cognita_web/user_auth.ex` | Add `fetch_passkey_banner/2` plug |
| `lib/scientia_cognita_web/router.ex` | New routes; add `fetch_passkey_banner` to `:browser` pipeline |
| `lib/scientia_cognita_web/components/layouts.ex` | Add `:show_passkey_banner` attr + banner markup to `Layouts.app` |
| `lib/scientia_cognita_web/controllers/user_session_html/new.html.heex` | Add passkey button at top |
| `lib/scientia_cognita_web/controllers/user_settings_html/edit.html.heex` | Add passkeys section |
| `assets/js/passkeys.js` | New JS module |
| `assets/js/app.js` | Import passkeys.js, wire up event listeners |
| `test/scientia_cognita/accounts_test.exs` | New passkey context tests |
| `test/scientia_cognita_web/controllers/user_passkey_controller_test.exs` | New controller tests |
