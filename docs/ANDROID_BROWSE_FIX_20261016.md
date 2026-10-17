# Android feature browsing fixes — 2026-10-16

The feature build at `2ca406d` could replace the UI with Flutter's error display
when the keyboard opened. Reproduced in an app-level widget test as
`No Overlay widget found` from RawTooltip: the global keyboard-dismiss control
was above Navigator, so its tooltip had no overlay ancestor. The global offline
badge had the same placement problem. Wrapped both controls and the Navigator
in an outer overlay; retained tooltip accessibility and keyboard dismissal.

Breadcrumbs and Back previously disabled themselves during browse requests,
making All Recipes ignore taps during search or category loading. They now
remain active, dismiss the keyboard, and use the existing request generation
guard to prevent a late category response replacing the root results.

Online cached browsing could return a partial initial download with no category
tree as if it were the complete library. It now fetches the server when there
is no completed library or when the requested tree has not been saved yet.
Existing saved text remains available offline; no cache clearing is required
for this fix. This addresses the identified partial-cache path, not every
possible source of outdated category metadata.

Regression coverage includes the actual app wrapper with keyboard insets,
Android offline badge visibility, phone search layout, returning to All Recipes
during a pending request, late-response isolation, and interrupted text/category
downloads. The keyboard-overlay test failed before the fix with the error above.

The replacement APK is a debug feature build, version 1.5.0/build 17, using the
existing local Firebase configuration and hosted coffeybean.com backend. The
pubspec release version is unchanged. This is not a release or hosted app
deployment. No Android device was connected during initial reproduction;
physical-device verification remains necessary.

Validation: Flutter analysis found no issues; all 243 Flutter tests passed.
Android debug APK compilation passed;
`apksigner verify` passed and package inspection confirmed the existing
application ID, version 1.5.0/build 17, minimum SDK 24 and target SDK 36.
