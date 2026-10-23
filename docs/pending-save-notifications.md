# Safe recipe retries and pending save reminders

Every new recipe create/edit outbox entry has a durable `client_save_id`. Its
request is replayed unchanged after a temporary network failure or process death.
The server atomically records the result with the recipe and returns the original
receipt on retries. This avoids duplicate creates and false revision conflicts
after a lost edit response. Actual conflicting edits or validation failures still
retain the local draft for review. Legacy ambiguous submissions without an
identifier cannot be retroactively deduplicated and remain reviewable.

Each local change stores its original save time. At 60 seconds without a server
confirmation, the app displays an overdue warning. It keeps the local recipe
visible. Android/iOS also schedule device notifications when the outbox persists,
so reminders do not require a reachable server or a running Flutter timer.
Confirmation cancels pending/delivered reminders. Restart retains the original
deadline; repeated retries do not restart it. Android restores reminders after
reboot/update. Notifications contain no recipe text or account identity.

Device notification permission is required. Denial or scheduling failure is
reported in the app; the in-app warning still works. OS power/notification policy
can delay or suppress delivery, especially Android without exact-alarm permission.
iOS uses one reminder for the oldest outstanding change per account to avoid its
pending-notification limit. Web currently shows the in-app warning while open.
Background uploading remains subject to app lifecycle; reminders do not claim
that background Flutter code runs while the OS has suspended it.

Validation: the local-data suite covers same-identifier retries after a lost
creation response, process-death recovery, retained local data, original deadline
across restart, the one-minute boundary, and cancellation on confirmation. Main
full suite: 408 tests passed; static analysis clean. Native delivery still needs
device verification; no installable app build was requested for this change.
