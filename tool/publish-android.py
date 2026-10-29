"""Upload a verified release APK to Google Drive before trashing older releases."""
import argparse
import base64
import configparser
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile
import time
import urllib.parse
import urllib.request
import zipfile

RELEASE = re.compile(r'CoffeyTableRecipes-(\d+\.\d+\.\d+)-build([1-9]\d*)\.apk')


def digest(stream):
    value = hashlib.sha256()
    while chunk := stream.read(1024 * 1024):
        value.update(chunk)
    return value.hexdigest()


class Drive:
    def __init__(self, rclone, config, remote, folder_id):
        if not re.fullmatch(r'[A-Za-z0-9_-]+', remote):
            raise ValueError('Use a configured remote name without a colon or path')
        if not re.fullmatch(r'[A-Za-z0-9_-]{10,}', folder_id):
            raise ValueError('A Google Drive destination folder ID is required')
        settings = configparser.ConfigParser(interpolation=None)
        with Path(config).open() as private:
            settings.read_file(private)
        if (not settings.has_section(remote) or
                settings.get(remote, 'type', fallback='') != 'drive' or
                settings.get(remote, 'scope', fallback='').strip() not in
                ('drive.file', 'https://www.googleapis.com/auth/drive.file')):
            raise ValueError('Google Drive publication requires a drive.file-only OAuth configuration')
        configured_folder = settings.get(remote, 'root_folder_id', fallback='').strip()
        if not configured_folder:
            raise ValueError('Pin the authorized recipe folder in the private root_folder_id configuration')
        if configured_folder != folder_id:
            raise ValueError('Destination differs from the authorized recipe folder configuration')
        self.root = remote + ':'
        self.command = [str(rclone), '--config', str(config),
                        '--drive-root-folder-id', folder_id, '--drive-scope', 'drive.file',
                        '--drive-use-trash=true', '--contimeout', '15s', '--timeout', '60s']

    def run(self, *arguments):
        result = subprocess.run(self.command + list(arguments), capture_output=True,
                                text=True, timeout=600)
        if result.returncode:
            raise RuntimeError('Google Drive operation failed; check private rclone configuration and access')
        return result.stdout

    def files(self):
        return json.loads(self.run('lsjson', self.root, '--files-only', '--max-depth', '1'))

    def upload(self, apk, filename):
        self.run('copyto', str(apk), self.root + filename, '--immutable')

    def sha256(self, filename):
        with subprocess.Popen(self.command + ['cat', self.root + filename],
                              stdout=subprocess.PIPE, stderr=subprocess.DEVNULL) as process:
            value = digest(process.stdout)
            if process.wait(timeout=600):
                raise RuntimeError('Could not verify the uploaded Google Drive APK')
            return value

    def trash(self, filename):
        self.run('deletefile', self.root + filename)


def release_files(rows):
    releases = {}
    for row in rows:
        name = row['Name']
        if RELEASE.fullmatch(name) and not row.get('IsDir', False):
            if name in releases:
                raise ValueError('Duplicate release filenames in Drive require review before publication')
            releases[name] = row
    return releases


def send_update(service_account, version, build, *, validate_only=False):
    """Send an Android-only release hint using the private messaging identity."""
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
    payload = dict(message=message)
    if validate_only:
        payload['validate_only'] = True
    request = urllib.request.Request(
        'https://fcm.googleapis.com/v1/projects/coffey-table-recipes/messages:send',
        data=json.dumps(payload).encode(),
        headers={'Authorization': 'Bearer ' + token, 'Content-Type': 'application/json'})
    with urllib.request.urlopen(request, timeout=30) as response:
        if response.status != 200:
            raise RuntimeError('Release notification failed; retry publication')


def notify_release(version, build, expected, receipt, notify):
    release = dict(version=version, build=build, sha256=expected)
    sent = json.loads(receipt.read_text()) if receipt.exists() else None
    if sent == release:
        return False
    if sent and int(sent['build']) >= build:
        raise ValueError('Notification receipt contains a newer or conflicting release')
    notify(version, build)
    receipt.parent.mkdir(parents=True, exist_ok=True)
    temporary = receipt.with_name('.' + receipt.name + '-new')
    temporary.write_text(json.dumps(release) + '\n')
    temporary.chmod(0o600)
    temporary.replace(receipt)
    return True


def publish(apk, version, build, expected, drive, *, notify, receipt):
    filename = f'CoffeyTableRecipes-{version}-build{build}.apk'
    if not RELEASE.fullmatch(filename) or not re.fullmatch(r'[a-f0-9]{64}', expected):
        raise ValueError('Invalid release version, build or SHA-256')
    with apk.open('rb') as source:
        if digest(source) != expected:
            raise ValueError('Source APK checksum mismatch')
    with zipfile.ZipFile(apk) as package:
        if 'AndroidManifest.xml' not in package.namelist():
            raise ValueError('Source is not an Android package')

    releases = release_files(drive.files())
    for name in releases:
        current = RELEASE.fullmatch(name)
        if int(current[2]) > build or (int(current[2]) == build and name != filename):
            raise ValueError('Refusing to replace a newer or conflicting release')
    if filename not in releases:
        drive.upload(apk, filename)
    # Download and hash the actual Drive bytes, including on idempotent retries.
    if drive.sha256(filename) != expected:
        raise ValueError('Google Drive APK checksum mismatch; older releases retained')
    uploaded = release_files(drive.files()).get(filename)
    if not uploaded or not re.fullmatch(r'[A-Za-z0-9_-]+', uploaded.get('ID', '')):
        raise ValueError('Could not identify the verified Drive file; older releases retained')

    notified = notify_release(version, build, expected, receipt, notify)
    removed = []
    for name in releases:
        if int(RELEASE.fullmatch(name)[2]) < build:
            drive.trash(name)
            removed.append(name)
    remaining = release_files(drive.files())
    if filename not in remaining or any(name in remaining for name in removed):
        raise ValueError('Drive cleanup could not be confirmed; inspect destination before retrying')
    return dict(filename=filename, sha256=expected, removed=sorted(removed), notified=notified,
                url=f'https://drive.google.com/file/d/{uploaded["ID"]}/view')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apk', required=True, type=Path)
    parser.add_argument('--version', required=True)
    parser.add_argument('--build', required=True, type=int)
    parser.add_argument('--sha256', required=True)
    parser.add_argument('--folder-id', required=True, help='ID of the existing recipe app folder')
    parser.add_argument('--remote', default='ctr-drive')
    tools = Path('/home/debian/projects/.release-tools')
    parser.add_argument('--rclone', type=Path, default=tools / 'rclone')
    parser.add_argument('--config', type=Path, default=tools / 'credentials/rclone.conf')
    parser.add_argument('--service-account', type=Path, default=tools / 'credentials/timer-push.local.json')
    parser.add_argument('--notification-receipt', type=Path, default=tools / 'android-release-notifications.json')
    args = parser.parse_args()
    try:
        drive = Drive(args.rclone, args.config, args.remote, args.folder_id)
        print(json.dumps(publish(args.apk, args.version, args.build, args.sha256, drive,
            notify=lambda version, build: send_update(args.service_account, version, build),
            receipt=args.notification_receipt), indent=2))
    except (ValueError, RuntimeError, OSError, configparser.Error, zipfile.BadZipFile, subprocess.SubprocessError) as error:
        parser.exit(1, f'Publication failed: {error}\n')
