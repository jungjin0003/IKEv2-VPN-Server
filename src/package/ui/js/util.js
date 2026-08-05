// util.js - small shared helpers.

// HTML-escape a value that will be interpolated into an i18n string which is
// itself rendered as markup (a few notices carry <b>/<code> tags).
export function esc(s) {
    s = String(s == null ? "" : s);
    const d = document.createElement("div");
    d.textContent = s;
    return d.innerHTML;
}

// Preact does not re-render an <input> the user is typing in unless we ask it
// to, and the 15s status poll must not overwrite a field mid-edit. Mirrors the
// original guard: skip repopulating forms while a field has focus.
export function isEditing() {
    const el = document.activeElement;
    return !!el && (el.tagName === "INPUT" || el.tagName === "SELECT");
}
