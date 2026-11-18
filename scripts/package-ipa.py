#!/usr/bin/env python3
"""Package a built Paper.app as a SideStore-ready IPA.

The archive holds exactly one Payload/Paper.app and no macOS metadata
(._* AppleDouble files, .DS_Store, __MACOSX). SideStore can mistake
Payload/._Paper.app for the app, so avoid `ditto -c -k --sequesterRsrc`.
"""
import argparse, os, pathlib, plistlib, tempfile, zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
DEFAULT_APP = ROOT / 'build-device/Build/Products/Debug-iphoneos/Paper.app'


def junk(part):
    return part.startswith('._') or part in ('.DS_Store', '__MACOSX')


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('output', type=pathlib.Path, help='Destination .ipa path')
    parser.add_argument('--app', type=pathlib.Path, default=DEFAULT_APP, help=f'Built app bundle (default: {DEFAULT_APP.relative_to(ROOT)})')
    parser.add_argument('--bundle-id', default=os.environ.get('PAPER_BUNDLE_ID', 'com.aayush.paper.reader'))
    args = parser.parse_args()
    app, target = args.app.resolve(), args.output.resolve()
    if not (app / 'Info.plist').is_file():
        parser.error(f'No built app at {app}')
    target.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(dir=target.parent, suffix='.ipa')
    os.close(fd)
    staging = pathlib.Path(name)
    try:
        with zipfile.ZipFile(staging, 'w', zipfile.ZIP_DEFLATED) as archive:
            for file in sorted(app.rglob('*')):
                relative = file.relative_to(app)
                if file.is_file() and not any(junk(part) for part in relative.parts):
                    archive.write(file, pathlib.PurePosixPath('Payload/Paper.app', *relative.parts))
        with zipfile.ZipFile(staging) as archive:
            assert archive.testzip() is None, 'corrupt archive'
            paths = [pathlib.PurePosixPath(n) for n in archive.namelist()]
            assert {p.parts[:2] for p in paths} == {('Payload', 'Paper.app')}, 'unexpected top-level entries'
            assert not any(junk(part) for p in paths for part in p.parts), 'macOS metadata in archive'
            info = plistlib.loads(archive.read('Payload/Paper.app/Info.plist'))
            assert info['CFBundleIdentifier'] == args.bundle_id, f"bundle ID {info['CFBundleIdentifier']} != {args.bundle_id}"
            executable = info['CFBundleExecutable']
            assert archive.read(f'Payload/Paper.app/{executable}') == (app / executable).read_bytes()
        os.replace(staging, target)
        print(f'{target}: {len(paths)} entries, {target.stat().st_size} bytes, bundle {args.bundle_id}')
    finally:
        staging.unlink(missing_ok=True)


if __name__ == '__main__':
    main()
