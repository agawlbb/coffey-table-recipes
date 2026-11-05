# InMotion web app retirement

Task branch `task/retire-inmotion-ctr`, based on main `9487cca`.
The user authorized retiring the hosted web app on 2026-11-05. No app build or
release was required for the retirement operation. The retirement was accepted
and merged into main on 2026-11-05; native release delivery is recorded in
[releases.md](releases.md).

The VPS sends invitation emails without a web destination. An invited recipient
opens the installed app and signs in or creates an account using the invited
email. Existing verified-email checks and Accept/Decline handling stay in place.
Firebase verifies the email, then the user manually returns to the app; generated
links no longer carry an InMotion return URL. The unused Dart return-URL helper
and its obsolete test assertions were removed.

The hosted-web workflow and deployment scripts are removed from this branch;
the existing GitHub web workflow is disabled immediately. Future releases must
omit hosted web publication. Historical web source and release records remain
in Git. Native Android/iOS recipe associations continue on `ctr.coffeybean.com`.

The hosted site and retained source databases are backed up on Samba before
removal. Operational details and the backup location are recorded in the
[VPS repository](https://github.com/agawlbb/coffey-table-recipes-vps/blob/main/INMOTION-RETIREMENT.md).

Validation: affected Dart files formatted and analyzed; invitation, verification
delivery and email-verification widget tests passed (17 tests). No app build.
