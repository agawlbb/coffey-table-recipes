# Hosted-service access

Publishing this source does not expose the server's OpenAI API key, grant access
to the hosted database, or change backend authorization. Firebase client settings
identify the authentication project; they are not the server's AI credentials.
Server credentials, signing keys and personal configuration are excluded from Git.

The hosted AI endpoints require a valid Firebase ID token for the configured
project, an enabled account, and membership of the household in the request.
Someone without an existing account would need to register with this Firebase
project and create or join a household before using those endpoints. Registration
is offered by the coffeybean.com app, but it can also use Firebase's supported
authentication APIs; visiting the website is not itself the authorization check.
An eligible account can call the backend from the app or a script.

The owner requested removal of the 20-import-requests-per-hour limit on 2026-10-12.
Authentication, household checks, validation, timeouts and request-size limits
remain. Public source does not grant anonymous AI access; account eligibility is
the boundary. This is not a promise that any internet service is free of abuse risk.

AI image generation also requires administrator approval of the household, with
access disabled by default. The backend enforces this for recipe and missing
category images, including requests outside the app. Household owners cannot enable
themselves. Approved household members can generate images without a spending cap.
Existing images and AI recipe importing retain their current access rules.

Administration is determined by the database role linked to the Firebase user ID
verified from the sign-in token. Neither an email address nor a client claim can
grant that role. Google sign-in must resolve to the same Firebase user ID to retain
an existing assigned role. New installations require a trusted operator to assign
their initial administrator explicitly.

Public ID-based recipe sharing is intentional. Recipes are not access-protected
by the public share page. Private imports and account-management data are excluded
from that page. Independent installations should configure their own backend,
Firebase project and API credentials rather than using the owner's deployment.
