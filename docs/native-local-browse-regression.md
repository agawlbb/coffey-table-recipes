# Native local recipe browsing regression (2026-10-23)

The first complete-database APK successfully downloaded text but its root category
query constructed Map<dynamic,dynamic> rows. The browser cast the row list to
Map<String,dynamic>, which throws in the native Dart VM. The generic error handler
incorrectly called this a connection failure. A new native regression assertion
failed before the fix and passes afterward; the previous web-only live check did
not expose this platform type difference.

Category results are explicitly typed, and the browser normalizes row maps at its
boundary. Production household browsing now explicitly uses the local-only mode:
no network/cache fallback, network deadline, connectivity-triggered reload or
manual network-refresh control. Unexpected local read errors remain distinct local
database failures; they are never silently substituted with empty results or
reported as a connection problem. The old generic connection messages for recipe
list/detail reads were removed.

The local query also repeatedly scanned the entire category catalog inside each
recipe/category search, including empty searches. It now builds a category-parent
index and recipe membership sets once per read, avoids unnecessary deep cloning,
and skips text-search construction for an empty query. This eliminates the
category-squared scan that could block the UI isolate. The phone was not attached
for ANR log capture, so the exact cause of its reported unresponsiveness has not
been independently observed on that device.

Validation: all406 main Flutter tests passed. Android-variant tests use the actual
LocalData-backed RecipeBrowser through root/child/back/search without HTTP, and
verify input remains responsive after a deliberate local read exception. Another
regression uses5000 categories and200 recipes with a five-second bound. The tests
also cover restart, complete-download validation and pending local edits. No
backend changes are necessary; existing downloaded databases remain valid and
must not be cleared to apply this fix.
