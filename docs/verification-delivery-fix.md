# Verification delivery and resend cooldown

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

Focused validation covers
`shopping_socket_test.dart`, `backend_socket_test.dart`,
`email_verification_test.dart`, `verification_delivery_test.dart` and
`invitations_test.dart`. Changed Dart files were formatted. Full-suite, analysis
and updated APK delivery evidence will be recorded after completion.
