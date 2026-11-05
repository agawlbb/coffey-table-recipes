# Server connection in 2.7.6

Requested behavior: one foreground connection, server-owned data, no local/server comparison workflow. Green means the authenticated connection is open.

The first launch of 2.7.6 clears recipe caches, image caches and pending Dart/native synchronization actions once, before loading data. Unsent edits are discarded, including old blocked recipe/meal-plan saves. Firebase sign-in, installation identity and device preferences remain. The server is not cleared.

All production RecipeApi instances share AppConnection. Account, household, cooking, timers and public recipe reads use that connection. Startup receives server state; subsequent changes are pushed. Saves go directly to the server, without the old recipe outbox. Account commands share a serial command stream. Authentication renews on the existing socket. Resume or a lost connection reconnects and receives current server state.

No minute snapshot polling or data-confirmation checks control the indicator. Existing transport heartbeat and cooking presence remain. Native notification actions retain their existing short background delivery when Flutter is suspended; foreground native actions use the shared Dart connection.

Validation: reset-once/sign-in retention, connection indicator, real Dart/PHP protocol, screen reconnect, invitation acceptance and token renewal tests. Backend tests cover four simultaneous clients, account commands, bidirectional changes before acknowledgments and account isolation. Full release validation and delivery are recorded in releases.md. Physical affected-device acceptance requires installing the update.
