"""Upload only generated web assets using a cPanel API token from the environment."""
import hashlib
import json
import os
from pathlib import Path
import sys
import zipfile

import requests

HOST = 'https://ecngx362.inmotionhosting.com:2083'
DIRECTORY = '/home/' + os.environ.get('CPANEL_USER', 'hosting_account') + '/coffeybean.com/CoffeyTableRecipes'
PUBLIC = 'https://coffeybean.com/CoffeyTableRecipes/app/'

def deploy():
    root = Path('build/web')
    expected = json.loads((root / 'version.json').read_text(encoding='utf-8-sig'))
    archive = Path('build') / f"web-{expected['commit']}.zip"
    with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as output:
        for path in root.rglob('*'):
            if path.is_file():
                output.write(path, 'app/' + path.relative_to(root).as_posix())
    session = requests.Session()
    session.headers['Authorization'] = f"cpanel {os.environ['CPANEL_USER']}:{os.environ['CPANEL_API_TOKEN']}"
    print('Uploading generated web archive', flush=True)
    with archive.open('rb') as stream:
        response = session.post(HOST + '/execute/Fileman/upload_files', data={'dir': DIRECTORY, 'overwrite': '1'}, files={'file-1': (archive.name, stream, 'application/zip')}, timeout=180)
    response.raise_for_status()
    upload_result = response.json()
    if upload_result.get('status', upload_result.get('result', {}).get('status')) != 1:
        raise RuntimeError('cPanel upload failed; credential and response details omitted')
    print('Extracting uploaded web archive', flush=True)
    response = session.post(HOST + '/json-api/cpanel', data={'cpanel_jsonapi_user': os.environ['CPANEL_USER'], 'cpanel_jsonapi_apiversion': '2', 'cpanel_jsonapi_module': 'Fileman', 'cpanel_jsonapi_func': 'fileop', 'op': 'extract', 'sourcefiles': DIRECTORY + '/' + archive.name, 'destfiles': DIRECTORY, 'doubledecode': '1'}, timeout=180)
    response.raise_for_status()
    result = response.json()['cpanelresult']
    if result.get('event', {}).get('result') != 1 or any(item.get('result') == 0 for item in result.get('data', [])):
        raise RuntimeError('cPanel extraction failed; response details omitted')
    destinations = [item.get('dest', '') for item in result.get('data', [])]
    if not destinations or any(path.rstrip('/') != DIRECTORY for path in destinations):
        raise RuntimeError('cPanel did not confirm the intended extraction directory')
    print('Verifying public deployment metadata and asset hashes', flush=True)
    # Public checks use a separate unauthenticated client: never send the token to the site.
    response = requests.get(PUBLIC + 'version.json', params={'commit': expected['commit']}, timeout=60)
    response.raise_for_status()
    if response.json() != expected:
        raise RuntimeError('Hosted source metadata does not match this deployment')
    for name in ('main.dart.js', 'flutter_bootstrap.js', 'assets/FontManifest.json'):
        response = requests.get(PUBLIC + name, params={'commit': expected['commit']}, timeout=60)
        response.raise_for_status()
        if hashlib.sha256(response.content).digest() != hashlib.sha256((root / name).read_bytes()).digest():
            raise RuntimeError(f'Hosted asset mismatch: {name}')
    print(f"Verified hosted web {expected['version']} build {expected['build']} at {expected['commit']}")

if __name__ == '__main__':
    try:
        deploy()
    except Exception as error:
        # Avoid printing request objects or credential-bearing headers.
        detail = str(error) if type(error) is RuntimeError else type(error).__name__
        print(f'Deployment failed: {detail}. Credentials are not logged.', file=sys.stderr)
        sys.exit(1)
