# Changelog

Release dates and changes are reconstructed from annotated Git tags, commit history, and project release records. Versions before 1.0 are demonstration releases; 1.0 marks the first usable release. Android retains the existing signing identity; iOS delivery and signing are recorded for each release.

## 2.10.2 — 2026-11-12

Build 76; tag `v2.10.2`. iOS and Android release.

- Restore visible dish names beneath recipe photos in the meal planner.

## 2.10.1 — 2026-11-10

Build 74; tag `v2.10.1`. iOS and Android release.

- Fix calendar color saves using the wrong endpoint, which caused a Saved on this device / Endpoint not found notice after foregrounding.
- Deliver existing pending color changes through the shared app connection without clearing locally saved changes.
- Keep calendar read errors from blocking the server's required app snapshot or disconnecting the shared connection. Calendar bars temporarily disappear while calendar data is unreadable and return after recovery.

## 2.10.0 — 2026-11-10

Build 73; tag `v2.10.0`. iOS and Android release.

- Show a color bar beside meal-planner dates covered by any event on the selected Home Assistant work calendar, including dates without planned meals.
- Add a household Workday color setting and retain calendar markers and color offline.
- Update workday markers automatically when the linked calendar changes, with a periodic refresh fallback.
- Keep past, today and future date labels on one line on phones while retaining compact planner actions.

## 2.9.1 — 2026-11-09

Build 71; tag `v2.9.1`. iOS and Android release.

- Rename meal-planner actions to Timeline and Add dish, with compact outlined buttons at the date tile's top right.
- Remove recipe-picture captions from the meal planner.
- Combine identical planner shopping ingredients regardless of capitalization and split names joined by conjunctions or symbols. Sum compatible amounts and retain distinct amounts in one row.
- Group Error log and Dinner time under This device in Settings.
- Show full recipe titles and move Edit, Share, Request variation and Delete into the overflow menu.
- Place favorite beside the recipe title and a compact Variations selector below it; keep cooking and meal-planning actions together below the photo.
- Align the shorter Add to list action beside Ingredients.

## 2.9.0 — 2026-11-07

Build 69; tag `v2.9.0`. iOS and Android release.

- Plan combined cooking from the meal planner with a dinner time, overlapping recipe steps and explicit preparation.
- Start with low reasoning and offer More reasoning to replan on medium. Save reusable plans and shift dinner time without another AI call.
- Provide cooking feedback with current progress and remember personal cooking context for the feedback author.
- Offer device start alarms, show their scheduled time and confirm before clearing sessions.
- Keep AI requests, token renewal and native alarm updates from holding up unrelated communication on the shared connection.
- Keep the cooking screen focused on steps, with clear side-by-side actions and feedback controls above Android navigation and the keyboard.
- Center and emphasize Today while keeping meal-planner actions together on phones.

## 2.8.1 — 2026-11-06

Build 64; tag `v2.8.1`. iOS and Android release.

- Warn before meal-plan changes when offline. Continue offline suppresses repeat warnings until a healthy reconnection or app relaunch.
- Add Clear log beside Copy to clipboard in the error log.
- Remove log entries older than 24 hours and clear the log once on the first launch of a new app version.
- Includes the SQLite local working data and independent live synchronization introduced in 2.8.0, now released on Android as well.

## 2.8.0 — 2026-11-06

Build 63; tag `v2.8.0`. iOS release; Android deferred. Main integration remains pending approval.

- Store local working data and unsent changes in SQLite, importing existing local data without clearing it.
- Show meal-plan moves and other ordinary edits immediately, online or offline, without waiting for server acknowledgement.
- Automatically send new offline recipes; ask whether to save or discard existing recipe edits and meal-plan changes after reconnecting.
- Keep shopping removals for up to two hours across restart, and preserve unrelated server items when sending item changes.
- Keep unrelated incoming and outgoing synchronization running while a decision or another save is pending or fails.
- Keep a healthy connection open when an individual request times out; retain existing shared-edit and past-meal confirmations.

## 2.7.7 — 2026-11-06

Build 62; tag `v2.7.7`. iOS is staged for approval through TestFlight. Android release and main integration remain pending approval.

- Apply last-update-wins saves without edit-version conflicts or a general synchronization hold.
- Warn before recipe editing, adding, or shopping when disconnected.
- Retain shopping item removals for up to two hours; automatically upload new recipes when reconnected.
- Offer Save to server or Discard my changes for offline recipe edits without blocking incoming synchronization.
- Keep pushed server state current and record only actual errors in the copyable error log.

## 2.7.6 — 2026-11-05

Build 61; tag `v2.7.6`.

- Clear recipe caches and pending local edits once after updating, then reload server data; retain sign-in and device preferences.
- Use one shared foreground server connection for account, recipes, meal plans, shopping, cooking and timers, with server-pushed changes and direct saves.
- Remove the local/server comparison screen and routine synchronization polling. Green indicates an open server connection.
- Renew authentication on the existing connection and serialize account commands to avoid competing startup requests.

## 2.7.5 — 2026-11-05

Build 60; tag `v2.7.5`.

- Preserve initial and reconnected snapshot confirmation so synchronization can finish and become green without depending on a redundant download.
- Retry failed startup storage reads instead of caching the failure indefinitely.
- Recover safely retryable interrupted saves after restarting, including old interruption holds; preserve real conflicts and uncertain saves without receipt IDs.
- Add a persistent device-local error log under Settings, with Copy to clipboard. Record synchronization state and safe error codes without tokens, recipe contents or private exception messages.

## 2.7.4 — 2026-11-05

Build 59; tag `v2.7.4`.

- Repair shared-recipe loading when the server sends an empty public synchronization handshake.
- Recover automatically from malformed responses, timed-out connections and temporary recipe-loading failures.
- Preserve saves through token refresh, brief system dialogs and interrupted acknowledgments; retain real conflicts for review.
- Require persisted server snapshots and no known pending work before showing green synchronization status. The indicator means “Matches last confirmed server data.”
- Prevent concurrent cache writes and delayed reads from corrupting or restoring stale local data, including remotely deleted recipes.
- Synchronize household/account display metadata and add real Dart/PHP protocol and fault-recovery regression coverage.

## 2.7.3 — 2026-11-05

Build 58; tag `v2.7.3`.

- Resolve synced recipe IDs in new and already queued meal-plan edits so temporary device IDs cannot leave uploads stuck.
- Show pending or failed saves in the sync indicator and expose the existing retry/review status instead of showing a misleading green cloud.
- Repair sharing from retained recipe screens and remove the HTML-copy option; Share recipe opens normal device sharing directly.
- Add device notification categories and first-launch permission handling.
- Complete InMotion web-hosting retirement. Android and iOS releases continue using the VPS backend; invitation and verification flows no longer point to the retired website.

## 2.7.2 — 2026-11-03

Build 57; tag `v2.7.2`.

- Keep temporary cooking connection failures out of startup notifications and cooking-action messages; retain existing connection indicators and actionable validation/alarm errors.
- Refresh cooking sessions even when registering the device for push delivery fails.
- The underlying repeated device disconnect has not been reproduced; this release does not claim to resolve its cause.

## 2.7.1 — 2026-11-03

Build 56; tag `v2.7.1`.

- Return to the recipe browser when the displayed cooking session ends locally, remotely or through expiry, removing the ended screen and its overlays.
- Keep the recipe title and screen-awake control above the cooking progress line while steps scroll below; show the existing connection icon on recipe and cooking screens.
- Close the timer sheet after Stop succeeds, including when other timers remain.
- Delete shopping-item photos from the photo viewer while preserving the shopping item and syncing the change.
- End cooking sessions by swiping their menu entries, with confirmation for partial progress or timers and a timer-cancellation warning. Allow accessible sessions to be ended without joining that device.

## 2.7.0 — 2026-11-03

Build 54; tag `v2.7.0`.

- Start shared cooking sessions, open or join them from the bottom of the navigation menu, and switch between dishes while steps and timers remain synchronized.
- Invite household members directly by holding a session and choosing a person under **Share with**. Keep sessions available until explicitly ended or expired after inactivity, with running timers protected.
- Preserve timer ranges in recipe imports, chat, variations and editing. Start at the minimum and offer the remaining time once, with shared revisions preventing duplicate extensions.
- Add **Stop** and **Add remaining time** actions to expired Android and iOS timers. Clear stopped timers from cooking mode, retain background actions for reconciliation, and synchronize them through the server.
- Optimize large recipe images in a separate backend worker while preserving originals and keeping shopping and recipe connections responsive.

## 2.6.0 — 2026-11-01

Build 52; tag `v2.6.0`.

- Keep an evolving **Draft recipe** beside conversational AI chat. Apply discussed changes immediately, evaluate the whole recipe for both direct and “what if” requests, and explain the cooking effects using relevant remembered preferences.
- Save the agreed draft directly into the recipe viewer without an editor/review step or another AI cooking request. Choose variation versus edit when saving; variations copy the original picture. Preserve shared-edit confirmation and safe save retries.
- Remember each user's cooking preferences and household-scoped family preferences in the VPS database, with corrections and requests to forget carried into future chats.
- Improve phone and iPad chat input with keyboard Send/Enter, Shift+Enter for new lines, and clearance for software keyboards and Bluetooth suggestion bars.
- Attach, replace, remove and view household-shared pictures on shopping items, with private uploads, image normalization, and preservation across queued edits and older clients.
- Simplify household settings navigation and use **Full name** consistently.
- Keep backend hosting and the persistent recipe database on the VPS; publish the web app on InMotion. No InMotion PHP/backend deployment.

## 2.5.0 — 2026-10-31

Build 47; tag `v2.5.0`.

- Add **Create a dish with AI** for every household, with a messaging-style conversation for developing recipes, asking for improvements, and exploring how proposed changes affect cooking results. Keep hypothetical discussion separate from agreed changes; review and Save remain explicit.
- Use the same conversational flow for **Request variation**, with a clear choice between a new linked variation and editing the existing recipe. Preserve variation title/language conventions, approved cover reuse, review explanations, and existing shared-edit and revision safeguards.
- Move signup, household setup, verification email, invitations, SQL-backed child-mode policy and account administration to the VPS. Preserve account data and pending offline edits, and improve verification resend/reconnection handling.
- Serve generated recipe links, public recipe pages, native app associations and owned recipe media from `ctr.coffeybean.com`. Resolve cached legacy photos and named illustrations through the VPS while retaining external image URLs.
- Protect shared shopping edits when incoming changes alter the displayed list; keep newly checked items in place briefly before grouping them. Show main dishes first within each meal-planner date.
- Fix Android release startup for timer preferences and verify the Kotlin JNI classes in signed APKs.
- Keep the InMotion PHP endpoint-retirement deployment suppressed for this release. Persistent MySQL and SMTP remain on InMotion; the app uses the deployed VPS services.

## 2.4.0 — 2026-10-31

Build 40; tag `v2.4.0`.

- Move recipe imports, clarification answers, variations, recipe images, category artwork and parent-category administration to authenticated VPS WebSockets. Keep signup and account administration on inMotion.
- Show the current AI stage and elapsed seconds beside existing actions, keeping shopping, timers and heartbeats responsive during provider work. Preserve entered answers and existing review/save behavior.
- Keep the AI connection alive through long runs and clarification, with bounded cancellation and reconnect behavior; mobile background connectivity still depends on the operating system.
- Distribute signed Android releases to the existing Google Drive recipe app folder, verifying downloaded bytes before sending an informational release notice and trashing older authorized APKs.
- Remove VPS APK metadata/download checks and the in-app update window. Android release notices have no download link or click action; recipients use their shared Drive folder.
## 2.3.0 — 2026-10-29

Build 39; tag `v2.3.0`.

- Synchronize recipes, favorites, household data and meal plans through the authenticated VPS WebSocket connection while preserving local data, durable pending edits and required meal dates.
- Show the existing green connection icon throughout the household app only after shopping and library snapshots are saved; remove obsolete manual data-sync/status controls.
- Synchronize account-private timers through VPS snapshots with reconnect and account-switch guards. Keep the SQL database, account provisioning, invitations and AI access on inMotion; retain existing photo URLs and store new uploads on the VPS.
- Add Android release notifications and a dismissible update window on launch/resume with the trusted VPS APK link. Installation remains manual through Android; existing 2.2.1 clients need this first update installed manually.
- Build Android releases on a standard GitHub runner, retain the original signing identity, and verify public versioned/latest downloads before release notification and cleanup.
## 2.2.1 — 2026-10-28

Build 38; tag `v2.2.1`.

- Reconnect shopping synchronization immediately when networking returns and limit retry delays to five seconds.
- Prevent interrupted connection attempts and stale snapshots from blocking or marking a newer connection ready. Preserve pending shopping edits during recovery.
- Distribute Android APKs from the stable VPS HTTPS download instead of Google Drive, with verified replacement downloads and automatic removal of older hosted release APKs. The in-app update link remains deferred.

## 2.2.0 — 2026-10-28

Build 37; tag `v2.2.0`.

- Move shopping synchronization to the persistent VPS WebSocket service, with authenticated live updates, reconnects and safe replay of durable local edits.
- Preserve pending changes when receiving snapshots and acknowledgements, and allow shopping uploads independently of recipe HTTP availability.
- Show the small green connection icon when shopping synchronization is ready. Remove the unwanted manual shopping sync controls and overdue shopping notice; other temporary notices can be dismissed and expire after eight seconds.
- Keep child-mode editing controls hidden in the app. Account, recipe and meal-planning operations continue through inMotion; the HA integration uses the same VPS shopping service.

## 2.1.5 — 2026-10-27

Build 36; tag `v2.1.5`.

- Recover uncertain recipe-variation responses and busy requests with bounded retries using the same request identity and answers, without duplicating generation.
- Preserve entered text and show specific timeout, network and malformed-response messages; stop recovery when leaving the preparation screen or going offline. Explicit provider failures are not automatically regenerated.
- Pair with the compatible server's nonblocking request locks, completed-draft recovery and sanitized timeout diagnostics. No screens or controls were added, and saved recipe data is unchanged.
## 2.1.4 — 2026-10-25

Build 35; tag `v2.1.4`.

- Remove the unrequested Saved local drafts history button/dialog and archive-only Local drafts retained banner.
- Preserve internally retained edits, pending shopping uploads, sync error reporting and existing conflict resolution. Retained drafts alone no longer display a sync row; no stored data is deleted or replayed.
## 2.1.3 — 2026-10-24

Build 34; tag `v2.1.3`.

- Save shopping changes durably before hiding deleted items, and retain visible items when device storage fails.
- Retry interrupted shopping uploads safely across restarts with stable operation identities, original edit times and explicit server acknowledgements.
- Merge pending changes into incoming shopping snapshots without losing unrelated items or resurrecting pending deletions; remove stale secondary-cache reads in local-first mode.
- Show unconfirmed uploads and current errors in the shared sync banner, with recovery after a valid account refresh.
- Pair with the deployed compatible server's duplicate-request receipts, per-field ordering and deletion tombstones. Preserve manually corrected shopping data; no historical replay or data reset is performed.
## 2.1.2 — 2026-10-24

Build 33; tag `v2.1.2`.

- Preserve downloaded household data and pending edits when a request fails because an action is denied, a token expires, or an unstructured server/proxy error occurs; authoritative membership/account removal remains enforced.
- Validate membership responses before revoking access, and repair legacy local household blocks after a successful membership refresh so missing records can be downloaded again.
- Preserve archived drafts for review rather than automatically replaying them, and protect against late cross-household responses.
- Build all platforms with patched Flutter 3.47.8/Dart 3.13.7 and enforce those minimum SDK versions. Existing 2.1.1 packages are superseded by this rebuild.
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
