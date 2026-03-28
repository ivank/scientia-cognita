// WebAuthn passkey helpers
// All binary data is base64url-encoded (no padding) for JSON transport.

function b64urlEncode(buffer) {
  const bytes = new Uint8Array(buffer);
  let str = "";
  for (const b of bytes) str += String.fromCharCode(b);
  return btoa(str).replace(/\+/g, "-").replace(/\//g, "_").replace(/=/g, "");
}

function b64urlDecode(str) {
  str = str.replace(/-/g, "+").replace(/_/g, "/");
  while (str.length % 4) str += "=";
  const bin = atob(str);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return bytes.buffer;
}

function csrfToken() {
  return document.querySelector("meta[name=csrf-token]")?.content ?? "";
}

export async function registerPasskey() {
  // 1. Get registration challenge from server
  const challengeRes = await fetch("/users/passkeys/challenge/register");
  if (!challengeRes.ok) throw new Error("Could not get registration challenge.");
  const { challenge, user_id, user_name, rp_id, rp_name } = await challengeRes.json();

  // 2. Create credential via WebAuthn API
  const credential = await navigator.credentials.create({
    publicKey: {
      challenge: b64urlDecode(challenge),
      rp: { id: rp_id, name: rp_name },
      user: {
        id: b64urlDecode(user_id),
        name: user_name,
        displayName: user_name,
      },
      pubKeyCredParams: [
        { type: "public-key", alg: -7 },   // ES256
        { type: "public-key", alg: -257 },  // RS256
      ],
      authenticatorSelection: {
        residentKey: "required",
        userVerification: "preferred",
      },
      attestation: "none",
    },
  });

  // 3. Send attestation to server
  const res = await fetch("/users/passkeys", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-csrf-token": csrfToken(),
    },
    body: JSON.stringify({
      response: {
        attestationObject: b64urlEncode(credential.response.attestationObject),
        clientDataJSON: b64urlEncode(credential.response.clientDataJSON),
      },
      authenticatorAttachment: credential.authenticatorAttachment ?? null,
    }),
  });

  const data = await res.json();
  if (!data.ok) throw new Error(data.error ?? "Registration failed.");
  return data;
}

export async function authenticateWithPasskey() {
  // 1. Get authentication challenge from server
  const challengeRes = await fetch("/users/passkeys/challenge/authenticate");
  if (!challengeRes.ok) throw new Error("Could not get authentication challenge.");
  const { challenge } = await challengeRes.json();

  // 2. Get assertion via WebAuthn API (discoverable credential — no allowCredentials)
  const assertion = await navigator.credentials.get({
    publicKey: {
      challenge: b64urlDecode(challenge),
      userVerification: "preferred",
      allowCredentials: [],
    },
  });

  // 3. Send assertion to server
  const res = await fetch("/users/passkeys/authenticate", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-csrf-token": csrfToken(),
    },
    body: JSON.stringify({
      rawId: b64urlEncode(assertion.rawId),
      response: {
        authenticatorData: b64urlEncode(assertion.response.authenticatorData),
        clientDataJSON: b64urlEncode(assertion.response.clientDataJSON),
        signature: b64urlEncode(assertion.response.signature),
      },
    }),
  });

  const data = await res.json();
  if (!data.ok) throw new Error(data.error ?? "Authentication failed.");
  return data; // contains { ok: true, redirect: "/path" }
}

export function dismissBanner(banner) {
  fetch("/users/passkeys/banner-dismiss", {
    method: "DELETE",
    headers: { "x-csrf-token": csrfToken() },
  }).then(() => banner.remove());
}
