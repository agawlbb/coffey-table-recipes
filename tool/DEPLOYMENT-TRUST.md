# Deployment client trust store (October 21, 2026)

The manual web-deployment workflow uses a dedicated virtual environment with
Requests 2.32.5 and certifi 2026.10.19. Authenticated cPanel calls and public
asset checks explicitly pass certifi.where() as Requests' verify argument.
This selects that wheel's CA bundle even if REQUESTS_CA_BUNDLE or CURL_CA_BUNDLE
is set. TLS certificate and hostname verification remain enabled.

Four offline tests pass with Python 3.14.8, including environment CA overrides,
failed-upload handling, and separation of authenticated and public clients.
No cPanel credentials or live deployment were used. Historical distro-certifi
version output alone does not establish the historical effective trust bundle.
The workflow remains manually dispatched and requires a release tag.

The actual isolated bundle was inspected through Python's SSL certificate
loader: both compromised emSign G3 roots are absent. A regression test verifies
this before authenticated deployment. The 2026.10.19 upstream release restores
unaffected emSign roots, so rejecting every root with an emSign name would be
incorrect: https://github.com/certifi/python-certifi/commit/662df63 .
