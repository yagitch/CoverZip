"""退避の内容照合、整理対象の限定、署名不一致と置換失敗時の保護を検証する。"""
from pathlib import Path
import importlib.util
import os
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('app_install', Path(__file__).resolve().parents[1] / 'tools/app_install.py')
app_install = importlib.util.module_from_spec(spec)
spec.loader.exec_module(app_install)


def bundle(path, version='51', identifier='com.dmng.CoverZip'):
    contents = path / 'Contents'
    contents.mkdir(parents=True)
    (contents / 'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': identifier, 'CFBundleVersion': version}))
    (contents / '日本語.txt').write_text('復元対象の本文')
    (contents / 'リンク').symlink_to('日本語.txt')
    return path


class AppInstallTests(unittest.TestCase):
    def test_archive_round_trip_and_unique_names(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = bundle(root / 'CoverZip.app')
            first = app_install.archive_bundle(source, root / 'archives')
            second = app_install.archive_bundle(source, root / 'archives')
            self.assertNotEqual(first, second)
            restored = root / 'restored'
            app_install.run('/usr/bin/ditto', '-x', '-k', first, restored)
            self.assertEqual((restored / 'CoverZip.app/Contents/日本語.txt').read_text(), '復元対象の本文')
            self.assertEqual((restored / 'CoverZip.app/Contents/リンク').readlink(), Path('日本語.txt'))
            (source / 'Contents/日本語.txt').write_text('変更後')
            with self.assertRaises(ValueError):
                app_install.verify_archive(source, first)
            self.assertTrue(source.exists())

    def test_cleanup_scope_and_dry_run(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            output = bundle(root / '.build-local/Build/Products/Release/CoverZip.app')
            old = bundle(root / '.local-backup/test/Old.app')
            other = bundle(root / '.local-backup/test/Other.app', identifier='example.other')
            outside = bundle(root / 'unmanaged/CoverZip.app')
            (root / '.local-backup/external.app').symlink_to(outside, target_is_directory=True)
            self.assertEqual(set(app_install.managed_apps(root)), {output, old})
            app_install.cleanup(root)
            self.assertTrue(output.exists() and old.exists() and other.exists() and outside.exists())
            current = bundle(root / 'installed/CoverZip.app')
            with patch.object(app_install, 'INSTALLED', current), patch.object(app_install, 'signature_team', return_value='team'), patch.object(app_install, 'archive_bundle', side_effect=ValueError('照合失敗')):
                with self.assertRaises(ValueError):
                    app_install.cleanup(root, apply=True)
            self.assertTrue(output.exists() and old.exists())

    def test_signature_mismatch_does_not_replace(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            current = bundle(root / 'installed/CoverZip.app', '50')
            source = bundle(root / 'source/CoverZip.app')
            with patch.object(app_install, 'INSTALLED', current), patch.object(app_install, 'signature_team', side_effect=['new-team', 'old-team']):
                with self.assertRaises(ValueError):
                    app_install.install(source)
            self.assertEqual(app_install.bundle_info(current)['CFBundleVersion'], '50')

    def test_failed_replacement_restores_previous(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            current = bundle(root / 'installed/CoverZip.app', '50')
            source = bundle(root / 'source/CoverZip.app')
            real_run = subprocess.run

            def mocked_process(args, **kwargs):
                if args[0] == '/usr/bin/pgrep':
                    return subprocess.CompletedProcess(args, 1)
                return real_run(args, **kwargs)

            with patch.object(app_install, 'ROOT', root), patch.object(app_install, 'INSTALLED', current), patch.object(app_install, 'signature_team', side_effect=['team', 'team', 'team', ValueError('置換後の署名検証失敗')]), patch.object(app_install.subprocess, 'run', side_effect=mocked_process):
                with self.assertRaises(ValueError):
                    app_install.install(source)
            self.assertEqual(app_install.bundle_info(current)['CFBundleVersion'], '50')
            self.assertTrue(list((root / '.local-backup/app-archives').glob('*.zip')))

    def test_install_then_cleanup_keeps_only_installed_app(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            current = bundle(root / 'installed/CoverZip.app', '50')
            source = bundle(root / '.build-test/Build/Products/Release/CoverZip.app')
            registered = [source, current]
            real_run = subprocess.run

            def system_process(args, **kwargs):
                if args[0] in ['/usr/bin/pgrep', '/bin/launchctl']:
                    return subprocess.CompletedProcess(args, 1)
                if args[0] == '/usr/bin/pluginkit':
                    return subprocess.CompletedProcess(args, 0, '', '')
                if args[0] == app_install.LSREGISTER:
                    if args[1] == '-dump':
                        output = '\n-----\n'.join(f'identifier: com.dmng.CoverZip\npath: {p} (0x123)' for p in registered)
                        return subprocess.CompletedProcess(args, 0, output, '')
                    if args[1] == '-u' and Path(args[2]) in registered:
                        registered.remove(Path(args[2]))
                    return subprocess.CompletedProcess(args, 0, '', '')
                return real_run(args, **kwargs)

            with patch.object(app_install, 'ROOT', root), patch.object(app_install, 'INSTALLED', current), patch.object(app_install, 'signature_team', return_value='team'), patch.object(app_install.subprocess, 'run', side_effect=system_process):
                app_install.install(source)
                app_install.cleanup(root, apply=True)
                self.assertEqual(app_install.registered_paths(), [current])
            self.assertEqual(app_install.bundle_info(current)['CFBundleVersion'], '51')
            self.assertFalse(source.exists())
            self.assertEqual(len(list((root / '.local-backup/app-archives').glob('*.zip'))), 2)

    def test_build_entry_runs_cleanup_even_on_failure(self):
        wrapper = Path(__file__).resolve().parents[1] / 'tools/build_coverzip.sh'
        for build_result in [0, 7]:
            with self.subTest(build_result=build_result), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                tools = root / 'tools'
                tools.mkdir()
                (tools / 'build_coverzip.sh').write_bytes(wrapper.read_bytes())
                (tools / 'app_install.py').write_text('import os,sys\nwith open(os.environ["COVERZIP_TEST_LOG"],"a") as f: print("installer",*sys.argv[1:],file=f)\n')
                binaries = root / 'bin'
                binaries.mkdir()
                xcode = binaries / 'xcodebuild'
                xcode.write_text(f'#!/bin/bash\nprintf "%s\\n" "$@" >> "$COVERZIP_TEST_LOG"\nexit {build_result}\n')
                xcode.chmod(0o755)
                log = root / 'commands.txt'
                env = dict(os.environ, PATH=str(binaries) + ':' + os.environ['PATH'], COVERZIP_TEST_LOG=str(log))
                result = subprocess.run(['/bin/bash', str(tools / 'build_coverzip.sh'), '52'], env=env, capture_output=True, text=True)
                self.assertEqual(result.returncode, build_result, result.stderr)
                lines = log.read_text().splitlines()
                self.assertIn('CURRENT_PROJECT_VERSION=52', lines)
                if build_result:
                    self.assertEqual(lines[-1], 'installer --apply')
                else:
                    self.assertEqual(lines[-1], 'installer --install-from .build-local/Build/Products/Release/CoverZip.app --apply')


if __name__ == '__main__':
    unittest.main()
