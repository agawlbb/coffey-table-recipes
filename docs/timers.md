# Timer settings and status

The account menu opens Timer settings. The sound-selection bottom sheet supports
search, radio selection and Cancel/Save. Selection stays local until Save;
Cancel and Android Back discard it. A failed save retains the previous sound.
The selected sound applies to newly scheduled or edited timers.

Selecting a sound plays a one-second preview. A new selection replaces the
previous preview; leaving the selector or putting the app in the background
stops it. Previewing never schedules an alarm or saves the selection. Android
uses device alarm sounds with alarm-volume attributes. iOS uses bundled sounds,
including `default.wav`; existing timers retain their scheduled sound.

An app-wide bar shows the nearest timer's countdown or Time is up and the count
of other timers. Tap it to manage timers and stop alarms. It restores native
timer state on resume, refreshes while timers exist, and updates after schedule
or cancel operations. Failed reads retain confirmed state; stale responses
cannot revive cancelled timers or erase newly scheduled ones. Expired records
remain until stopped. Cooking mode observes the same state.

The bar is visible while the app is open. Native alarms and supported iOS Live
Activities retain their own lifecycle and permission requirements. See
[timer synchronization](timer-sync.md) and [release verification](releases.md)
for cross-device behavior and the limits of physical-device validation.

The regression suite covers narrow account menus, sound selection and save
failures, one-second preview cleanup, timer navigation, cancellation and stale
state recovery. Retain these tests when changing the controls. Run the affected
timer test files for source validation, following the focused-validation rules
in `AGENTS.md`; builds, device installation and distribution require
separate explicit authorization.
