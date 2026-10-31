# Verification delivery and resend cooldown

The current test APK is [build 43](child-mode-sql.md), which retains these fixes and
also removes the InMotion HTTP policy dependency. Build 42 below is historical;
its superseded APK was moved to Drive trash after build 43 was verified.

The account-test build exposed a client connection race: a newly subscribed
Android connectivity stream reports its initial online state. The socket treated
that first notification as a network transition, closed an already-opening/ready
connection and failed a pending verification write with "Data synchronization
disconnected." Read requests could recover through their existing retry policy;
mail writes must not be replayed automatically because delivery may already have
occurred. A real loopback WebSocket regression reproduced the exact failure
before the fix and passed afterward, including real offline/online recovery.

The first online notification now leaves the existing connection alone. Actual
offline transitions still clear it, and recovery reconnects. Account connection
failures have an account-specific message/code. The verification screen explains
that delivery was not confirmed and advises checking the inbox before resending;
it does not report success or claim that no message was delivered in that case.

Resend remains disabled during delivery and for 60 seconds after each completed
attempt, successful or failed, including the initial signup attempt. The countdown
uses a per-account deadline retained across screen rebuilds. Concurrent send calls
share the same in-flight attempt. Firebase rate-limit messages remain distinct;
the app's cooldown does not claim to reset Firebase's provider limit. Instructions
no longer assume the first email has already been sent.

The existing deployed VPS backend handles these account requests; this reproduced
failure requires no backend source or credential changes. No real test email or
new Firebase account is created by the regression tests. Actual fresh-user signup
and inbox delivery remain device checks after installing the updated test APK.

Focused validation: 22 tests passed in one invocation across
`shopping_socket_test.dart`, `backend_socket_test.dart`,
`email_verification_test.dart`, `verification_delivery_test.dart` and
`invitations_test.dart`. Changed Dart files were formatted and scoped analysis
passed with no issues. The complete `flutter test --no-pub --reporter compact`
suite passed all 549 tests. It ran once after the final source changes because
the socket lifecycle affects shared account/data connections.

A live diagnostic also generated a Firebase action link for an existing unverified
account using the deployed VPS service. It succeeded without sending mail or
logging the link, recipient or token. No new account was created. The existing
VPS runtime and private credentials were retained; there was no backend source
change or unnecessary restart.

Updated test delivery: Android `2.4.0-account-test`, build 42, from immutable source
`80c7260b3ac42479123225431af5c7016cc915cc`.
[Build 41210524212](https://github.com/agawlbb/coffey-table-recipes/actions/runs/41210524212)
passed, including original signing identity, package/version/source and hosted
app-link verification. Independent local APK checks and the downloaded Drive
SHA-256 matched: `552c1b92af58162e33e4036abf5655e95a706231baae35ace5c0f37de284bce4`.
[Download verified build 42](https://drive.google.com/file/d/1kBLKeNviqthun7UYSd5RTqpTyLF6sNVv/view).
The usual private pinned recipe app folder was used. An informational Android
notification was sent with no link/click action. Stable build 40 was retained;
superseded test build 41 was already absent from the authorized listing, so this
publication trashed no files. No web/iOS build, merge to main, app metadata on the
VPS or sharing change was performed. Install over the previous app and retry
verification, or test automatic delivery with a fresh signup.
