# Changelog

Release dates and changes are reconstructed from annotated Git tags, commit history, and project release records. Versions before 1.0 are demonstration releases; 1.0 marks the first usable release. Android retains the existing signing identity; iOS packages are unsigned for user-managed signing.

## 1.0.0 — 2026-10-11

Build 7; tag `v1.0.0`. First usable release.

- Added AI-assisted recipe import from pasted text, dish descriptions, website links, PDF/image/text uploads, and camera photos.
- Added clarification questions and editable review before saving, including quantity conflict warnings and cooking-action previews.
- Added incoming Android/iOS shares that open recipe import for review, including files, links, and text.
- Improved ingredient review, editor layout, category-parent display, and cancellation/navigation behavior.
- Added optional AI imagery for recipes without photos and category artwork; separated import warnings from saved cooking notes and made source labels readable.

## 0.5.0 — 2026-10-11

Build 6; tag `v0.5.0`.

- Added a complete recipe editor for ingredients, ordered steps and cooking actions, photos, categories, tags, notes, sources, pairings, and nutrition.
- Added device photo selection and camera capture, draft protection, conflict handling, and offline-cache updates after saving.
- Added recipe sharing beside the edit button, using public database-ID links with native sharing and copy-link fallback.
- Made full recipe-text downloads resumable, with persistent progress, retries, and verified offline-readiness reporting.

## 0.4.0 — 2026-10-11

Build 5; tag `v0.4.0`.

- Added an offline mobile recipe library, offline browsing/search/cooking, and recent-photo caching.
- Improved browsing with distinct category cards followed by scoped recipes.
- Switched verification email delivery to the authenticated hosted backend.
- Added registration and administration of Firebase-only accounts.

## 0.3.0 — 2026-10-10

Build 4; tag `v0.3.0`.

- Added a dedicated email-verification screen, explicit resend, and refreshed verification claims before household invitation loading.
- Improved administration to delete accounts and unlinked table people.
- Corrected verification delivery fallback and signup feedback.

## 0.2.0 — 2026-10-10

Build 3; tag `v0.2.0`.

- Added household invitation dialogs and invitation responses after login.
- Added retry handling and duplicate invitation-submission protection.

## 0.1.0 iOS follow-up — 2026-10-09

Build 2; tag `v0.1.0-ios.2`. Web and Android remained on initial build 1.

- Added the iOS Firebase client configuration and Google sign-in callback setup to the unsigned iOS build workflow.

## 0.1.0 — 2026-10-09

Build 1; tag `v0.1.0`.

- Initial demonstration with household authentication, recipe categories and browsing, recipe details, cooking mode, and navigation breadcrumbs.
- Published the app against the hosted coffeybean.com backend.
