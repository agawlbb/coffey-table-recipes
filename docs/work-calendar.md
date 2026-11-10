# Home Assistant work calendar

Task branch: `feat/work-calendar`, based on Flutter `f9b7ebf`, HA integration
`73f5a3a`, and VPS backend `fde81a0`. Each repository keeps its own commit.

The CTR integration's Home Assistant options accept one optional calendar entity
for the connected household. Every event counts, regardless of its title. HA sends
only occupied dates through the existing authenticated CTR WebSocket; event
contents and calendar credentials stay in HA. All-day dates retain their meaning;
timed events use HA's configured local timezone. Event ends are exclusive, so an
event ending at midnight does not mark the next day. Overlapping events produce
one bar per date.

HA subscribes to calendar event updates and entity state changes, with a 60-second
poll as a fallback and retry after failures. The source calendar's own refresh
schedule still controls how soon HA sees an external change. Each successful
refresh replaces the date list, so moved/deleted events remove previous markers.
An unavailable calendar retains the last successful dates; clearing the calendar
selection publishes an empty date list. The rolling sync window covers 366 days
before today through 730 days after today; dates outside it have no markers.

Settings has a household Workday color palette (amber by default). The meal planner
shows only a slim color bar beside marked dates, including dates without meals.
There is no planner label or tooltip. Color changes use the existing local-first
outbox; dates/color arrive in household snapshots and remain available offline.
HA date updates preserve the household color, and color edits preserve dates.

Backend setup requires the explicit one-time `bin/work-calendar.sql` schema step
before deploying the changed backend. Then install the changed HA integration and
select its calendar. App installation requires a separately requested build or
release. The initial source implementation did not install or deploy these changes;
the subsequent authorized rollout is recorded below.

Validation: affected Dart files formatted; affected sources and new tests analyzed
without issues. Three new Flutter tests cover markers and incoming changes,
settings color selection, and offline restart/delivery/account separation. All 37 existing
planner and access regressions passed in a separate serial run. No app build or full suite was requested.

## Authorized rollout and temporary Android APK — 2026-11-10

The owner explicitly requested backend setup/deployment, HA installation and a
temporary Android APK. The backend calendar table was created once and its
foreign key verified. Backend source `a5da643` was deployed; a new-file mode 600
startup failure was corrected to 644, then the service recovered. The live health
endpoint and source checksum comparisons passed, with CPU shares 1024 and
`cpu.max` starting with `max`. See the backend's WORK-CALENDAR.md rollout record.

HACS installed HA source `d8ffc96` from `feat/work-calendar`. All 16 installed
component files matched source. Home Assistant 2026.11.0 restarted and CTR loaded.
Selected `calendar.joe_s_work_schedule_work_calendar`, retaining existing shopping
selections and scan interval. All nine current calendar event dates matched the
nine dates received by the backend. No production events, meals or synthetic
shopping items were changed for validation. See the HA VALIDATION.md record.

[Android test build 42729933301](https://github.com/agawlbb/coffey-table-recipes/actions/runs/42729933301)
succeeded from immutable app source
`4d35236065818b4d424923bd97dae3bd89d0df96`. This uses the existing workflow's
generic test version name `2.9.1-account-test`, build 72; no release tag was made.
Workflow validation includes original distribution signing identity, package,
version/source, Kotlin classes needed by native timer preferences and hosted
Android app links. Downloaded-artifact verification independently confirmed the
SHA-256, certificate, package/version and non-debuggable status;
`python3 tool/verify-app-links.py --fingerprint
f8de933f14b9bb4b3191a94aedc8637972c5ab224565f6abd7808f8038d12097`
passed. No app/tooling suites were rerun for this operational delivery.

- [Temporary work-calendar APK](https://drive.google.com/file/d/11eKt3nNUuiqZ2gYgVo9WB3Hz8uD032de/view)
- Filename: `CoffeyTableRecipes-2.9.1-work-calendar-test-build72.apk`
- Size: 71,874,201 bytes
- SHA-256: `60789fe418f92e69069b00c8ed37c1316806f613cea4d5eb6e4c0cec2a2b8cea`

Uploaded through the existing folder-pinned Drive helper to the authorized recipe
app folder, then downloaded and verified by SHA-256. Existing files/sharing were
retained; no release notification was sent. Artifact and verification reports are
retained outside Git at
`/home/debian/projects/.release-tools/test-work-calendar-72/`.

Physical Android installation/rendering and OS link resolution were not tested.
No full suite, iOS/web build, release or main integration was performed. All
implementation and rollout records remain on the three existing task branches.

## Phone date header follow-up — 2026-11-10

Past, today and future date labels now stay on one line beside the workday bar.
The date receives two fifths of the remaining header width instead of one quarter,
with a scale-down fit only when its full label would otherwise wrap. The existing
Timeline/Add dish controls retain their compact side-by-side layout.

The new 320px regression reproduced multiline dates before the fix and verifies
past/today/future labels fit completely on one line with bars and both actions.
The initial planner/calendar file run passed 26 tests but exposed one 320px compact
button-height regression. After adjusting header proportions, the four directly
affected date/header layout checks passed at 320px, 390px and 900px. Both changed
Dart files were formatted and analyzed without issues. The other passing planner
and calendar scenarios were not repeated after that final proportion adjustment.
No full suite, new APK, deployment or main integration was requested or performed
for this follow-up; the previously delivered test APK predates this fix.

## Accepted release — 2.10.0 build 73

On 2026-11-10 the owner approved merging all three repositories to main, deleting
the merged calendar branches and releasing the app. The release includes the
phone date-header fix, superseding the earlier temporary APK.

[Android release APK](https://drive.google.com/file/d/1UhScyd89qM0kiupnHhPEogMA0HMVitpT/view)
and TestFlight 2.10.0/build 73 are verified delivered; Apple reports VALID and
IN_BETA_TESTING for the existing Family testers group. HA now tracks main and
retains the selected work calendar; its already deployed code was unchanged by
main integration. See docs/releases.md for source, checksums, signing/link checks,
the iOS provisioning-timeout retry, processing evidence and merged-branch cleanup.

## Foreground Endpoint not found repair — 2026-11-10

Task `fix/calendar-connection`, base app main `09e5894`; companion backend base
`44c1261`. The generic Saved on this device / Endpoint not found / retry notice
is raised when a durable local write fails to send. Work-calendar was missing
from isVpsDataPath, so the production RecipeApi fell back to HTTP for calendar
color writes even with the shared WebSocket connected. The HTTP service has no
calendar data endpoint. Foregrounding retried the pending write and the same
notice appeared again. A mock-transport audit reproduced that misrouting; the
separate live-backend failure audit reproduced calendar-read startup/disconnect
failures using disposable SQLite fixtures, not production data.

Added work-calendar to the existing socket route allowlist. Reads and color saves
now use the authenticated shared app connection. Existing durable pending writes
are retained and can deliver after reconnect; no cache reset, operation deletion,
new controls or suppressed send-error messages were introduced.

Extended the real Dart-to-PHP connection regression to queue a color change while
offline, resume the app twice, verify the saved color on the server and verify no
send-error callback. The same scenario retains account, timer, meal and shared
connection behavior. HTTP is mocked to fail immediately so fallback cannot pass
silently. The selected real transport check passed against the companion backend
fixture. Both changed Dart files were formatted/analyzed without issues. No app
build or full app/tooling suite was run; the released 2.10.0 still needs replacing
with a build containing this client fix.

The companion backend catches exceptions from its optional calendar snapshot
read, logs a safe error and returns empty dates/default amber while unreadable.
Core startup and updates remain available; stored calendar data is not changed,
and subsequent good snapshots restore its dates/color. Four selected server
WebSocket regressions and calendar/data-socket fixtures passed; three new checks
were repeated after fixture connection cleanup. This guards read exceptions,
not unrelated network/database failures or an indefinitely stalled SQL query.

Backend source `1439d90` was deployed and health/source/CPU-policy checks passed.
See backend WORK-CALENDAR.md for the operational record. No schema setup or HA
integration change was needed. Both repairs remain on fix/calendar-connection
branches for owner review/main acceptance; no new app build or release was made.

## Released repair — 2.10.1 build 74

The owner accepted main integration, merged-branch cleanup and release on
2026-11-10. The calendar endpoint routing repair is included in
[Android 2.10.1 build 74](https://drive.google.com/file/d/1t77Iuvn0u7cvjTbZwrsP9wcCO_nkgmvh/view)
and the verified TestFlight 2.10.1/build 74. Apple reports VALID and IN_BETA_TESTING
for the existing Family testers group. Existing pending color writes can deliver
through the corrected shared connection after installing this build; no cache or
change reset is required. See docs/releases.md for native signature/source/link
checks, delivery records and final main/branch synchronization evidence.
