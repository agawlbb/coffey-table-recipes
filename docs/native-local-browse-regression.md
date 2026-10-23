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

Feature verification: all443 tests passed, with clean changed-source analysis.
The deliberate local-error regression also opens the actual Scaffold hamburger
menu and then edits the search field, verifying the error boundary does not trap
navigation or input. No phone was connected for Android ANR/log capture.

## Corrected main test builds

Built main runtime bc11ee6e8d80929ad9a225c767f5b2e20800dc52, version1.8.5+29,
after the native/read responsiveness fixes. Web and Android debug builds passed.
The local XAMPP version.json identifies that commit; delivered main.dart.js matches
SHA-2563646368a84ef7a4c70a62b8c197b3caf96db1c672ffd28f74ee19a816a686ee3.

Replacement APK:
G:/My Drive/recipe app/CoffeyTableRecipes-main-native-local-fix-bc11ee6.apk
(199839032 bytes). Build/delivery SHA-256 both
c498783335a6468136cec82297c7ad90b8edccd158009dab6ab4cd1e644e0db6.
Android debug signature verification passed with the existing certificate
f8de933f14b9bb4b3191a94aedc8637972c5ab224565f6abd7808f8038d12097.
This supersedes the earlier d5d04a8 test package. Install over the existing app;
retain device data. No native installation/ANR log capture, backend change,
hosted Flutter publication or release tag was performed for this correction.


## iOS blank-filter and recipe-opening report, 2026-10-23

The user reported intermittent waits of approximately one minute in 2.0.0: a
linear indicator after applying the blank-only filter, then a circular indicator
opening a recipe. No physical-device trace or reproduction is available, so the
exact cause of that incident remains unconfirmed.

Ready household browsing now receives `LocalData.readView`, a synchronous read of
the committed in-memory generation. Root/category/filter reads, filter people,
recipe detail and initial favorites bypass asynchronous request/cache wrappers.
Detail navigation carries the same reader into related recipes. Background
snapshot persistence is independent: readers retain the prior committed data
until the replacement is durable, then local change events update the screen.
Permission rejection still blocks removed household data. A local detail refresh
error preserves already displayed content unless access was rejected. Editing
continues to load its editor catalog through the existing local repository API.

This removes an asynchronous loading seam; it does not establish that a network
request caused the original iPhone waits. Existing async callers normally resolve
from local data, but the detail screen still had the legacy cache/request timeout
sequence and started without a displayed recipe. The production route now reads
locally before its first paint instead of relying on that sequence finishing.

Focused validation: `recipe_browser_test.dart`, `recipe_filter_dialog_test.dart`
and `blank_recipe_detail_layout_test.dart` passed in the combined affected run.
After correcting the new regression's filter selector, all 8 snapshot-database
tests passed, including an iOS-mode widget scenario with stalled persistence and
never-completing async/cache readers: filter/open remain usable for a simulated
minute, no loading indicators or async reads occur, and committed replacement
data appears afterward. All 27 `local_data_test.dart` tests passed. Changed Dart
files were formatted; analysis of the three source files and snapshot test passed.
No full suite, build, release, hosted publication or physical-device run was done
for this bounded source change. TestFlight 2.0.0/build30 predates this patch.
