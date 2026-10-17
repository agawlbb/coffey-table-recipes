# Importing alternative cooking methods

When a website supplies separate complete appliance methods, import offers each
method and "Both, as linked variations". The first method listed becomes the main
recipe. Both drafts are reviewed and saved separately; the second is linked to
the first only after the first has saved successfully. Cancelling the second
leaves the first recipe saved. Each method retains its source picture and its own
import identity. Questions for either draft are handled before its review.

The method choice is required; "Review with missing details" cannot bypass it.
Choosing both allows additional request time for two AI extractions. Existing
apps without this flow can choose a single method through backend clarification.

Validation: six method widget tests cover required selection, single selection,
sequential linked saves, child clarification, cancellation and failure of the first save.
All 86 targeted import, editor, source-link and shared-import tests pass. Flutter
analysis is clean. A broader variation run also exposed an existing compact-title
menu overflow in unchanged `recipe_browser.dart`; that layout is outside this change.
The supplied
Life Made Simple soup page passed a live backend extraction with distinct
25-minute stovetop and 15-minute pressure-cooking timers. No app build was made.
