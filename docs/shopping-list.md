# Shopping list

Open **Shopping list** from the hamburger menu for the selected household.
All household members share the same list. Items have a name and department;
checkboxes apply one strike-through. Items have no tap-to-edit screen. Click
and drag with a mouse, or hold a row on a touch screen, to reorder. **Remove checked off** stays at the bottom.

Items appear beneath department headings, with Produce first and Other last.
Every department is displayed as a compact 30-pixel heading, with no empty
placeholder or drop box. Drag anywhere on the item label or row.
Drop on a department heading to move the item into that department, or on the
upper/lower half of another item to insert before/after it. The drop saves the
new department and position together. Headings are not draggable and retain
accessibility heading semantics. Dragging near the list edge scrolls the list.
Rows omit both the redundant department subtitle and trailing drag/menu icon.

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
