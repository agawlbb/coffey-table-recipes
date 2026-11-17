# Routine VPS source deployment

Run preparation, dependencies, selected tests and Git in VM-laptop's existing
checkout using `dev COMMAND...`, from the clean committed default branch.
Use VM-only test credentials. Deploy only when explicitly requested.
From `dev bash`, use standard rsync and `ssh vps-admin` with the existing pairing.
Transfer prepared files only, preserving private settings, runtime state and
infrastructure. Never build images or install dependencies on the VPS.
Infrastructure, schema and access changes need their own requested scope.

Prepare the locked runtime dependencies in development:

    composer install --no-dev --prefer-dist --no-interaction

Run only the focused checks for the requested change. Do not run a full suite
automatically. Never use production data for development tests.
Routine deployment does not rebuild the PHP runtime or copy Compose/Caddy.
Do not use the old host-only deploy.py for this restricted-account path.

Validate Compose, stop only backend, transfer prepared code, then start it.
A failed transfer must be resolved before restarting; downtime is acceptable.
Private settings and persistent media/state are outside the code directory.

    ssh vps-admin 'sudo -n /usr/bin/docker compose --env-file /dev/null -f /opt/services/ctr-backend/compose.yaml config --quiet'
    ssh vps-admin 'sudo -n /usr/bin/docker compose --env-file /dev/null -f /opt/services/ctr-backend/compose.yaml stop backend'

    rsync -rlt --omit-dir-times --delete --exclude __pycache__ --exclude "*.pyc" --exclude ".env*" src/ vps-admin:/opt/services/ctr-backend/code/src/
    rsync -rlt --omit-dir-times --delete --exclude __pycache__ --exclude "*.pyc" --exclude ".env*" vendor/ vps-admin:/opt/services/ctr-backend/code/vendor/
    rsync -rlt --omit-dir-times --delete --exclude __pycache__ --exclude "*.pyc" --exclude ".env*" assets/ vps-admin:/opt/services/ctr-backend/code/assets/
    rsync -rlt --omit-dir-times --delete --exclude __pycache__ --exclude "*.pyc" --exclude ".env*" bin/ vps-admin:/opt/services/ctr-backend/code/bin/
    rsync -rlt --omit-dir-times --delete --exclude __pycache__ --exclude "*.pyc" --exclude ".env*" associations/ vps-admin:/opt/services/ctr-backend/code/associations/
    rsync -rlt --omit-dir-times bootstrap.php server.php ai-worker.php account-worker.php composer.lock vps-admin:/opt/services/ctr-backend/code/

    ssh vps-admin 'sudo -n /usr/bin/docker compose --env-file /dev/null -f /opt/services/ctr-backend/compose.yaml up -d --no-build --no-deps --wait --wait-timeout 120 backend'
    ssh vps-admin 'sudo -n /usr/bin/docker inspect --format {{.State.Status}} ctr-backend'
    ssh vps-admin 'sudo -n /usr/bin/docker logs --tail 60 ctr-backend'

Check https://coffeybean.com/ctr/health and affected read-only public behavior.
Authenticated account/shopping/timer checks must use authorized test identities;
never change live recipes or send notifications as an unsolicited smoke test.
The fixed source/state/private mounts and production CPU/memory policy are
unchanged. The service has no Docker healthcheck, so running is not a health claim.
Do not rerun migrations, image builds, media cutover, credential imports or Caddy
reloads for routine source deployment. Those need separate administration.
Source rollback repeats this procedure from canonical main, retaining current data.


## Public hostname migration

Source-generated share links and managed recipe/category/photo URLs now use
`https://coffeybean.com/ctr`; internal HTTP and WebSocket paths remain unchanged.
The existing proxy must continue stripping `/ctr` before forwarding. Public
branding assets use `/ctr/assets/email/`. `backend.caddy` is the retained legacy
subdomain configuration; do not replace the main site's configuration with it.

On an explicitly requested deployment, publish the updated backend source and
merge this app's association entries into the domain-root
`https://coffeybean.com/.well-known/assetlinks.json` and
`https://coffeybean.com/.well-known/apple-app-site-association`, preserving other
apps' entries. Serve HTTPS 200 JSON without redirects. The iOS association
component is `/ctr/recipes/*`; Android package and signing certificate are unchanged.
No Caddy configuration or production data was modified during source preparation.

The Flutter app must be rebuilt/released with its new associated domain and
recipe path. The separate Home Assistant integration must also be updated.
Keep the old DNS entry until deployment and client updates are verified; old
shared links/bookmarks require that entry even afterward.

Focused source validation: 34 HTTP fixture assertions, category-artwork and
media-migration fixtures, and four selected data/AI WebSocket scenarios passed
with disposable SQLite and fake AI providers. The page scenario checks canonical
URLs, image/branding URLs and the association route. No complete suite, live
mutations or deployment was run. Live `/ctr/recipes/12` returned 200 but still
contained the old hostname, and both new domain-root associations returned 404.


### Authorized deployment — November 17, 2026

Backend `a016376` is deployed. The ten changed source/association files were
checked against expected prior/current source before transfer and read-back
verified against VM hashes afterward. Root-owned code required sudo rsync;
file ownership and persistent data were preserved. Backend restart is healthy,
CpuShares=1024 and cpu.max=`max 100000`. No dependency/image/schema change.

VPS config `3ef667c` adds the two apex association routes to the existing root
site. Caddy candidate validation and exact-live-hash check passed before its
graceful reload, retaining unrelated handlers and the transitional hostname.
No other apps' association entries were present. Both root association checkers
passed; public page, image, branding, health and HA bootstrap returned 200.
The rendered recipe no longer contains the old hostname. No live data mutation,
DNS change, app build or full test suite was performed in this backend repository.
Corrected native app release is 2.10.4/build 78; its delivery and actual signed
association verification are tracked in the Flutter repository.
