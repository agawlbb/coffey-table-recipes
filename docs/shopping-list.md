# Shopping list

Open **Shopping list** from the hamburger menu for the selected household.
All household members share the same list. Items have a name and department;
tap an item to edit or delete it. Checkboxes apply one strike-through. Hold a
row and drag to reorder. **Remove checked off** stays at the bottom.

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
