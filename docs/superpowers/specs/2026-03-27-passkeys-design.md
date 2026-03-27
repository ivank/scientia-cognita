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

Add `{:wax_, "~> 0.6"}` to `mix.exs`. `wax_` is the actively-maintained Elixir WebAuthn library that handles:
- Challenge generation (`Wax.new_registration_challenge/1`, `Wax.new_authentication_challenge/1`)
- Attestation verification on registration (`Wax.register/3`)
- Assertion verification on login (`Wax.authenticate/5`)
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
| `label` | string | | Auto-detected device name, user-editable |
| `last_used_at` | utc_datetime | | Updated on each successful authentication |
| `inserted_at` | utc_datetime | NOT NULL | |
| `updated_at` | utc_datetime | NOT NULL | Updated when label is renamed |

**Indexes:**
- `unique_index(:user_passkeys, [:credential_id])` — credential IDs are globally unique
- `index(:user_passkeys, [:user_id])`

### New Ecto schema: `Accounts.UserPasskey`

Changesets:
- `creation_changeset/2` — validates `credential_id`, `public_key`, `sign_count`, `label`, `user_id`
- `label_changeset/2` — validates `label` only (for rename)

### New context functions on `Accounts`

```elixir
list_passkeys(user)                      # returns [%UserPasskey{}], ordered by inserted_at desc
get_passkey_by_credential_id(cred_id)    # returns %UserPasskey{} preloaded with :user, or nil
register_passkey(user, attrs)            # {:ok, passkey} | {:error, changeset}
update_passkey_label(passkey, label)     # {:ok, passkey} | {:error, changeset}
delete_passkey(user, passkey_id)         # {:ok, passkey} | {:error, :not_found | :unauthorized}
update_passkey_sign_count(passkey, count, last_used_at)  # internal, called after auth
```

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
   - Retrieves and clears challenge from session
   - Calls `Wax.register(attestation_object, client_data_json, challenge)`
   - Extracts `credential_id`, `public_key`, `sign_count` from result
   - Detects label from AAGUID metadata; falls back to `"Passkey (added #{Date.utc_today()})"`
   - Calls `Accounts.register_passkey(user, attrs)`
   - On success: JSON `{ok: true}` — JS redirects to settings
   - On failure: JSON `{error: "..."}` — JS shows inline message

### Authentication (user not logged in)

1. `GET /users/passkeys/challenge/authenticate`
   - No auth required
   - Calls `Wax.new_authentication_challenge([allow_credentials: [], origin: origin()])`
   - Empty `allow_credentials` triggers discoverable credential flow (OS account picker)
   - Stores challenge in session under `:wax_authentication_challenge`
   - Returns JSON: `{challenge}`

2. Browser JS calls `navigator.credentials.get({publicKey: {challenge, allowCredentials: [], userVerification: "preferred"}})` — OS presents account picker

3. `POST /users/passkeys/authenticate`
   - No auth required
   - Retrieves and clears challenge from session
   - Decodes `credential_id` from request
   - Calls `Accounts.get_passkey_by_credential_id(credential_id)` to find passkey + user
   - Calls `Wax.authenticate(credential_id, auth_data, sig, client_data_json, challenge, [{public_key: passkey.public_key, sign_count: passkey.sign_count}])`
   - Updates `sign_count` and `last_used_at`
   - Calls `UserAuth.log_in_user(conn, user)` — same as existing auth paths
   - On failure: JSON `{error: "..."}` — JS shows error and resets button

### Challenge Storage

Challenges stored in the Plug session:
- `:wax_registration_challenge` — cleared on use (success or failure) during registration
- `:wax_authentication_challenge` — cleared on use during authentication

---

## New Routes

```elixir
# Authenticated — passkey management
scope "/", ScientiaCognitaWeb do
  pipe_through [:browser, :require_authenticated_user]

  get  "/users/passkeys/challenge/register",  UserPasskeyController, :registration_challenge
  post "/users/passkeys",                      UserPasskeyController, :register
  put  "/users/passkeys/:id",                  UserPasskeyController, :update_label
  delete "/users/passkeys/:id",                UserPasskeyController, :delete
end

# Unauthenticated — passkey login
scope "/", ScientiaCognitaWeb do
  pipe_through [:browser]

  get  "/users/passkeys/challenge/authenticate", UserPasskeyController, :authentication_challenge
  post "/users/passkeys/authenticate",            UserPasskeyController, :authenticate
end
```

---

## New Controller: `UserPasskeyController`

Actions:
- `registration_challenge/2` — generates + returns registration challenge JSON
- `register/2` — verifies attestation, saves passkey, returns JSON
- `authentication_challenge/2` — generates + returns authentication challenge JSON
- `authenticate/2` — verifies assertion, logs user in
- `update_label/2` — updates passkey label, returns JSON
- `delete/2` — deletes passkey (with ownership check), returns JSON

All management actions (`register`, `update_label`, `delete`) verify `passkey.user_id == current_scope.user.id`.

---

## JS Layer

**New file:** `assets/js/passkeys.js`

Two exported functions, wired up via event listeners in `app.js`:

### `registerPasskey()`
1. `fetch GET /users/passkeys/challenge/register` → challenge JSON
2. Base64url-decode challenge and user ID
3. `navigator.credentials.create({publicKey: {challenge, rp, user, pubKeyCredParams: [{type: "public-key", alg: -7}, {type: "public-key", alg: -257}], authenticatorSelection: {residentKey: "required", userVerification: "preferred"}, attestation: "none"}})`
4. Base64url-encode `id`, `rawId`, `response.clientDataJSON`, `response.attestationObject`
5. `fetch POST /users/passkeys` with JSON body
6. On `{ok: true}`: `window.location = "/users/settings"`
7. On error: show inline error message near button

### `authenticatePasskey()`
1. `fetch GET /users/passkeys/challenge/authenticate` → challenge JSON
2. `navigator.credentials.get({publicKey: {challenge, allowCredentials: [], userVerification: "preferred"}})`
3. Base64url-encode assertion fields
4. `fetch POST /users/passkeys/authenticate` → server redirects on success
5. On `NotAllowedError`: reset button silently (user cancelled)
6. On other error: show inline error near button

No external JS dependencies. Both functions handle `AbortError` and `NotAllowedError` from the browser gracefully.

---

## UI Changes

### Login page (`user_session_html/new.html.heex`)

Add a "Sign in with passkey" button at the **top** of the page, above the existing magic link and password forms, separated by `<div class="divider">or</div>` dividers.

Button: `btn btn-primary w-full` with a passkey/fingerprint SVG icon.

JS: on click, calls `authenticatePasskey()`, disables button during request, re-enables on error.

### Settings page (`user_settings_html/edit.html.heex`)

Add a new **Passkeys** section below the existing password section, separated by a `<div class="divider" />`.

Section contains:
- Serif heading "Passkeys" + subtitle text
- List of registered passkeys: icon (laptop or phone based on `authenticatorAttachment`) + label + "Last used X ago · Added Y" metadata + rename icon-button + delete icon-button
- "Add a passkey" outlined button

Rename: clicking the pencil icon opens an inline edit (input replaces the label text, save/cancel).
Delete: clicking trash icon POSTs `DELETE /users/passkeys/:id` with a `confirm()` dialog.

Empty state (no passkeys yet): show subtitle "No passkeys registered yet." with only the "Add a passkey" button.

### Post-signup banner

Shown in the public app layout (`root.html.heex`) when:
- User is authenticated (`@current_scope` present)
- User has no passkeys (`Accounts.list_passkeys(user) == []`)
- Session key `:passkey_banner_dismissed` is not set

Banner: `bg-sc-primary-pale border border-primary/20` styling, passkey icon, headline "Add a passkey for one-tap sign-in", body text, "Set up" outlined button linking to `/users/settings#passkeys`, dismiss `×` button.

Dismiss: `DELETE /users/passkeys/banner-dismiss` sets `:passkey_banner_dismissed` in session and redirects back. Does not persist to DB — reappears after logout/login if user still has no passkeys.

---

## App Config

Add to `config/config.exs`:

```elixir
config :scientia_cognita, :webauthn,
  origin: "http://localhost:4000",   # overridden per environment
  rp_id: "localhost",                # overridden per environment
  rp_name: "Scientia Cognita"
```

`config/prod.exs` overrides `origin` and `rp_id` with the production domain.

---

## Error Handling

| Scenario | Handling |
|----------|----------|
| User cancels OS prompt (`NotAllowedError`) | JS resets button silently — no error shown |
| `Wax.register/3` fails attestation | JSON `{error: "Could not verify passkey. Please try again."}` |
| Duplicate credential ID | DB unique constraint → JSON `{error: "This passkey is already registered."}` |
| `Accounts.get_passkey_by_credential_id` returns nil | JSON `{error: "No passkey found. Try another sign-in method."}` (no user enumeration) |
| `Wax.authenticate/5` fails signature check | JSON `{error: "Passkey verification failed."}` |
| `sign_count` regression (possible cloned authenticator) | `wax_` emits a warning; login still proceeds — log at `:warning` level |
| Delete: passkey belongs to another user | `{:error, :unauthorized}` → 403 JSON |

---

## Testing

- `Accounts` context: unit tests for all new functions with Ecto sandbox
- `UserPasskeyController`: controller tests using fixture passkeys (bypassing WebAuthn JS layer)
- Registration and authentication flows tested by injecting pre-computed WebAuthn fixtures (credential, challenge, public key) — standard pattern for `wax_` testing
- Banner: renders when no passkeys, does not render when passkeys exist or dismissed

---

## File Inventory

| File | Action |
|------|--------|
| `mix.exs` | Add `wax_` dependency |
| `config/config.exs` | Add webauthn config block |
| `config/prod.exs` | Add production origin/rp_id |
| `priv/repo/migrations/TIMESTAMP_create_user_passkeys.exs` | New migration |
| `lib/scientia_cognita/accounts/user_passkey.ex` | New schema |
| `lib/scientia_cognita/accounts.ex` | New context functions |
| `lib/scientia_cognita_web/controllers/user_passkey_controller.ex` | New controller |
| `lib/scientia_cognita_web/router.ex` | New routes |
| `lib/scientia_cognita_web/controllers/user_session_html/new.html.heex` | Add passkey button |
| `lib/scientia_cognita_web/controllers/user_settings_html/edit.html.heex` | Add passkeys section |
| `lib/scientia_cognita_web/layouts/root.html.heex` | Add passkey banner |
| `assets/js/passkeys.js` | New JS module |
| `assets/js/app.js` | Wire up passkeys.js event listeners |
| `test/scientia_cognita/accounts_test.exs` | New passkey context tests |
| `test/scientia_cognita_web/controllers/user_passkey_controller_test.exs` | New controller tests |
