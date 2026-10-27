import importlib.util
import json
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('devmeter_release', Path(__file__).with_name('release.py'))
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ReleaseArtifactTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.app = Path(self.temp.name) / 'DevMeter.app'
        resources = self.app / 'Contents/Resources'
        resources.mkdir(parents=True)
        self.info = {'CFBundleIdentifier': release.BUNDLE_ID, 'CFBundleShortVersionString': '0.2.0',
                     'CFBundleVersion': '2', 'LSMinimumSystemVersion': '14.0', 'CFBundleExecutable': 'DevMeter'}
        (self.app / 'Contents/Info.plist').write_bytes(plistlib.dumps(self.info))
        (resources / 'PrivacyInfo.xcprivacy').write_bytes(plistlib.dumps({'NSPrivacyTracking': False}))
        widget = self.app / 'Contents/PlugIns/DevMeterWidget.appex/Contents/Resources'
        widget.mkdir(parents=True)
        (widget / 'PrivacyInfo.xcprivacy').write_bytes(plistlib.dumps({'NSPrivacyTracking': False}))

    def test_unsigned_candidate_is_never_reported_as_release_accepted(self):
        with patch.object(release.subprocess, 'check_output', return_value='arm64 x86_64'):
            report = release.inspect_app(self.app)
        self.assertFalse(report['releaseAccepted'])
        self.assertFalse(report['signedDistributionVerified'])

    def test_app_store_artifact_rejects_sparkle(self):
        (self.app / 'Contents/Frameworks/Sparkle.framework').mkdir(parents=True)
        with self.assertRaisesRegex(ValueError, 'Sparkle'): release.inspect_app(self.app)

    def test_app_store_artifact_rejects_shipped_test_products(self):
        (self.app / 'Contents/Resources/DevMeter.storekit').write_text('{}')
        with self.assertRaisesRegex(ValueError, 'test configuration'): release.inspect_app(self.app)

    def test_app_store_artifact_rejects_wrong_bundle_identity(self):
        self.info['CFBundleIdentifier'] = 'invalid.app'
        (self.app / 'Contents/Info.plist').write_bytes(plistlib.dumps(self.info))
        with self.assertRaisesRegex(ValueError, 'bundle identifier'): release.inspect_app(self.app)

    def test_app_store_artifact_requires_both_architectures(self):
        with patch.object(release.subprocess, 'check_output', return_value='arm64'):
            with self.assertRaisesRegex(ValueError, 'both arm64'): release.inspect_app(self.app)

    def test_app_store_artifact_requires_widget_privacy_manifest(self):
        (self.app / 'Contents/PlugIns/DevMeterWidget.appex/Contents/Resources/PrivacyInfo.xcprivacy').unlink()
        with self.assertRaisesRegex(ValueError, 'manifest'): release.inspect_app(self.app)


if __name__ == '__main__': unittest.main()
