# Account administration

Application administration is separate from household membership roles. The
backend verifies the Firebase ID token and uses its stable UID to find the local
user record. Administration requires that record's account_role to be administrator.
An email address, Google OAuth client ID, or unverified client claim cannot grant it.

Existing assigned administrators retain access, including when their email changes.
New installations have no automatic administrator. A trusted database operator must
assign the role to the intended verified Firebase UID using a parameterized database
update after that account has signed in. Keep the deployment's actual UID private.

Migration 008 adds the role column. The migration runner recognizes the exact
original installed checksum as a legacy case after removal of its personal email
grant; it does not rerun the migration or change existing roles. Other checksum
mismatches still fail.

The API checks administration on every privileged request; hiding a menu is not
authorization. Tests cover denied access, identity continuity, deletion rollback,
self-deletion prevention, shared-content preservation, and deleted-account checks.

## Household AI images

Administration now lists registered households and member counts, with an
"Allow AI image generation" switch for each household. Only application
administrators can change it. Both existing and new households start disabled;
enabling a household lets every member generate recipe images and category artwork.

The server checks the current permission on each generation request, including
requests from older apps or outside the UI. Existing images, camera uploads and
AI recipe importing remain available. Revocation blocks subsequent requests but
does not cancel an image already being generated. There is no spending cap for
an enabled household.

The editor explains disabled access and disables its AI image button. Automatic
category artwork is skipped while permission is disabled. Reopen the editor after
an administrator changes permission to refresh the displayed setting.

Validation: Flutter analysis passed; 24 administrator and recipe-editor widget
tests passed, including switch persistence/failure behavior and disabled image
generation with camera/uploads still available. The separate image-editor suite
also passed. No live paid AI request or macOS build was used for these checks.

The backend permission policy and migration were deployed and verified on
2026-10-12. Existing households are disabled. These Flutter UI changes are committed
and tested; the hosted app UI awaits an explicitly authorized tagged app deployment.
