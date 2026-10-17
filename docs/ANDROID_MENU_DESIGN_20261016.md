# Android account and alarm menus — 2026-10-16

Inspected the original feature APK in the existing Pixel 8 / API 36 emulator.
Its account menu put a plain Timer settings item above a disabled identity
block and mixed that with taller ListTile actions. Timer settings began with
a dense paragraph followed by the entire device alarm list.

The account menu now uses a single anchored Material surface with a visible
identity header, avatar, shorter action labels, consistent leading icons and
52 dp minimum action rows. Identity and logout have separators. Timer settings
is grouped with the other actions, and existing capability/role gates remain.
It constrains width to the phone and permits text wrapping instead of overflow.

Timer settings now shows the current alarm tone in a settings row. A modal
bottom sheet presents real radio controls, scrollable device sounds, search for
long lists, and pinned Cancel/Save actions. Selection remains local until Save;
cancel and Android Back discard it. Save failures retain the previous tone and
show a readable error. Duplicate saves are blocked while writing. The existing
native tone storage and system alarm behavior are unchanged. Existing timer
limitations remain available under How timers work, and the screen explicitly
states that the choice applies to new/edited timers.

Reference: Material 3 menus and lists:
https://m3.material.io/components/menus/overview
https://m3.material.io/components/lists/overview

Regression checks cover narrow-phone account action routing and tone search,
keyboard insets, Cancel, successful persistence and failure preservation.
Existing account-name/household/logout tests use the updated labels.

Validation: Flutter analysis reported no issues and all 245 Flutter tests passed.
The Android deliverable is a debug feature build, version 1.5.0/build 18, using
the existing Firebase configuration and coffeybean.com backend. The release
version in pubspec remains unchanged. No hosted client/backend deployment,
release tag, or remote push is part of this change.

Emulator visual review confirmed the account menu, settings summary, tone sheet,
search filtering and radio selection on the final clean build. Android package
and signature verification passed. No physical-device alarm behavior is claimed
by this UI work.
