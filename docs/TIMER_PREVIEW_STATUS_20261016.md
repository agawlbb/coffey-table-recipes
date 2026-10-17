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

Platform references:
https://developer.android.com/reference/android/media/Ringtone
https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/MultimediaPG/UsingAudio/UsingAudio.html
