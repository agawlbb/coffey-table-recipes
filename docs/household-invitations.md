# Household invitations

The envelope beside an unlinked household person opens an email dialog. Owners/admins can send invitations; a rejected request displays the server's explanation in the dialog. A pending invitation keeps the envelope in the same left position as the linked-account icon.

After sign-in/account creation, `/me` supplies pending invitations for the authenticated email. The app asks the recipient to accept or decline before household setup. Acceptance reloads the household and people; declining leaves the account without household membership. An unverified recipient is prompted to verify email before seeing invitation details or responding.

The backend remains coffeybean.com, as selected by the user. Deployment requires the PHP invitation migration/API, authenticated SMTP configuration, and a restricted Firebase account lookup credential. A local web rebuild alone does not activate those hosted capabilities.

Validation: Flutter analysis, existing widget/API tests, and `test/invitations_test.dart` cover email validation, account-already-in-household rejection, retry, pending invitations at login, accept/decline, and email verification gating. See the PHP repository's `docs/household-invitations.md` for server setup and disposable database tests.

Additional regression coverage verifies that an acceptance error leaves the invitation visible for retry, and disables both response buttons while a retry is running to prevent duplicate submission. All five invitation widget tests pass. The current feature is deployed at `https://coffeybean.com/CoffeyTableRecipes/app/`; authenticated hosted UI and real email delivery verification still need a signed-in account and a test recipient.

Invitation links now use `account=create&email=...` for new accounts and `account=signin&email=...` for existing accounts. They open the appropriate form with the email filled in; this URL is only a form hint and grants no access. Signup sends Firebase verification automatically. The pending-invitation verification dialog also sends automatically for an existing unverified account, shares the signup send to avoid duplicates, and offers resend after failure. Firebase's hosted confirmation uses a continue URL back to the prefilled sign-in screen; an existing session refreshes its verified email claim on return. Six invitation widget tests cover these changes. No database or API route changes are required.
