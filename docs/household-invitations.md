# Household invitations

The envelope beside an unlinked household person opens an email dialog. Owners/admins can send invitations; a rejected request displays the server's explanation in the dialog. A pending invitation keeps the envelope in the same left position as the linked-account icon.

After sign-in/account creation, `/me` supplies pending invitations for the authenticated email. The app asks the recipient to accept or decline before household setup. Acceptance reloads the household and people; declining leaves the account without household membership. An unverified recipient is prompted to verify email before seeing invitation details or responding.

The backend remains coffeybean.com, as selected by the user. Deployment requires the PHP invitation migration/API, authenticated SMTP configuration, and a restricted Firebase account lookup credential. A local web rebuild alone does not activate those hosted capabilities.

Validation: Flutter analysis, existing widget/API tests, and `test/invitations_test.dart` cover email validation, account-already-in-household rejection, retry, pending invitations at login, accept/decline, and email verification gating. See the PHP repository's `docs/household-invitations.md` for server setup and disposable database tests.
