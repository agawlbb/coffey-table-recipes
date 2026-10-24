# Changelog

Release dates and changes are reconstructed from annotated Git tags, commit history, and project release records. Versions before 1.0 are demonstration releases; 1.0 marks the first usable release. Android retains the existing signing identity; iOS delivery and signing are recorded for each release.

## 2.1.1 — 2026-10-23

Build 32; tag `v2.1.1`.

- Fit three compact meal tiles per phone row with tighter spacing and smaller pictures, preserving readable captions and responsive bounds.
- Show the planner's side-by-side recipe browser on portrait tablets, while retaining phone and child-mode behavior.
- Improve dish captions with word-boundary wrapping and short titles on one line where space allows.
- Use the same short 200 ms hold for browser and planned-meal dragging, allowing quick swipes to scroll without grabbing a dish.
## 2.1.0 — 2026-10-23

Build 31; tag `v2.1.0`.

- Add PIN-protected account child mode: viewing and favorites remain available while editing, AI generation, shopping/planner changes and cooking/timer controls are restricted. Administrators can request a reset applied on a new login.
- Identify child accounts in household people, place Child mode after Household & people, and move Manage restaurants directly below Shopping list departments with matching presentation.
- Warn about blank planned recipes during ingredient review, preserving other available ingredients and updating the warning with the selected dates.
- Open the planner with today at the top and refine the approved ivory date cards, bold headings, Today accent/shadow, rounded recipe pictures and centered captions.
- Read saved recipe views before their first paint, retaining local browsing during stalled background storage and respecting access removal.
- Add optional shared shopping-entry notes, with inline editing, offline persistence, revision-safe synchronization and compatibility with older clients.
- Identify password fields for platform autofill and honor household AI-image settings in local snapshots.
## 2.0.0 — 2026-10-23

Build 30; tag `v2.0.0`. Releases the accepted meal planner and local-first household data after 1.8.5.

- Add a shared dated meal planner with recipe variations, leftovers, restaurant outings, drag-to-move, and confirmed changes to past cooking history. Every new addition or move requires a date.
- Offer frequently paired recipes when adding a meal, preserve recipe identity/title history, and retain recipe covers across navigation, restart and synchronization.
- Review ingredients for all future planned meals or a chosen date range; combine compatible quantities and add selected ingredients to the household shopping list with duplicate checks.
- Manage a shared household restaurant list, retaining the selected restaurant name in saved outings.
- Download a complete household database before browsing and use persistent local recipes, categories, favorites, people, shopping and planner data, with background synchronization and a durable edit queue.
- Preserve pending edits and drafts through interruptions; make recipe-save retries safe against duplicate submissions and require explicit review for conflicts.
- Warn after one minute when a local change lacks server confirmation, including native device reminders when notification permission allows.
- Restore the last main section, improve cached recipe/public-link browsing and cooking quantities, and keep drag scrolling and navigation responsive.
- Update Android Kotlin build tooling and retain signed iOS export-compliance and native recipe-link verification.
## 1.8.5 — 2026-10-22

Build 29; tag `v1.8.5`. First three-platform release after delivered 1.8.3; 1.8.4 only validated deployment tooling.

- Recover quietly from server rate limits: honor Retry-After, pause additional requests during cooldown, and retry safe reads without repeatedly contacting the server.
- Preserve downloaded recipe batches during rate limiting and show Updates paused for shopping refreshes instead of incorrectly reporting Offline.
- Deliver the reconciled app source using the isolated, patched deployment certificate bundle and explicit publish workflow prepared in 1.8.4.
- Add rate-limit recovery regression coverage and retain existing native signing and encryption settings.
## 1.8.4 — 2026-10-21

Build 28; tag `v1.8.4`.

- Use an isolated, patched certificate bundle for authenticated web deployment and verify the affected emSign G3 roots are absent.
- Allow the manual web workflow to validate its deployment client without contacting hosting; publishing requires the explicit publish input.

## 1.8.3 — 2026-10-18

Build 27; tag `v1.8.3`.

- Edit shopping item names inline with a double tap.
- Keep department drop targets ordered and correct shopping-list drag scrolling.
- Keep importer questions above their answer fields and label the next action Continue.
- Recover from brief server failures without discarding recipe work; retry safe reads and preserve pending edits and cached recipes.
## 1.8.2 — 2026-10-18

Build 26; tag `v1.8.2`.

- Add a bottom-sheet ingredient selector for adding recipe ingredients to the household shopping list.
- Separate shopping ingredient names from quantities and warn about similar existing items.
- Reveal empty department drop targets during stationary holds and keep held shopping items anchored.
- Retry transient shopping failures quietly and show clearer save notices; remove the redundant household heading.
- Warn about duplicate recipe names during import and save.
- Simplify cooking-mode screen-awake behavior and timer text.
- Reuse the encrypted Apple signing identity introduced during 1.8.1 recovery.
## 1.8.1 — 2026-10-18

Build 25; tag `v1.8.1`.

- Toggle shopping items by tapping the row, while retaining hold/drag behavior without accidental check-offs.
- Group checked items below active departments, preserving their departments so unchecking restores their placement.
- Make shopping department headings larger and bold, indent assigned active items, and adapt heading height to text scaling.
- Update shopping cache/drag regression coverage and document native Home Assistant/Google Keep synchronization.

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
