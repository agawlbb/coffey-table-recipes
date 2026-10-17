# Timer sound previews and app-wide status — 2026-10-16

Each alarm tone now has a Play/Stop preview control. Previews are independent
of the saved choice, last at most five seconds, replace earlier previews,
and stop when the selector closes or the app leaves the foreground. Android
uses the actual device alarm sound and alarm-volume audio attributes. iOS uses
AVAudioPlayer with bundled files. Its default for newly scheduled/edited timers
is now a bundled `default.wav`, so the default can be previewed accurately;
already scheduled timers retain their original sound. No preview schedules an
alarm or changes sound preferences.

A compact bar above every app page displays the nearest timer's live countdown
or Time is up, with a count when multiple timers exist. Tap it to manage all
timers, including Stop controls and individual recipe/action titles. The bar
uses persisted native timer state, refreshes on app resume and every ten seconds
while timers exist, and preserves its last confirmed state on platform errors.
Successful schedule/cancel updates appear immediately. Stale in-flight reads
cannot erase a newly scheduled timer or revive a cancelled one. Cooking mode
observes the same state so global cancellation is reflected there.

The bar is present on Android and iOS, providing a fallback when iOS Live
Activities are unavailable or disabled. Existing Live Activities remain intact.
Android retains its exact OS alarms and ongoing ringing notification; this
change uses an in-app bar for countdowns rather than a foreground service
running throughout the countdown. The bar is visible only while the app is open.
Expired native timer records remain visible until stopped, consistent with
the native alarm model.

Validation covers navigation with a running timer, last-timer removal while its
management sheet is open, failed cancellation, stale restoration, single-preview
replacement, timeout and selector-close cleanup, and selection independence.
Android development package: version 1.5.0/build 19; release version unchanged.
No hosted client/backend deployment or TestFlight upload is part of this work.

Local validation: analysis clean; all 248 Flutter tests passed; Android debug
compilation and APK signature verification passed. iOS configuration/audio
packaging tests validate all three bundled PCM sounds. Native iOS compilation
and emulator observations are recorded separately after completion.

Pixel 8/API 36 emulator: tone selector rendered Play controls; pressing Argon's
preview created a started MediaPlayer with USAGE_ALARM and no muted state.
After the bounded preview, no started player remained. The saved tone remained
Default alarm. The emulator had notifications denied and no explicit exact-alarm
grant, so real scheduling/ringing was not claimed; global countdown/navigation
and Stop behavior were verified through widget tests with a mocked native
store. Physical-device audibility, alarm permissions and lifecycle behavior
remain release-validation work.

Unsigned iOS compilation was dispatched from feature commit `d67cb07`:
https://github.com/agawlbb/coffey-table-recipes/actions/runs/38992979709
The user subsequently instructed that app builds require an explicit build or
release request. Cancellation was requested for this run; no successful iOS
compilation or distribution is claimed. The project instructions now record
that requirement for every app platform and development package.

Delivered Android package:
`G:\My Drive\recipe app\CoffeyTableRecipes-1.5.0-build19-test-d67cb07-debug.apk`
SHA-256: `cd73ad4770cbc4c99e5725859e646c05dd8517a999c1b2e580793f325418c343`.

Platform references:
https://developer.android.com/reference/android/media/Ringtone
https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/MultimediaPG/UsingAudio/UsingAudio.html
