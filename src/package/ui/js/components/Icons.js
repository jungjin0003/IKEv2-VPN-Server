// Icons.js - the inline SVGs used across the UI.
//
// Kept in one place so a component reads as layout rather than as a wall of
// path data. Every icon is a plain function returning markup.

import { html } from "../preact.js";

export const IconLogo = () => html`
<svg width="24" height="24" viewBox="0 0 16 16" fill="none" stroke="#fff" stroke-width="1.3"><rect x="1.5" y="2.5" width="13" height="8.5" rx="1"></rect><path d="M5.5 14h5M8 11v3"></path><path d="M4.5 5.5l2 2-2 2M8 9.5h3.5" stroke-width="1.2"></path></svg>`;

export const IconRestart = () => html`
<svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.6"><path d="M13.5 8a5.5 5.5 0 1 1-1.6-3.9"></path><path d="M13.5 1.5v3.5H10"></path></svg>`;

export const IconOverview = () => html`
<svg width="18" height="18" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.4"><rect x="1.5" y="2" width="5.5" height="5.5" rx="1"></rect><rect x="9" y="2" width="5.5" height="5.5" rx="1"></rect><rect x="1.5" y="8.5" width="5.5" height="5.5" rx="1"></rect><rect x="9" y="8.5" width="5.5" height="5.5" rx="1"></rect></svg>`;

export const IconConnections = () => html`
<svg width="18" height="18" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.4"><path d="M5.5 1.5v3.5M10.5 1.5v3.5"></path><rect x="3.5" y="5" width="9" height="5.5" rx="1.5"></rect><path d="M8 10.5v4"></path></svg>`;

export const IconLog = () => html`
<svg width="18" height="18" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.4"><path d="M5.5 4h9M5.5 8h9M5.5 12h9"></path><path d="M2 4h.01M2 8h.01M2 12h.01" stroke-width="2.2" stroke-linecap="round"></path></svg>`;

export const IconGeneral = () => html`
<svg width="18" height="18" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.4"><circle cx="8" cy="8" r="2.4"></circle><path d="M8 1.5v2M8 12.5v2M1.5 8h2M12.5 8h2M3.4 3.4l1.4 1.4M11.2 11.2l1.4 1.4M12.6 3.4l-1.4 1.4M4.8 11.2l-1.4 1.4"></path></svg>`;

export const IconPrivilege = () => html`
<svg width="18" height="18" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.4"><circle cx="8" cy="5.5" r="2.5"></circle><path d="M2.5 14c.7-3 3-4.2 5.5-4.2s4.8 1.2 5.5 4.2"></path></svg>`;

export const IconServer = () => html`
<svg width="18" height="18" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.3"><rect x="2" y="2" width="12" height="4" rx="1"></rect><rect x="2" y="7.5" width="12" height="4" rx="1"></rect><circle cx="4.5" cy="4" r=".6" fill="currentColor" stroke="none"></circle><circle cx="4.5" cy="9.5" r=".6" fill="currentColor" stroke="none"></circle><path d="M11 4h1.5M11 9.5h1.5"></path></svg>`;

// overview table row icon - stroke colour follows the enabled state
export const IconServerRow = (stroke) => html`
<svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke=${stroke} stroke-width="1.2"><rect x="2" y="2" width="12" height="4.5" rx="1"></rect><rect x="2" y="8" width="12" height="4.5" rx="1"></rect></svg>`;

// larger variant for the server page heading
export const IconServerHead = () => html`
<svg width="20" height="20" viewBox="0 0 16 16" fill="none" stroke="var(--accent)" stroke-width="1.2"><rect x="2" y="2" width="12" height="4.5" rx="1"></rect><rect x="2" y="8" width="12" height="4.5" rx="1"></rect><circle cx="4.4" cy="4.25" r=".7" fill="var(--accent)" stroke="none"></circle><circle cx="4.4" cy="10.25" r=".7" fill="var(--accent)" stroke="none"></circle></svg>`;

export const IconChevron = () => html`
<svg width="12" height="12" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="2"><path d="M3.5 6l4.5 4.5L12.5 6"></path></svg>`;

export const IconSearch = () => html`
<svg width="14" height="14" viewBox="0 0 16 16" fill="none" stroke="#9aa2a8" stroke-width="1.6"><circle cx="7" cy="7" r="4.5"></circle><path d="M10.5 10.5L14 14"></path></svg>`;

// shown in the "no connections" empty state
export const IconNoConnections = () => html`
<svg width="36" height="36" viewBox="0 0 16 16" fill="none" stroke="#cfd6dc" stroke-width="1.2"><path d="M5.5 1.5v3.5M10.5 1.5v3.5"></path><rect x="3.5" y="5" width="9" height="5.5" rx="1.5"></rect><path d="M8 10.5v4"></path></svg>`;
