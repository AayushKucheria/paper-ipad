#!/usr/bin/env python3
"""Copy ANTHROPIC_API_KEY from ignored .env into Paper's one-time Keychain import."""
import os, pathlib, subprocess, tempfile
root = pathlib.Path(__file__).resolve().parents[1]
key = None
for line in (root / '.env').read_text().splitlines():
    name, separator, value = line.partition('=')
    if name.strip() == 'ANTHROPIC_API_KEY':
        key = value.strip().strip('\"\'')
if not key:
    raise SystemExit('ANTHROPIC_API_KEY is missing from .env')
fd, filename = tempfile.mkstemp(prefix='paper-anthropic-', suffix='.credential')
try:
    with os.fdopen(fd, 'w') as stream:
        stream.write(key)
    subprocess.run(['xcrun','devicectl','device','copy','to','--device','<your-device-udid>',
        '--source',filename,'--destination','tmp/anthropic-key.txt','--domain-type','appDataContainer',
        '--domain-identifier','com.aayush.paper.reader'],check=True)
    print('Copied the one-time credential. Relaunch Paper to move it into Keychain and delete the import file.')
finally:
    pathlib.Path(filename).unlink(missing_ok=True)
