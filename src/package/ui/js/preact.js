// preact.js - single import point for the vendored Preact + htm bundle.
//
// Everything else imports from here, so the vendored file name and version can
// change without touching every component. The bundle is htm/preact/standalone:
// Preact, its hooks and htm's tagged-template renderer in one ES module, which
// is what lets this UI run with no build step at all.
export * from "../vendor/preact-standalone.module.js";
