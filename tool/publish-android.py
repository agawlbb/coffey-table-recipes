"""Publish a verified APK on the VPS; prune old releases only after HTTPS checks."""
import argparse
import base64
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import time
import urllib.parse
import tempfile
import urllib.request
import zipfile

RELEASE = re.compile(r'CoffeyTableRecipes-(\d+\.\d+\.\d+)-build([1-9]\d*)\.apk')
BASE_URL = 'https://vps.coffeybean.com/recipes/android'


def digest(stream):
    value = hashlib.sha256()
    while chunk := stream.read(1024 * 1024):
        value.update(chunk)
    return value.hexdigest()


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


def verify_download(url, expected):
    with urllib.request.build_opener(NoRedirect).open(url, timeout=120) as response:
        if response.status != 200 or response.headers.get_content_type() != 'application/vnd.android.package-archive':
            raise ValueError('APK download requires HTTPS 200 and the Android APK MIME type')
        if digest(response) != expected:
            raise ValueError('Public APK checksum does not match the verified package')


def switch_latest(directory, target):
    temporary = directory / '.latest-new'
    temporary.unlink(missing_ok=True)
    temporary.symlink_to(target)
    temporary.replace(directory / 'latest.apk')


def send_update(service_account, version, build):
    """Use the existing Firebase service identity without logging secrets."""
    key = json.loads(service_account.read_text())
    if key.get('project_id') != 'coffey-table-recipes':
        raise ValueError('Wrong Firebase push project')
    def encode(value):
        return base64.urlsafe_b64encode(value).rstrip(b'=')
    now = int(time.time())
    claims = dict(iss=key['client_email'],
                  scope='https://www.googleapis.com/auth/firebase.messaging',
                  aud='https://oauth2.googleapis.com/token', iat=now, exp=now + 3600)
    unsigned = b'.'.join(encode(json.dumps(value).encode()) for value in
                         ({'alg': 'RS256', 'typ': 'JWT'}, claims))
    with tempfile.TemporaryDirectory() as private:
        path = Path(private) / 'key.pem'
        path.write_text(key['private_key'])
        path.chmod(0o600)
        signed = subprocess.run(['openssl', 'dgst', '-sha256', '-sign', str(path)],
                                input=unsigned, capture_output=True, check=True).stdout
    assertion = (unsigned + b'.' + encode(signed)).decode()
    request = urllib.request.Request('https://oauth2.googleapis.com/token',
        data=urllib.parse.urlencode(dict(grant_type='urn:ietf:params:oauth:grant-type:jwt-bearer',
                                         assertion=assertion)).encode())
    with urllib.request.urlopen(request, timeout=30) as response:
        token = json.load(response)['access_token']
    message = dict(topic='android_releases', data=dict(kind='android_update',
                   version=version, build=str(build)),
                   android=dict(priority='HIGH', ttl='86400s', collapse_key='android_update'))
    request = urllib.request.Request(
        'https://fcm.googleapis.com/v1/projects/coffey-table-recipes/messages:send',
        data=json.dumps(dict(message=message)).encode(),
        headers={'Authorization': 'Bearer ' + token, 'Content-Type': 'application/json'})
    with urllib.request.urlopen(request, timeout=30) as response:
        if response.status != 200:
            raise RuntimeError('Update push failed; retry publication')


def write_json(path, value):
    temporary = path.with_name('.' + path.name + '-new')
    temporary.write_text(json.dumps(value) + '\n')
    temporary.chmod(0o644)
    temporary.replace(path)


def publish(apk, version, build, expected, directory, base_url=BASE_URL, *, notify):
    filename = f'CoffeyTableRecipes-{version}-build{build}.apk'
    if not RELEASE.fullmatch(filename) or not re.fullmatch(r'[a-f0-9]{64}', expected):
        raise ValueError('Invalid release version, build or SHA-256')
    with apk.open('rb') as source:
        if digest(source) != expected:
            raise ValueError('Source APK checksum mismatch')
    with zipfile.ZipFile(apk) as package:
        if 'AndroidManifest.xml' not in package.namelist():
            raise ValueError('Source is not an Android package')

    directory.mkdir(parents=True, exist_ok=True)
    with (directory.parent / '.publish.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        latest = directory / 'latest.apk'
        previous = os.readlink(latest) if latest.is_symlink() else None
        if latest.exists() and previous is None:
            raise ValueError('Existing latest.apk must be reviewed before replacement')
        if previous:
            current = RELEASE.fullmatch(previous)
            if not current or int(current[2]) > build:
                raise ValueError('Refusing to replace an invalid or newer release link')

        destination = directory / filename
        if destination.exists():
            with destination.open('rb') as existing:
                if digest(existing) != expected:
                    raise ValueError('Published release filename already has different contents')
        else:
            descriptor, temporary = tempfile.mkstemp(prefix='.upload-', dir=directory)
            staged = Path(temporary)
            try:
                with os.fdopen(descriptor, 'wb') as target, apk.open('rb') as source:
                    shutil.copyfileobj(source, target)
                with staged.open('rb') as target:
                    if digest(target) != expected:
                        raise ValueError('Staged APK checksum mismatch')
                staged.chmod(0o644)
                staged.replace(destination)
            finally:
                staged.unlink(missing_ok=True)

        verify_download(f'{base_url}/{filename}', expected)
        switch_latest(directory, filename)
        try:
            verify_download(f'{base_url}/latest.apk', expected)
        except Exception:
            if previous:
                switch_latest(directory, previous)
            else:
                latest.unlink(missing_ok=True)
            raise

        # Advertise only after both public downloads have passed verification.
        release = dict(version=version, build=build, url=f'{base_url}/latest.apk', sha256=expected)
        write_json(directory / 'latest.json', release)
        receipt = directory.parent / '.android-update-sent.json'
        sent = json.loads(receipt.read_text()) if receipt.exists() else None
        if sent != release:
            notify(version, build)
            write_json(receipt, release)

        removed = []
        for path in directory.iterdir():
            old = RELEASE.fullmatch(path.name)
            if old and path.name != filename and int(old[2]) < build:
                path.unlink()
                removed.append(path.name)
        return dict(url=f'{base_url}/latest.apk', filename=filename,
                    sha256=expected, removed=sorted(removed))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apk', required=True, type=Path)
    parser.add_argument('--version', required=True)
    parser.add_argument('--build', required=True, type=int)
    parser.add_argument('--sha256', required=True)
    parser.add_argument('--directory', type=Path, default=Path('/opt/services/ctr-downloads/public'))
    parser.add_argument('--service-account', required=True, type=Path,
                        help='Private Firebase messaging service account JSON (never in public/)')
    args = parser.parse_args()
    if args.service_account.resolve().is_relative_to(args.directory.resolve()):
        parser.error('Service account must be outside the public download directory')
    print(json.dumps(publish(args.apk, args.version, args.build, args.sha256, args.directory,
                             notify=lambda version, build: send_update(args.service_account, version, build)), indent=2))
