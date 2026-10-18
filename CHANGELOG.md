# Changelog

Release dates and changes are reconstructed from annotated Git tags, commit history, and project release records. Versions before 1.0 are demonstration releases; 1.0 marks the first usable release. Android retains the existing signing identity; iOS delivery and signing are recorded for each release.

## 1.8.0 — 2026-10-18

Build 24; tag `v1.8.0`. Build 23 was an Android timer-sync test package.

- Added a shared household shopping list with item check-offs, draggable department grouping, configurable departments and a compact add row.
- Remember household department choices for later additions, including tolerant item-name matching and preservation of pending moves.
- Cache confirmed shopping lists by account and household; refresh visible lists every five seconds and show connection loss without hiding cached items.
- Request external shopping-list synchronization when the shopping view opens, using the hosted household integration API.
- Mirror cooking timers between signed-in mobile devices with opt-in reception, account-scoped recovery, original deadlines and native push handling. Background push delivery remains subject to OS restrictions.
- Keep shared navigation available in recipe, cooking and shopping views; place recipe titles in the persistent app bar and clarify timer and variation controls.
- Verify production iOS push permissions and hosted universal-link identity in the exported signed IPA before TestFlight upload.

## 1.7.0 — 2026-10-17

Build 22; tag `v1.7.0`.

- Added private household favorites, including long-press selection of household members and combined favorite filters.
- Added blank recipes with name, categories, photos and favorites; import text, websites, files or camera captures into the same saved recipe while retaining its identity.
- Added blank-only browsing and a unified filter panel with independent removable filters, retry behavior and clearer responsive layouts.
- Added review of alternative website cooking methods, with a choice of one method or separately reviewed linked recipe variations.
- Added long-press ingredient reordering, direct ingredient deletion and stronger ingredient-group and description presentation.
- Refined blank-recipe details, picture editing, favorite placement and cooking-timer presentation.
- Fixed narrow-screen overflow in the recipe variation menu after adding favorite controls.
- Included verified Android and iOS domain-root associations for shared recipe links and documented release verification.

## 1.6.1 — 2026-10-16

Build 21; tag `v1.6.1`. Completes the three-platform shared-recipes/native-timers release.

- Added the timer widget's required App Store display name after Apple rejected the 1.6.0 iOS upload.
- Validate display names for the app and both extensions before upload and during signed-package verification.
- Rebuilt web and Android with the corrected version/build to keep all three platforms aligned; retains all 1.6.0 features.

## 1.6.0 — 2026-10-16

Build 20; tag `v1.6.0`. This follows development packages through build 19.

Web and Android were delivered; iOS compiled and signed but Apple rejected upload for a missing timer-widget display name. Superseded by 1.6.1.

- Added public shared-recipe browsing and authenticated attachment of a canonical recipe to another household, with confirmation before shared edits.
- Preserved canonical variation-family navigation across household lists and added native HTTPS recipe-link routing with web fallback.
- Added persistent native cooking timers, app-wide running-timer controls, cancellation and recovery, Android alarm-tone selection and one-second previews.
- Added iOS AlarmKit scheduling on supported systems, notification fallback, bundled tones and a Live Activity timer widget.
- Refined the account menu, recipe-title layout, responsive browsing and keyboard-overlay handling.
- Included the running app version in the menu and recipe-name HTML links when sharing.

## 1.5.0 — 2026-10-16

Build 16; tag `v1.5.0`.

- Search recipes as you type, using cached recipe and ingredient text first, with category scoping and protection against stale results.
- Display cached category text immediately and prefetch photos for variation families and linked recipes.
- Simplify recipe review and editing with grouped ingredients, focused editors, synchronized quantity fields, section shortcuts and clearer save feedback.
- Preserve imported category selections and improve informal recipe extraction, component membership, fractions and readable cooking instructions.
- Distinguish import connection failures, timeouts and incomplete responses while retaining input for retry.
- Add administrator management of shared parent categories with AI covers, previews and missing-cover retries; supporting backend changes were deployed separately.
- Refine recipe layout with centered titles, descriptions above metadata, actions on the left and Variations on the right.
- Allow requested iOS builds without a separate approval step; retain accurate export declarations and the France distribution exclusion.

## 1.4.0 — 2026-10-15

Build 15; tag `v1.4.0`.

- Added recipe variations: request changes, answer follow-up questions, review the adaptation and save a new recipe without changing the original.
- Grouped recipe families into one browsing entry with a Variations menu for switching between family members, including offline safeguards.
- Added temporary explanations of variation changes during review and reuse of an approved parent cover photo when suitable.
- Made recipe source website links clickable and gave recipe titles full width above the action row.
- Corrected cooking-temperature formatting and updated the Android Gradle wrapper with a verified distribution checksum.
- Included the exempt-encryption declaration in future iOS builds; retained the policy excluding France from iOS distribution.

## 1.3.1 — 2026-10-13

Build 14; tag `v1.3.1`. Build 13 was separately distributed for TestFlight as version 1.3.0.

- Split parent and child category selection into separate controls and sorted category choices alphabetically.
- Selected imported source photos by default while retaining review and deselection.
- Included pinned workflow actions, the Flutter 3.47.7 build update, and validated iOS archive/export tooling. This release builds signed iOS and uploads to App Store Connect for TestFlight.

## 1.3.0 — 2026-10-12

Build 12; tag `v1.3.0`.

- Added recipe deletion with immediate Undo and a Recently Deleted screen for recovery within 30 days.
- Kept offline caches synchronized with confirmed deletions and restores.
- Simplified recipe import and editing, with visible categorization and expanded editing sections.
- Sorted subcategories and recipes alphabetically and improved step numbering and category/tag placement in details.
- First three-platform release build from the public repository; standard public-repository macOS runner use is documented as free by GitHub, with separate approval still required for every iOS run.

## 1.2.0 — 2026-10-12

Build 11; tag `v1.2.0`. Web and Android release only; no iOS build was requested.

- Added local crop, rotate, horizontal flip, and resize tools to recipe photos before saving.
- Published the sanitized source under AGPL-3.0-or-later with licensing, attribution, security, and self-hosting guidance.
- Made iOS Actions builds manual-only with explicit approval required for each paid macOS run.
- Included the accumulated iOS sharing/signing source refinements; this release does not distribute a new iOS package.

## 1.1.1 — 2026-10-11

Build 9; tag `v1.1.1`. iOS-only patch; hosted web and Android remain on 1.1.0.

- Fixed iOS share-storage errors opening Add recipe on ordinary launches; errors now notify without navigating and repeated storage failures are deduplicated.
- Added iOS file-opening delivery through the app's own persistent inbox for PDFs, images and text, without requiring App Group storage. Signed-device validation is pending.

## 1.1.0 — 2026-10-11

Build 8; tag `v1.1.0`.

- Added source food-photo suggestions with crop review and typed category selection during import review.
- Repaired iOS sharing with a visible handoff result and persistent shared input for pickup when the app opens.
- Displayed and edited recipe durations in hours, minutes, and seconds.
- Simplified recipe tiles and removed redundant header and offline-count clutter.
- Corrected iOS extension build ordering introduced in 1.0.0.

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
