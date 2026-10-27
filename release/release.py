#!/usr/bin/env python3
"""DevMeter Mac App Store build preparation. No uploads, credentials, or fake release success."""
import argparse
import json
from pathlib import Path
import plistlib
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
BUNDLE_ID = 'com.zhaobinrui.devspace.meter'
PRODUCT_ID = BUNDLE_ID + '.pro.lifetime'


def run(arguments, **kwargs):
    # Keep executable and arguments separate; never evaluate operator input in a shell.
    return subprocess.run(arguments, check=True, text=True, **kwargs)


def preflight():
    identities = subprocess.run(['/usr/bin/security', 'find-identity', '-v', '-p', 'codesigning'], capture_output=True, text=True)
    has_distribution = any(name in identities.stdout for name in ['Apple Distribution:', '3rd Party Mac Developer Application:'])
    dirty = bool(subprocess.check_output(['/usr/bin/git', '-C', str(ROOT), 'status', '--porcelain'], text=True))
    return {
        'schemaVersion': 1, 'channel': 'mac-app-store', 'scheme': 'DevMeterAppStore',
        'productID': PRODUCT_ID, 'targetPrice': {'currency': 'CNY', 'amount': '58.00', 'type': 'non-consumable'},
        'releaseAccepted': False,
        'checks': [
            {'id': 'distribution-signing', 'passed': has_distribution, 'detail': 'Requires an installed Mac App Store distribution identity and provisioning profiles.'},
            {'id': 'clean-source', 'passed': not dirty, 'detail': 'Archive an exact committed source revision.'},
            {'id': 'app-store-connect-product', 'passed': False, 'detail': 'Create/verify the non-consumable product and the mainland China CNY 58 price in App Store Connect.'},
            {'id': 'sandbox-codex-data', 'passed': False, 'detail': 'Real signed sandbox execution and authorized Codex account data access are not yet accepted.'},
            {'id': 'commercial-data-source', 'passed': False, 'detail': 'Confirm permitted commercial use of the current Codex app-server authentication/data source.'},
            {'id': 'real-store-sandbox-payment', 'passed': False, 'detail': 'Xcode local StoreKit tests do not establish App Store Connect sandbox or production payment acceptance.'},
            {'id': 'macos-14-runtime', 'passed': False, 'detail': 'Requires execution on macOS 14, not merely a deployment target check.'},
        ],
    }


def inspect_app(app, signed=False):
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    if info.get('CFBundleIdentifier') != BUNDLE_ID:
        raise ValueError('Unexpected main bundle identifier')
    if info.get('LSMinimumSystemVersion') not in ['14.0', '14.0.0']:
        raise ValueError('Unexpected minimum macOS version')
    if list(app.rglob('Sparkle.framework')):
        raise ValueError('App Store build must not include Sparkle')
    if list(app.rglob('*.storekit')):
        raise ValueError('Local StoreKit test configuration must not ship')
    for bundle in [app, app / 'Contents/PlugIns/DevMeterWidget.appex']:
        if not (bundle / 'Contents/Resources/PrivacyInfo.xcprivacy').is_file():
            raise ValueError('Privacy manifest is missing from ' + bundle.name)
    executable = app / 'Contents/MacOS' / info['CFBundleExecutable']
    archs = subprocess.check_output(['/usr/bin/lipo', '-archs', str(executable)], text=True).split()
    if not {'arm64', 'x86_64'}.issubset(archs):
        raise ValueError('Candidate must contain both arm64 and x86_64')
    if signed:
        run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(app)])
        for bundle in [app, app / 'Contents/PlugIns/DevMeterWidget.appex']:
            raw = subprocess.check_output(['/usr/bin/codesign', '-d', '--entitlements', ':-', str(bundle)], stderr=subprocess.DEVNULL)
            entitlements = plistlib.loads(raw)
            if entitlements.get('com.apple.security.app-sandbox') is not True:
                raise ValueError('App Sandbox is not enabled: ' + bundle.name)
            metadata = subprocess.check_output(['/usr/bin/codesign', '-dvv', str(bundle)], stderr=subprocess.STDOUT, text=True)
            if not any(identity in metadata for identity in ['Authority=Apple Distribution:', 'Authority=3rd Party Mac Developer Application:']):
                raise ValueError('Not signed with an App Store distribution certificate')
    return {'bundleID': info['CFBundleIdentifier'], 'version': info['CFBundleShortVersionString'],
            'build': info['CFBundleVersion'], 'architectures': archs, 'signedDistributionVerified': signed,
            'noSparkle': True, 'noStoreKitTestFixtures': True, 'privacyManifestsPresent': True,
            'releaseAccepted': False}


def candidate(args):
    output = args.output.resolve()
    if output.exists():
        raise ValueError('Output directory already exists; refusing to overwrite')
    if not str(args.derived_data.resolve()).startswith('/private/tmp/'):
        raise ValueError('Derived Data must be under /private/tmp')
    output.mkdir(parents=True)
    log = output / 'build.log'
    command = ['xcodebuild', '-project', str(ROOT / 'DevMeter.xcodeproj'), '-scheme', 'DevMeterAppStore',
               '-configuration', 'Release', '-destination', 'generic/platform=macOS',
               '-derivedDataPath', str(args.derived_data), '-disableAutomaticPackageResolution',
               'CODE_SIGNING_ALLOWED=NO', 'ARCHS=arm64 x86_64', 'ONLY_ACTIVE_ARCH=NO', 'build']
    with log.open('w') as handle:
        run(command, stdout=handle, stderr=subprocess.STDOUT)
    built = args.derived_data / 'Build/Products/Release/DevMeterAppStore.app'
    app = output / 'DevMeter.app'
    run(['/usr/bin/ditto', str(built), str(app)])
    report = inspect_app(app)
    report['kind'] = 'unsigned-engineering-candidate'
    (output / 'candidate-report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))


def archive(args):
    if not str(args.derived_data.resolve()).startswith('/private/tmp/'):
        raise ValueError('Derived Data must be under /private/tmp')
    report = preflight()
    # The archive is only preparation; commercial, sandbox and payment acceptance remain explicit human evidence.
    if not all(check['passed'] for check in report['checks'] if check['id'] in ['distribution-signing', 'clean-source']):
        print(json.dumps(report, indent=2))
        raise ValueError('Signing or committed-source prerequisite is missing')
    if not re.fullmatch(r'[A-Z0-9]{10}', args.team_id):
        raise ValueError('Invalid Apple team identifier')
    output = args.output.resolve()
    if output.exists(): raise ValueError('Output directory already exists')
    output.mkdir(parents=True)
    archive_path = output / 'DevMeter.xcarchive'
    run(['xcodebuild', '-project', str(ROOT / 'DevMeter.xcodeproj'), '-scheme', 'DevMeterAppStore',
         '-configuration', 'Release', '-destination', 'generic/platform=macOS',
         '-derivedDataPath', str(args.derived_data), '-archivePath', str(archive_path),
         'DEVELOPMENT_TEAM=' + args.team_id, 'ARCHS=arm64 x86_64', 'ONLY_ACTIVE_ARCH=NO', 'archive'])
    options = {'method': 'app-store-connect', 'destination': 'export', 'teamID': args.team_id,
               'signingStyle': 'automatic', 'uploadSymbols': True}
    options_path = output / 'ExportOptions.plist'
    options_path.write_bytes(plistlib.dumps(options))
    run(['xcodebuild', '-exportArchive', '-archivePath', str(archive_path), '-exportPath', str(output / 'export'),
         '-exportOptionsPlist', str(options_path)])
    print('Archive/export prepared. No App Store upload or publication was performed.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='operation', required=True)
    sub.add_parser('preflight')
    for name in ['candidate', 'archive']:
        item = sub.add_parser(name)
        item.add_argument('--output', type=Path, required=True)
        item.add_argument('--derived-data', type=Path, default=Path('/private/tmp/DevMeterPhase1DerivedData'))
        if name == 'archive': item.add_argument('--team-id', required=True)
    verify = sub.add_parser('verify')
    verify.add_argument('app', type=Path)
    verify.add_argument('--signed', action='store_true')
    args = parser.parse_args()
    try:
        if args.operation == 'preflight':
            print(json.dumps(preflight(), indent=2))
            return 2
        if args.operation == 'candidate': candidate(args)
        elif args.operation == 'archive': archive(args)
        elif args.operation == 'verify': print(json.dumps(inspect_app(args.app, args.signed), indent=2))
        return 0
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print('Release preparation failed: ' + str(error), file=sys.stderr)
        return 1


if __name__ == '__main__': sys.exit(main())
