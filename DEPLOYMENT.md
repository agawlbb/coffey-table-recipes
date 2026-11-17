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

Check https://ctr.coffeybean.com/health and affected read-only public behavior.
Authenticated account/shopping/timer checks must use authorized test identities;
never change live recipes or send notifications as an unsolicited smoke test.
The fixed source/state/private mounts and production CPU/memory policy are
unchanged. The service has no Docker healthcheck, so running is not a health claim.
Do not rerun migrations, image builds, media cutover, credential imports or Caddy
reloads for routine source deployment. Those need separate administration.
Source rollback repeats this procedure from canonical main, retaining current data.
