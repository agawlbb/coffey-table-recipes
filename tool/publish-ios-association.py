"""Publish only this app's universal-link association, preserving other apps."""
import json
import os
import re
import requests

HOST = 'https://ecngx362.inmotionhosting.com:2083'
PUBLIC = 'https://coffeybean.com/.well-known/apple-app-site-association'


def main():
    team = os.environ['IOS_TEAM_ID']
    if not re.fullmatch(r'[A-Z0-9]{10}', team):
        raise ValueError('Invalid signing team')
    app = team + '.com.coffeytable.coffeyTableRecipes'
    root = '/home/' + os.environ['CPANEL_USER'] + '/coffeybean.com'
    session = requests.Session()
    session.headers['Authorization'] = f"cpanel {os.environ['CPANEL_USER']}:{os.environ['CPANEL_API_TOKEN']}"

    def api(module, operation, **params):
        response = session.get(f'{HOST}/execute/{module}/{operation}', params=params, timeout=60, allow_redirects=False)
        response.raise_for_status()
        result = response.json()
        if result.get('status') != 1:
            raise RuntimeError('cPanel operation failed; response omitted')
        return result['data']

    rows = api('LangPHP', 'php_get_vhost_versions')
    if not any(row.get('vhost') == 'coffeybean.com' and row.get('documentroot', '').rstrip('/') == root for row in rows):
        raise RuntimeError('Domain document root did not match')
    directory = root + '/.well-known'
    listing = api('Fileman', 'list_files', dir=directory)
    if not isinstance(listing, list) or any(not isinstance(row, dict) or not isinstance(row.get('file'), str) for row in listing):
        raise RuntimeError('Directory listing was incomplete; no changes made')
    names = {row.get('file') for row in listing}

    def read(name):
        return api('Fileman', 'get_file_content', dir=directory, file=name)['content'] if name in names else None

    def upload(name, content):
        response = session.post(HOST + '/execute/Fileman/upload_files', data={'dir': directory, 'overwrite': '1'},
            files={'file-1': (name, content.encode(), 'application/json')}, timeout=60, allow_redirects=False)
        response.raise_for_status()
        if response.json().get('status') != 1:
            raise RuntimeError('Association upload failed; response omitted')

    old = read('apple-app-site-association')
    data = json.loads(old) if old is not None else {}
    details = data.setdefault('applinks', {}).setdefault('details', [])
    if not isinstance(details, list):
        raise ValueError('Unexpected existing association structure')
    if not any((row.get('appID') == app or app in row.get('appIDs', [])) and
               (row.get('paths') == ['*'] or any(c.get('/') == '/CoffeyTableRecipes/share.php' for c in row.get('components', []))) for row in details):
        details.append({'appIDs': [app], 'components': [{'/': '/CoffeyTableRecipes/share.php'}]})
    upload('apple-app-site-association', json.dumps(data, indent=2) + '\n')
    response = requests.get(PUBLIC, timeout=60, allow_redirects=False)
    if response.headers.get('Content-Type', '').split(';')[0] != 'application/json':
        existing = read('.htaccess') or ''
        rule = '<Files "apple-app-site-association">\nForceType application/json\n</Files>\n'
        if rule not in existing:
            upload('.htaccess', existing + '\n' + rule)
        response = requests.get(PUBLIC, timeout=60, allow_redirects=False)
    if response.status_code != 200 or response.headers.get('Content-Type', '').split(';')[0] != 'application/json' or response.json() != data:
        raise RuntimeError('Public association verification failed')
    print('Verified iOS association with signing team, bundle identifier, HTTPS 200, JSON MIME and no redirect')


if __name__ == '__main__':
    main()
