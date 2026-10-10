"""Prepare cache-safe web assets and source metadata after flutter build web."""
import hashlib
import json
from pathlib import Path
import re
import subprocess

root = Path('build/web')
manifest = root / 'assets/FontManifest.json'
families = json.loads(manifest.read_text(encoding='utf-8-sig'))
for family in families:
    for font in family['fonts']:
        source = root / 'assets' / font['asset']
        digest = hashlib.sha256(source.read_bytes()).hexdigest()[:12]
        target = source.with_name(f'{source.stem}-{digest}{source.suffix}')
        target.write_bytes(source.read_bytes())
        font['asset'] = target.relative_to(root / 'assets').as_posix()
manifest.write_text(json.dumps(families), encoding='utf-8')
(root / '.htaccess').write_text('<IfModule mod_headers.c>\nHeader set Cache-Control "no-store, max-age=0"\n</IfModule>\n')
version, build = re.search(r'^version: (\d+\.\d+\.\d+)\+(\d+)', Path('pubspec.yaml').read_text(), re.M).groups()
(root / 'version.json').write_text(json.dumps(dict(version=version, build=int(build), commit=subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(), channel='demonstration')), encoding='utf-8')
print(f'Prepared web {version} build {build}')
