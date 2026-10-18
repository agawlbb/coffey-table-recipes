# Shopping list

Open **Shopping list** from the hamburger menu for the selected household.
All household members share the same list. Items have a name and optional department;
checkboxes apply one strike-through. Items have no tap-to-edit screen. Click
and drag with a mouse, or hold a row on a touch screen, to reorder. **Remove checked off** stays at the bottom.

New items are added without a department, above all department headings. The
add form contains only the item field and Add item button. Unassigned items
have no visible heading. Drag an assigned item to the top strip to remove its
department, or drop on a department heading to assign it. The named Other
department remains distinct from having no department.

Assigned items appear beneath department headings, with Produce first and Other last.
By default every department is displayed as a compact 30-pixel heading, with no empty
placeholder or drop box. Drag anywhere on the item label or row.
Drop on a department heading to move the item into that department, or on the
upper/lower half of another item to insert before/after it. The drop saves the
new department and position together. Headings are not draggable and retain
accessibility heading semantics. Dragging near the list edge scrolls the list.
Rows omit both the redundant department subtitle and trailing drag/menu icon.

The bottom **Hide empty departments** checkbox hides only named departments
that have no items. Unassigned items and occupied departments remain visible;
unchecking it restores all department headings. This is a view setting for the
open screen and does not change the household list or anyone else's view.

The screen uses the app's existing theme and refreshes while visible and on
resume. Changes require a connection to coffeybean.com. Concurrent changes are
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
