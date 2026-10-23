# Shopping list

Opening or returning to Shopping list now sends a household request to
synchronize with an external list. Home Assistant exposes it as Shopping list
synchronization (`requested`) and
`coffey_table_recipes_shopping_list_sync_requested`. The request is independent
of item changes; background polling and ordinary widget rebuilds do not send
one. Sending is best effort while online and does not block list use. When a
Google Keep Sync list is selected in CTR's Home Assistant settings, CTR handles
fresh Keep synchronization internally after receiving the request on its next
poll. Other external-list connections can still use the event in an automation.
The backend retains 128 requests; HA remembers its cursor across restarts and
does not replay pre-installation history. Source changes require an explicitly
authorized app build before the app can send these requests.

Validation: 11 focused shopping/synchronization/cache widget checks passed,
including one request per opening, reopening a retained view, no requests from
polling/rebuilds, and a failed synchronization request leaving list items usable.
Flutter analysis reported no issues. No app build was produced.

Open **Shopping list** from the hamburger menu for the selected household.
All household members share the same list. Items have a name and optional department;
a single tap toggles one strike-through. Items have no per-item checkbox or
tap-to-edit screen. Checked items appear together below all department groups. Click
and drag with a mouse, or hold a row on a touch screen, to reorder. **Remove checked off** stays at the bottom.

New items use the household's remembered department when their name matches a
previous assignment. Unrecognized items appear above all department headings.
The add form contains an item field and a compact plus button on its right,
including on narrow screens. The button retains an Add item accessibility label. Unassigned items
have no visible heading. Drag an assigned item to the top strip to remove its
department, or drop on a department heading to assign it. The named Other
department remains distinct from having no department.

Unchecked assigned items appear indented beneath larger bold department
headings in the household's configured order.
Occupied departments are displayed as compact headings, with no empty
placeholder or drop box. Empty departments are hidden until an item is held. Drag anywhere on the item label or row.
Drop on a department heading to move the item into that department, or on the
upper/lower half of another item to insert before/after it. The drop saves the
new department and position together. Headings are not draggable and retain
accessibility heading semantics. Dragging near the list edge scrolls the list.
Rows omit both the redundant department subtitle and trailing drag/menu icon.

Empty departments are always hidden during normal list use. A stationary long
press with a mouse, touch or stylus reveals all department headings before any
movement. Releasing or cancelling hides empty headings again; a department that
received an item stays visible. There is no visibility checkbox or preference.

The screen uses the app's existing theme. Its last confirmed local snapshot
appears while the server refresh is pending. It refreshes when opened or
resumed and polls every five seconds while visible. Changes require a connection
to coffeybean.com. Concurrent changes are
protected with server revisions: a stale save reloads the shared list and
shows a brief retry message. Unsaved add text survives failures.

The backend requires migration 015 and its shopping-list endpoint. Local web
builds are published only when authorized; the hosted Flutter app is unchanged.

Validation: shopping-list widget tests cover adding, checking, changing
departments, removing checked items, long-press drag-to-end ordering, and stale
write recovery that preserves typed input. Source analysis and the existing
298-test app suite passed. Backend sharing, ordering, validation and concurrency
checks passed, as did 107 deployment/migration checks. The backend and migration
were deployed successfully on 2026-10-18 (run 39129982170), with the published
receipt, health and unauthenticated-access boundary independently verified.

The add control is a prominent **Add item** button beside the item field on
wide screens and directly below it on phones. It remains enabled when empty
and focuses the field when pressed. A phone-keyboard widget check verifies
that the button remains visible and adds the typed item. The focused shopping
list suite passes all four checks after this usability refinement.

Web add regression (2026-10-18): the browser's compiled Add handler called
`Random.nextInt(0)` because `1 << 32` uses 32-bit shift semantics on JavaScript.
This threw before the save request and escaped the widget tests running on
the Dart VM. ID generation now uses the explicit numeric literal `0x100000000`.
Compile `tool/check_shopping_item_id.dart` with `dart compile js` and run its
output with Node (`globalThis.self = globalThis`) to verify 1,000 valid unique
IDs on the actual JavaScript target, alongside the four widget checks.

Local web build `32beca9` was republished and its served JavaScript/version
metadata matched the build. In the signed-in built-in browser, tapped **Add
item** to save Milk, fully reloaded the page, reopened Shopping list and
confirmed Milk remained. This exercised the actual hosted save and read paths.

Department drag validation: all five focused shopping-list widget checks pass,
including dropping an item into an empty department and saving its new
classification, within-department ordering that preserves other items, all ten
headings, and absence of trailing menu/drag icons. No backend schema change is
required; the existing item department and list order carry the result.

Item tap editing was removed entirely, including the dialog implementation.
A regression check taps an item and verifies that no edit dialog opens.
Local metadata inspection found the previously published build was 0349543,
which predates 9f21758 (all departments and cross-department dragging).
Those source changes require an explicitly authorized local web rebuild before
browser verification can exercise them.

Repeated-drag fix: a drop updates the visible order immediately, with writes
queued serially against the latest confirmed server revision. Rows remain
draggable while earlier saves are pending. Responses confirm their own queued
snapshot without replacing newer local moves; failed writes restore the last
confirmed list and discard remaining queued changes with an error. Background
polls no longer rebuild an unchanged list. Seven focused widget checks pass,
including consecutive moves across populated/empty sections with delayed saves
and a second complete drag while the first save is explicitly blocked.

Full-row drag validation: replaced the implicit ListTile hit area with an
opaque long-press drag surface and explicit heading/item drop targets. Mouse
and touch checks drag from both edges of a label and the row whitespace while
leaving the checkbox unchecked. Nine shopping-list tests pass, including compact
headings without empty rows, before/after ordering, successive queued drags,
conflict recovery and auto-scroll at the list edge. Source analysis is clean.

Drag lifecycle regression: a keyed row in the lazy list also needs an index
lookup when its department or position changes. Without it the row's drag
state was disposed after a move; the new regression test reproduced that state
loss. The list now maps stable row keys to their current indices. Accepted and
cancelled drags both clean up scrolling and drag flags, even if their original
row has left the viewport. Item cards consistently request the standard visible
mouse pointer, including their in-drag variants. The lifecycle test verifies
the same drag state survives three department moves and checks the exact
standard cursor after hovering each moved label. The edge-scroll test also
verifies scrolling stops after cancellation. The SDK-compatible `test` package
is a development-only dependency needed by Flutter's browser test runner.

Validation: all 307 app unit/widget tests passed, and source analysis was clean.
The lifecycle regression failed on the prior implementation (the original drag
state was defunct after the first move) and passes after the index mapping fix.
The browser runner compiled and launched headless Chrome, but stalled before
executing test bodies; it was stopped and is not counted as a passing web test.
This limitation is separate from the passing framework mouse-cursor assertions.

Mouse gesture regression: a normal click-and-drag in the affected Chrome tab
made no move because the source required a long press for every pointer type.
A no-delay mouse test reproduced that failure. Drag sources now filter their
pointer devices: immediate recognition for mouse and delayed recognition for
touch/stylus, so touch swipes remain available for scrolling. Both use the same
stable row identity, visible pointer, drop targets and save queue. Eleven
focused checks pass, including the new no-delay gesture, a short touch swipe
that does not move an item, and a normal mouse checkbox click.

Actual Chrome verification (2026-10-18): published local build 2337e09,
verified localhost asset hashes/source metadata, and reloaded the user's
affected tab. The same ordinary mouse drag that failed before rebuilding then
moved Milk from Bakery to Dairy, from Dairy to Produce, and from Produce back
to Bakery on three consecutive attempts, without a long-press pause. A full
reload and reopening Shopping list confirmed the restored original department
persisted. Browser console checks reported no warnings/errors during the moves.
The test item was returned to its starting department.

Unassigned-item validation: all twelve focused widget checks pass, including
adding without a picker, rendering new items above department headings,
assigning/unassigning by drag, and hiding/restoring empty headings without
changing existing assignments. The API accepts an explicit empty department
string, while invalid/missing departments remain rejected. No schema change is
required. The local web app needs an explicitly authorized rebuild for this
new feature; the previous mouse-drag build is unchanged.

Local web rebuild (2026-10-18): explicitly requested build completed for
app commit ae177859a10d65a12e83728a02cb6a84bc9a54e1 (1.7.0 build 22).
Prepared cache-safe assets and installed into the local XAMPP app directory.
Verified HTTP-served main.dart.js, flutter_bootstrap.js, version.json and font
manifest hashes match the generated build. No hosted Flutter app was deployed.

Shopping navigation and departments (2026-10-18): Shopping list now uses the
main app scaffold, retaining its hamburger menu and account menu. Shopping list departments is a section inside Household & people, reached
through the user icon menu. Neither settings entry appears in the hamburger
menu.
Members of the selected household can add, rename, reorder, and remove names;
configuration and assigned-item updates are saved together with the list
revision. Removing an occupied department asks for confirmation and retains its
items in the unassigned group. Names and order are shared among household
members. The shopping list loads configured names and refreshes on return.
Hidden shopping views pause polling while retaining their state and pending
writes. Existing rows remain readable without any database migration.

Validation: 21 focused Flutter checks passed across department configuration,
shopping-list behavior/drag lifecycle/sharing, and home navigation. New checks
exercise the shopping hamburger menu, department rename and return refresh,
duplicate names, add, actual drag reordering, removal/cancellation, and stale
configuration recovery. Backend PHP sharing/configuration fixtures also pass.
No app package was built for this feature request; the installed local web app
still needs an explicitly requested rebuild.

Local department-settings web rebuild (2026-10-18): explicitly requested build
completed for 08d196b58c9b4075f0387bab285bf4b55d10de8f (1.7.0 build 22).
Installed prepared assets into the local XAMPP app directory and verified
localhost main.dart.js, flutter_bootstrap.js, version.json and font manifest
hashes against the build. This includes the shopping hamburger menu and shared
department configuration. No hosted Flutter app was deployed.

Settings placement correction (2026-10-18): removed Household & people and
Shopping list departments from the hamburger drawer. Household & people remains
in the user icon menu; its household settings card now contains the department
configuration entry below the people controls. Shopping navigation and returning
from department edits retain the updated shared list. Nine targeted navigation
and department tests passed, including drawer exclusions, account-menu access,
configuration updates, and home layouts at 320 and 1000 pixels. Static analysis
is clean. No app build was requested or produced for this correction.

Main integration (2026-10-18): merged the shopping feature with main's shared
recipe/cooking navigation. The shared drawer retains Shopping list, Recipes
still returns to the root and clears filters, and Household & people remains
exclusive to the account menu. Resolved the account-panel and home-navigation
test conflicts with both behaviors preserved. All 24 focused shopping,
department, home and recipe/cooking navigation checks pass; analysis is clean.
This local merge did not build or deploy an app.

Merged-main local web rebuild (2026-10-18): explicitly requested build completed
for de593ea3d2873fb59704e2b76af22af08ad73798 (1.7.0 build 22). Installed
prepared assets into the local XAMPP app directory. Verified HTTP-served
main.dart.js, flutter_bootstrap.js, version.json and font manifest hashes match
the generated build. Includes the corrected account-menu settings placement and
merged recipe/cooking navigation. No hosted Flutter app was deployed.

Department management navigation (2026-10-18): added the shared household
drawer to the department screen, with the same hamburger and Back controls as
recipe/cooking detail screens. Its drawer returns to the root shopping list or
Recipes through the existing navigation handler. Settings remain exclusive to
the user icon menu. Six department and recipe-menu navigation checks pass,
including saving a rename and returning through the department drawer to see
its updated items. Static analysis is clean. No app build was requested.


Household department memory (2026-10-18): assignments and changes teach the
hosted backend a preference for later additions by any household member. Case,
spacing, punctuation and accents normalize together; common plurals and small
spelling errors can match when the closest department is unambiguous. Exact
matches win. Items with no remembered match remain unassigned. Moving an item
back to the unassigned group teaches that choice as well. Checking off and
removing items leave their saved associations intact.

The app applies the server-returned department immediately after a successful
addition. Queued drags inherit server-selected departments without overwriting
a later explicit department move. Department renames send a mapping so memory
survives even when the associated items are no longer in the list. Memory stays
on the household's server record, with no additional controls or explanatory UI.
No build was requested or produced for this change.

Department-memory validation: all 18 focused shopping-list, department, sharing
and drag lifecycle tests pass. New checks verify immediate rendering of the
server-selected department, rename metadata, and pending-add drags that retain
automatic placement while preserving explicit user overrides. Static analysis
is clean. Backend fixtures separately cover household persistence and matching.


Local shopping cache and live refresh (2026-10-18): confirmed items, order,
check-offs, configured departments and revision are saved through the existing
platform storage adapter (browser local storage or native application-support
files). Keys include server, signed-in account and household. Restoring a cache
never blocks the opening request or overwrites a newer response/local edit.
Cache hydration does not invalidate the in-flight opening refresh. Storage
failures or malformed snapshots are ignored so server access still works.
Unchanged polling responses do not repeatedly rewrite local storage.

The shopping view refreshes immediately on opening/reactivation, returning from
another route and app resume. Five-second polling runs only while the view is
active, foreground and uncovered, with no overlapping reads. Reads defer while
dragging or saving. A small cloud-off icon and Offline label beside the household
name indicate connection failure; recovery clears it even if the revision is
unchanged. Cached content remains visible and typed add text is retained.
Mutations pause while disconnected; this change does not queue offline writes.
Only confirmed server state reaches the cache. Access-denied/not-found responses
clear the relevant cached data rather than displaying it as offline content.

Validation: all 33 focused cache, shopping-list, department, home navigation and
recipe/cooking menu checks pass. Cache checks cover account/household/server
isolation, storage failure/corruption, pending refresh and reopening, late cache
reads, five-second polling, inactive/background/covered view pauses, immediate
recovery, preserved input, failed edits and access revocation. The connection
indicator and recovery flow were exercised at a 390-pixel phone width. No app
build was requested or produced; the local web app needs an authorized rebuild.

Android emulator preview (2026-10-18): at the user's request, built main commit
885398c as a debug Android x64 APK with the existing local Firebase settings.
Installed on CoffeyTable_Pixel_8_API_36 (emulator-5554) with data preserved.
Verified package version 1.7.0 (22), successful app startup, recipe home, shared
hamburger navigation, and the shopping screen with the household's configured
departments and bottom visibility control. Left Shopping list open in the
foreground emulator. Generated APK and local configuration remain excluded.


Compact add row (2026-10-18): replaced the labeled Add item button and stacked
phone layout with one row containing the input and a filled plus icon button.
The control retains its Add item tooltip/accessibility label and keyboard-submit
behavior. The 320-pixel phone-with-keyboard check verifies the button is beside
the input and remains visible and functional. All 24 focused shopping/cache/
department/drag checks pass; static analysis is clean. The user requested a
local web rebuild only; the Android emulator package remains unchanged.

Compact-add local web rebuild (2026-10-18): built app commit
334f18682962fecd0fff6dbf1d6bd83273ef9a49, prepared cache-safe web assets and
installed them in the local XAMPP app directory. Independently verified served
main.dart.js, flutter_bootstrap.js, version.json and font-manifest hashes match
the build. Version is 1.7.0 (22). No Android build or hosted app deployment ran.

Department heading emphasis (2026-10-18): named headings now use 18-pixel bold
(weight 700) title text, making them larger and heavier than item labels while
retaining the compact department rows. Six shopping layout/add/drag lifecycle
checks pass. The requested rebuild targets local web only.

Bold-heading local web rebuild (2026-10-18): built commit
32d9395f6784fdc3a6d6bb7f13a36b50a01b8f00, prepared cache-safe assets and
installed into the local XAMPP app directory. Verified localhost JavaScript,
bootstrap, version metadata and font-manifest hashes against the build.
The current project version is 1.8.0 (24). No Android build was performed.


Tap-to-check and completed grouping (2026-10-18): department headings now use
22-pixel bold text, with height adapting to text scaling. Unchecked assigned
items are inset 16 pixels relative to headings; unassigned and checked items
remain unindented. Removed each item's checkbox. Tapping anywhere on an item
toggles its strike-through and shared checked state. Touch still uses a hold to
drag; ordinary mouse dragging remains immediate. A hold/drag does not toggle.

Checked items are excluded from department groups and collected below all
active items/headings, separated by a divider. Their original department values
are retained, so unchecking restores the correct group and does not alter the
household's remembered association. Hide empty departments counts unchecked
items only. Checked items may reorder among themselves without changing their
departments; to move one to an active department, uncheck it first. Remove
checked off continues to remove the entire checked group.

Validation: all 25 focused list, cache, shared-write, department and drag
lifecycle tests pass. Added an end-to-end check of indentation, larger heading
style, no item checkboxes, bottom grouping, restore-on-tap, empty-heading
visibility, and hold-drag without toggling or changing department associations.
Static analysis is clean. No app build was requested or produced this turn.

Tap-to-check local web rebuild (2026-10-18): built commit
fb67b906a781df69db6e871d1aa7121bae5567bc (1.8.0 build 24), prepared assets and
installed in the local XAMPP app directory. Verified served JavaScript,
bootstrap, version metadata and font-manifest hashes against the build.
Includes larger headings, indented items and checked-item grouping at the bottom.
No Android build or hosted app deployment ran.

Updated Android emulator preview (2026-10-18): explicitly requested debug x64
build installed successfully on CoffeyTable_Pixel_8_API_36 (emulator-5554),
preserving sign-in and data. Verified installed version 1.8.0 (24), opened
Shopping list and visually confirmed the inline plus button, larger department
labels, indented assigned items and absence of item checkboxes. Left the screen
open in the foreground emulator. No household list data was modified for this
preview. Generated packages and local Firebase settings remain excluded.


Persistent empty-department visibility (2026-10-18): saved the checkbox in a
separate account/server/household-scoped local preference, independent of list
snapshots. Both checked and unchecked choices survive reopening/reloading, and
a late preference read cannot replace a choice made in the current screen.
Storage failures retain the usable in-memory choice without blocking the list.

While an item is held for dragging, empty department headings temporarily
appear without changing the checkbox or stored choice. After a drop or cancel,
visibility returns to the saved filter; a newly occupied target stays visible.
Stable row identities retain the active drag as new headings appear. Disposal
clears drag state without scheduling a rebuild from a canceled source.

Validation: 26 focused list/cache/department/drag checks pass, including saved
true/false choices across fresh screen instances, long-press target reveal,
cancellation, a drop into a previously empty department and subsequent reload.
Static analysis is clean. The user requested a local web rebuild only.

Visibility-preference local web rebuild (2026-10-18): built commit
e9e35cb7040166116b191a43c5c9904e872f31d9 (1.8.1 build 25), prepared assets
and installed into the local XAMPP app directory. Verified served JavaScript,
bootstrap, version metadata and font-manifest hashes against the build.
No Android build or hosted Flutter app deployment ran.


Stationary-hold reveal and automatic hiding (2026-10-18): removed the empty
visibility checkbox and its local preference reads/writes. Empty departments
are now hidden unconditionally whenever no item is held or dragged. A primary
pointer hold reveals them at the normal long-press timeout, independently of
the mouse drag recognizer (which starts on movement). Moving beyond touch slop
before the timeout cancels the reveal timer, retaining normal swipe scrolling.
The existing touch long-press and immediate mouse drag recognizers remain.

Stationary hold release is suppressed as a tap so it cannot check off the item.
Releasing, dropping, cancellation and disposal clean up hold/drag state, and
polling waits until the hold ends. Existing stored visibility preferences are
ignored. Cached list state and household assignments are unaffected.

Validation: all 26 focused cache/list/department/drag checks pass. The regression
holds mouse and touch pointers stationary, asserts empty targets before any
move, cancels, releases without moving, then drops into a revealed department
and reopens the screen. Other drag checks now measure empty targets only after
holding. The local web rebuild was explicitly requested.

Stationary-hold local web rebuild (2026-10-18): built commit
3993260d3e311633bdf1c18a6a9ca6ff63fed022 (1.8.1 build 25), prepared assets and
installed into the local XAMPP app directory. Verified served JavaScript,
bootstrap, version metadata and font-manifest hashes against the build.
Two additional opening-synchronization widget checks passed. No Android build
or hosted Flutter app deployment ran.

Stationary-hold Android preview (2026-10-18): explicitly requested debug x64
build from main commit 4870299 installed on CoffeyTable_Pixel_8_API_36,
preserving sign-in and app data. Verified installed version 1.8.1 (25) and
opened Shopping list. Visually confirmed occupied departments only, no empty
visibility checkbox, inline add button and indented items. Left the emulator
open on that screen. No household list items were modified for the preview.


Hold-position correction (2026-10-18): revealing empty departments no longer
inserts headings above existing rows. Temporary empty targets appear after the
existing list, retaining occupied department order and each row's screen
position. Drag feedback retains the original pointer-to-row anchor captured at
press time. A stationary hold or small pointer jitter cannot commit a drop;
the pointer must move beyond touch slop before a department/reorder save.
This avoids treating a layout change beneath the finger as an intentional move.

Validation: 23 focused cache/list/sharing/drag checks pass. The mouse/touch hold
regression now asserts the source row stays at its original screen coordinate,
in addition to no toggle on stationary release, cancellation cleanup and valid
cross-department drops. No app build was requested for this fix.

Shopping header simplification (2026-10-18): removed the household name above
the add row, reclaiming its vertical space while online. The small Offline
indicator remains right-aligned and appears only during a connection failure.
Eleven list/cache checks pass, including no visible household name, phone
keyboard layout and offline recovery. Static analysis is clean. No app build
was requested or produced for this change.

Quiet connection retries and save notices (2026-10-18): shopping reads and saves
retry transient transport errors, HTTP 408 and server failures twice, after
2 and 4 seconds. The existing per-request network timeout still applies, so a
stalled request can take longer than those backoff delays. Refresh failures
show only the small Offline status after attempts are exhausted; cached content
remains visible. Failed saves then restore the last confirmed list, retain add
text and display a neutral-colored, dismissible message: Your change couldn't
be saved. Please try again when connected. Technical HTTP wording is not shown
for these connection-related save failures. Sign-in, membership, validation and
ordinary edit-conflict responses are not retried or hidden.

Retries reuse the same items, IDs and base revision. If a response was lost
after a save committed, a subsequent conflict is treated as success only when
a read confirms the requested item IDs, order, names, checked states and
departments (including server-selected departments for new unassigned items).
Actual concurrent changes remain conflicts and are never silently overwritten.
A temporary verification-read failure may use the remaining retry. Closing the
screen cancels pending retry timers. No offline write queue was introduced.

Validation: 34 focused retry, cache, list, department, drag and opening-sync
checks pass; static analysis is clean. New checks cover a brief outage without
alerts, exhausted retries and neutral save text, retained drafts/cache, lost
save responses with and without temporary verification failure, genuine
concurrent edits, and cancellation on leaving. No app build was requested or
produced for this change.


Department order and drag scrolling correction (2026-10-18): empty departments
now appear in the configured department order during a hold or drag, including
between occupied departments. This supersedes the appended-target workaround
above. Feedback still uses the original press anchor and stationary release
cannot save a move. The list viewport tracks drag pointer movement so scrolling
can reverse upward even after the source row has scrolled offscreen.

Validation covers configured heading order during stationary mouse/touch holds,
repeated department moves, and downward then upward edge scrolling within one
drag. No app build was requested.


Inline item editing (2026-10-18): double-tapping an item replaces its label with
a focused text input and requests the device keyboard. Done, focus loss, or a
tap outside saves a trimmed nonempty name using the existing shared-list save
queue. Blank or unchanged edits leave the item untouched. Renaming preserves
its ID, department, position and completion state. Poll refreshes defer while
editing, and the edited row cannot start a drag. Single taps still toggle
completion after the double-tap recognition window; holds still move items.

Validation includes inline keyboard focus, no completion/save on double tap,
Done and outside-tap saves, blank-edit handling and existing drag/tap checks.
No app build was requested.


Opening-time HTTP 429 correction (2026-10-20): server throttling was excluded
from temporary communication errors, so an automatic opening refresh could
show a red error despite no user changes. It now receives quiet retries with a
30-second default cooldown, honoring Retry-After seconds or HTTP dates. RecipeApi
shares the cooldown across its requests, rejecting network attempts locally
until it expires. Safe reads retry; generic writes remain single-attempt.
Shopping saves retain their existing revision-aware reconciliation.

Cached shopping items remain visible. Exhausted throttled refreshes show the
small neutral “Updates paused” indicator and continue polling for recovery.
Background recipe text sync stops the pass after persistent throttling instead
of continuing through remaining batches and category metadata. Completed text
and successful peers in the current batch remain saved for the next sync.

Validation covers retry delays/header parsing, suppression of requests during
cooldown, cached opening refresh/recovery, persistent neutral status, and stopping
background downloads. No app build or hosted deployment was requested.

Validation result: 93 API, offline recipe and shopping-list checks pass.


Entry notes (2026-10-23): double tap expands the item into Item and optional
Note inputs with a save checkmark. Next moves from name to note; Done, the
checkmark or leaving the editor saves. Notes display as smaller muted text below
the name and remain part of the tap/hold target. They are shared household entry
metadata, limited to 500 characters, preserved by local caching/outbox and
revision-aware save reconciliation. Clearing sends an explicit empty string.
Removing an entry removes its note; name-only department associations do not
inherit notes. Older clients omitting the field preserve a same-ID entry's note.
No schema migration is required.

Focused validation: shopping list editor, retry, cache, drag lifecycle/sharing
and local-data outbox tests; affected-file Dart analysis; PHP shopping_lists.php
fixtures cover household sharing, legacy omission, clearing, validation and
re-adding the name without its former note. Local web rebuild explicitly requested.
