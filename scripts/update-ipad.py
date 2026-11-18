#!/usr/bin/env python3
"""Back up, build, install in place, and verify Paper's library. Never uninstalls."""
import argparse, os, datetime, hashlib, json, pathlib, plistlib, shutil, subprocess, sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
DEVICE = os.environ.get('PAPER_DEVICE_UDID', '')
TEAM = os.environ.get('PAPER_TEAM_ID', '')
BUNDLE = os.environ.get('PAPER_BUNDLE_ID', 'com.aayush.paper.reader')
APP = ROOT / 'build-device/Build/Products/Debug-iphoneos/Paper.app'

def run(*args, **kwargs):
    return subprocess.run(args, check=True, cwd=ROOT, **kwargs)

def copy_documents(destination):
    run('xcrun', 'devicectl', 'device', 'copy', 'from', '--device', DEVICE,
        '--source', 'Documents', '--destination', str(destination),
        '--domain-type', 'appDataContainer', '--domain-identifier', BUNDLE)

def manifest(root):
    library = root / 'Library'
    if not library.is_dir():
        raise RuntimeError('Backup has no Library directory. Stopping before installation.')
    result = {}
    for path in sorted(root.rglob('*')):
        if path.is_file():
            digest = hashlib.sha256()
            with path.open('rb') as stream:
                for block in iter(lambda: stream.read(1024 * 1024), b''):
                    digest.update(block)
            result[str(path.relative_to(root))] = digest.hexdigest()
    if not any(name.startswith('Library/') and name.endswith('/document.json') for name in result):
        raise RuntimeError('Backup contains no document records. Stopping before installation.')
    return result

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--renew-signing', action='store_true', help='Request fresh automatic provisioning and require a later expiry before installing')
    args = parser.parse_args()
    if not DEVICE or not TEAM:
        parser.error('Set PAPER_DEVICE_UDID and PAPER_TEAM_ID before updating a device')
    stamp = datetime.datetime.now().strftime('%Y-%m-%d-%H%M%S')
    backup = pathlib.Path.home() / 'Documents/Paper Backups' / stamp
    backup.mkdir(parents=True, mode=0o700)
    print(f'Backup: {backup}\nKeep the iPad unlocked and finish any Markup edits before continuing.', flush=True)
    copy_documents(backup / 'before')
    before = manifest(backup / 'before')
    (backup / 'library-sha256.json').write_text(json.dumps(before, indent=2) + '\n')
    old_expiry = None
    if args.renew_signing:
        # Move only this app's cached profile; keep it for recovery. No certificates
        # or profiles on the iPad are removed.
        profile_backup = backup / 'previous-profiles'
        profile_backup.mkdir(mode=0o700)
        for cache in (pathlib.Path.home() / 'Library/Developer/Xcode/UserData/Provisioning Profiles',
                      pathlib.Path.home() / 'Library/MobileDevice/Provisioning Profiles'):
            for cached in cache.glob('*.mobileprovision'):
                decoded = plistlib.loads(run('security', 'cms', '-D', '-i', str(cached), capture_output=True).stdout)
                if decoded.get('Entitlements', {}).get('application-identifier') == f'{TEAM}.{BUNDLE}':
                    expiry = decoded['ExpirationDate']
                    old_expiry = max(old_expiry, expiry) if old_expiry else expiry
                    shutil.move(str(cached), str(profile_backup / cached.name))
        if old_expiry is None:
            raise RuntimeError('No existing app profile found to establish the renewal baseline.')
        print(f'Requesting automatic provisioning; previous expiry {old_expiry} UTC.', flush=True)
    print(f'Backed up {len(before)} document files. Building…', flush=True)
    with (backup / 'build.log').open('w') as log:
        run('xcodebuild', *(['clean', 'build'] if args.renew_signing else ['build']), '-project', 'Paper.xcodeproj', '-scheme', 'Paper',
            '-destination', f'id={DEVICE}', '-derivedDataPath', 'build-device',
            '-allowProvisioningUpdates', '-allowProvisioningDeviceRegistration', stdout=log, stderr=subprocess.STDOUT)
    with (APP / 'Info.plist').open('rb') as stream:
        info = plistlib.load(stream)
    if info['CFBundleIdentifier'] != BUNDLE:
        raise RuntimeError('Unexpected bundle ID. Refusing to install.')
    profile = plistlib.loads(run('security', 'cms', '-D', '-i', str(APP / 'embedded.mobileprovision'), capture_output=True).stdout)
    if profile['Entitlements']['application-identifier'] != f'{TEAM}.{BUNDLE}':
        raise RuntimeError('Unexpected signing identity. Refusing to install.')
    expiry = profile['ExpirationDate']
    if expiry <= datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None):
        raise RuntimeError('Signing profile has expired. Backup retained; refusing to install.')
    if args.renew_signing and expiry <= old_expiry:
        raise RuntimeError(f'Apple returned a profile expiring {expiry} UTC; signing was not renewed. Existing app is still installed.')
    print(f'Profile expires {expiry} UTC.' + (' Renewal verified.' if args.renew_signing else ' A rebuild does not necessarily renew the profile.'), flush=True)
    run('xcrun', 'devicectl', 'device', 'install', 'app', '--device', DEVICE, str(APP))
    # Compare before launching: startup can refresh the separately stored catalog.
    copy_documents(backup / 'after-install')
    after = manifest(backup / 'after-install')
    if before != after:
        raise RuntimeError(f'Documents changed. Backup retained at {backup}; do not overwrite or uninstall.')
    run('xcrun', 'devicectl', 'device', 'process', 'launch', '--device', DEVICE, BUNDLE)
    print(f'Installed in place. All {len(before)} document file hashes match. Backup: {backup}', flush=True)

if __name__ == '__main__':
    try:
        main()
    except (subprocess.CalledProcessError, OSError, RuntimeError) as error:
        print(f'Update stopped: {error}', file=sys.stderr)
        sys.exit(1)
