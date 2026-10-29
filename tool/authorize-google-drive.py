"""One-time VPS OAuth consent using Google Picker and only drive.file.

Run on the VPS host. Forward loopback port 53682 for initial browser consent;
future publication uses the stored refresh token without a laptop.
Only the consent URL is printed. Credential output stays in memory/private config.
"""
import configparser
import json
import os
from pathlib import Path
import re
import subprocess
import sys

def main():
    root = Path('/home/debian/projects/.release-tools')
    config = root / 'credentials/rclone.conf'
    if config.exists():
        sys.exit('Private Drive configuration already exists; preserve it for inspection.')
    os.umask(0o077)
    auth_url = ('https://accounts.google.com/o/oauth2/v2/auth?prompt=consent'
                    '&trigger_onepick=true&allow_folder_selection=true&allow_multiple=true'
                    '&include_granted_scopes=false')
    command = [str(root / 'rclone'), 'authorize', 'drive', '--auth-no-open-browser',
               '--drive-scope', 'drive.file', '--drive-auth-url', auth_url]
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
    output = []
    for line in process.stdout:
        output.append(line)
        match = re.search(r'http://127\.0\.0\.1:53682/auth\?[^\s]+', line)
        if match:
            print('Browser authorization URL: ' + match.group(), flush=True)
            print('Waiting for owner Google consent through the SSH-forwarded callback. Tokens will be saved privately, never printed.', flush=True)
    if process.wait():
        sys.exit('Google authorization did not complete. Private process output omitted.')
    raw = ''.join(output)
    credential = None
    for match in re.finditer(r'\{', raw):
        try:
            value, _ = json.JSONDecoder().raw_decode(raw[match.start():])
            if isinstance(value, dict) and value.get('access_token') and value.get('refresh_token'):
                credential = value
                break
        except ValueError:
            continue
    if credential is None:
        sys.exit('No persistent OAuth credential returned. Private response omitted.')
    settings = configparser.ConfigParser(interpolation=None)
    settings['ctr-drive'] = {'type': 'drive', 'scope': 'drive.file', 'root_folder_id': '1VM1K1Ge6sgjEjtoEjS7aGzHYiSzlLVE-', 'token': json.dumps(credential)}
    with config.open('x') as file:
        settings.write(file)
    config.chmod(0o600)
    print('Google Drive OAuth saved privately with mode 600. No release has been uploaded or deleted.', flush=True)


if __name__ == '__main__':
    main()
