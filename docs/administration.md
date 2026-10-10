# Account administration

Account roles are returned by authenticated `GET /me` as `user.account_role` (`user` or `administrator`). This is separate from household owner/admin/member roles. The server grants the initial administrator role to the verified Firebase account with email `admin@example.test`; a matching unverified email cannot grant it.

Administrators see **Administration** in the user menu. Web opens `#/administration` in a separate browser window, restoring the Firebase session without putting tokens in the URL. Android opens a separate administration screen; a blocked browser popup also falls back to that screen. The administration route checks the server role before listing users. The API independently enforces permission on every administration request.

The user list contains database accounts. Delete opens a confirmation dialog identifying the user and explaining permanent deletion. Cancel makes no write. Confirm sends `POST /admin/users/{id}/delete` with `{"confirm":true}`. Success removes the row; failure retains it and displays the error. The current administrator cannot delete their own account.

Deletion removes the Firebase account, database user, memberships, linked household people and related invitations. Shared households, recipes and cooking history remain with account attribution cleared. This is a full delete, not an inactive flag. A person without a login is not an account in this list. Deletion does not prevent someone from deliberately registering a new Firebase account later.

The apps retain `https://coffeybean.com/CoffeyTableRecipes/api/v1`. Hosted activation completed on 2026-10-10 after the user's approval: migration `008_administrators.sql`, coordinated backend deployment and `firebaseauth.users.delete` on the existing server Firebase service account. The existing Project administrator account with email `admin@example.test` was explicitly assigned administrator by database ID and email because its unverified-email flag excluded it from the automatic grant. Its email-verification status remains unchanged. Both the hosted and localhost web copies include the new UI. Server credentials never belong in client builds or Git.

Validation: administrator widgets test menu visibility, navigation, confirmation/cancellation, self-delete protection, denied access and error feedback. The PHP administrator suite uses a disposable local database and a fake Firebase deleter to test authorization, rollback, foreign-key cleanup, shared content preservation and rejection of deleted-token reprovisioning. No real user is deleted during automated verification.

Deployment validation confirmed the hosted database role, healthy API, authentication requirements on administrator routes, protected backups/credentials and an error-free hosted sign-in screen. Authenticated administrator-window verification requires sign-in in the built-in browser. No real account was deleted to verify deployment.
