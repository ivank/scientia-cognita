// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/scientia_cognita"
import topbar from "../vendor/topbar"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#4d86b8"}, shadowColor: "rgba(0, 0, 0, .2)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// Passkey support
import { registerPasskey, authenticateWithPasskey, dismissBanner } from "./passkeys";

// Banner dismiss
const bannerDismissBtn = document.getElementById("passkey-banner-dismiss");
const banner = document.getElementById("passkey-banner");
if (bannerDismissBtn && banner) {
  bannerDismissBtn.addEventListener("click", () => dismissBanner(banner));
}

// Expose to inline handlers in templates
window.PasskeyAuth = { registerPasskey, authenticateWithPasskey };

// Login page: Sign in with passkey button
const passkeyLoginBtn = document.getElementById('passkey-login-btn');
const passkeyLoginError = document.getElementById('passkey-login-error');
if (passkeyLoginBtn && passkeyLoginError) {
  passkeyLoginBtn.addEventListener('click', async () => {
    passkeyLoginBtn.disabled = true;
    passkeyLoginError.textContent = '';
    try {
      const data = await authenticateWithPasskey();
      window.location = data.redirect || '/';
    } catch (err) {
      if (err && err.name !== 'NotAllowedError') {
        passkeyLoginError.textContent = err.message || 'Passkey sign-in failed.';
      }
      passkeyLoginBtn.disabled = false;
    }
  });
}

// Settings page: Add a passkey button
const passkeyRegisterBtn = document.getElementById('passkey-register-btn');
const passkeyRegisterError = document.getElementById('passkey-register-error');
if (passkeyRegisterBtn && passkeyRegisterError) {
  passkeyRegisterBtn.addEventListener('click', async () => {
    passkeyRegisterBtn.disabled = true;
    passkeyRegisterError.textContent = '';
    try {
      await registerPasskey();
      window.location = '/users/settings';
    } catch (err) {
      passkeyRegisterError.textContent = err.message || 'Could not register passkey.';
      passkeyRegisterBtn.disabled = false;
    }
  });
}

// Passkey management helpers
async function updatePasskeyLabel(passkeyId, label) {
  const csrfTok = document.querySelector('meta[name=csrf-token]')?.content ?? '';
  const res = await fetch(`/users/passkeys/${passkeyId}`, {
    method: 'PATCH',
    headers: { 'content-type': 'application/json', 'x-csrf-token': csrfTok },
    body: JSON.stringify({ label }),
  });
  return res.json();
}

window.passkeyDelete = async function(passkeyId, rowEl) {
  if (!confirm('Remove this passkey?')) return;
  const csrfTok = document.querySelector('meta[name=csrf-token]')?.content ?? '';
  const res = await fetch(`/users/passkeys/${passkeyId}`, {
    method: 'DELETE',
    headers: { 'x-csrf-token': csrfTok },
  });
  if (res.ok) rowEl?.remove();
};

window.passkeyStartRename = function(passkeyId) {
  const labelEl = document.getElementById(`passkey-label-${passkeyId}`);
  if (!labelEl) return;
  const current = labelEl.textContent.trim();
  const input = document.createElement('input');
  input.type = 'text';
  input.value = current;
  input.className = 'input input-xs input-bordered w-40';
  const saveBtn = document.createElement('button');
  saveBtn.textContent = 'Save';
  saveBtn.className = 'btn btn-xs btn-primary ml-1';
  const cancelBtn = document.createElement('button');
  cancelBtn.textContent = 'Cancel';
  cancelBtn.className = 'btn btn-xs btn-ghost ml-1';

  cancelBtn.onclick = () => {
    labelEl.textContent = current;
    labelEl.style.display = '';
    [input, saveBtn, cancelBtn].forEach(el => el.remove());
  };

  saveBtn.onclick = async () => {
    const result = await updatePasskeyLabel(passkeyId, input.value.trim());
    if (result.ok) {
      labelEl.textContent = result.label;
    }
    labelEl.style.display = '';
    [input, saveBtn, cancelBtn].forEach(el => el.remove());
  };

  labelEl.style.display = 'none';
  labelEl.after(input, saveBtn, cancelBtn);
  input.focus();
  input.select();
};

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

