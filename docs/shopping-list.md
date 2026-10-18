# Shopping list

Open **Shopping list** from the hamburger menu for the selected household.
All household members share the same list. Items have a name and department;
checkboxes apply one strike-through. Items have no tap-to-edit screen. Hold a
row and drag to reorder. **Remove checked off** stays at the bottom.

Items appear beneath department headings, with Produce first and Other last.
Every department is displayed, including an outlined drop area when empty.
Hold anywhere on an item to reorder it or drag it beneath another department;
the drop saves its new department and position together. Headings and empty
drop areas are not draggable. Headings retain accessibility heading semantics.
Rows omit both the redundant department subtitle and trailing drag/menu icon.

The screen uses the app's existing theme and refreshes while visible and on
resume. Changes require a connection to coffeybean.com. Concurrent changes are
protected with server revisions: a stale save reloads the shared list and
shows a brief retry message. Unsaved add text survives failures.

The backend requires migration 015 and its shopping-list endpoint. No app
package is built or hosted app deployed for this feature change.

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
