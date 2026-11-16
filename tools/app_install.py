"""CoverZipの導入と、Finderへ再登録されない形式でのビルド保管。"""
from pathlib import Path
import argparse
import hashlib
import os
import plistlib
import re
import shutil
import stat
import subprocess
import tempfile
import uuid
import zipfile

ROOT = Path(__file__).resolve().parents[1]
INSTALLED = Path('/Applications/CoverZip.app')
BUNDLE_ID = 'com.dmng.CoverZip'
LSREGISTER = '/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'


def run(*args):
    return subprocess.run([str(a) for a in args], check=True, capture_output=True, text=True).stdout


def bundle_info(app):
    with (app / 'Contents/Info.plist').open('rb') as stream:
        info = plistlib.load(stream)
    if app.is_symlink() or info.get('CFBundleIdentifier') != BUNDLE_ID:
        raise ValueError(f'CoverZip本体ではありません: {app}')
    return info


def verify_archive(app, archive):
    """削除前に全ファイルの内容とシンボリックリンクの復元情報を照合する。"""
    # dittoはUTF-8名でもZIPのUTF-8フラグを省略することがある。
    with zipfile.ZipFile(archive, metadata_encoding='utf-8') as saved:
        if saved.testzip() is not None:
            raise ValueError(f'ZIPが破損しています: {archive}')
        for directory, dirs, files in os.walk(app, followlinks=False):
            for name in dirs + files:
                path = Path(directory) / name
                relative = path.relative_to(app.parent).as_posix()
                if path.is_symlink():
                    entry = saved.getinfo(relative)
                    if not stat.S_ISLNK(entry.external_attr >> 16) or saved.read(relative) != os.fsencode(os.readlink(path)):
                        raise ValueError(f'リンク不一致: {relative}')
                elif path.is_file():
                    if hashlib.sha256(path.read_bytes()).digest() != hashlib.sha256(saved.read(relative)).digest():
                        raise ValueError(f'ファイル不一致: {relative}')


def archive_bundle(app, archive_directory):
    info = bundle_info(app)
    archive_directory.mkdir(parents=True, exist_ok=True)
    # 同じビルド番号での再ビルドも、既存の退避物を上書きしない。
    version = re.sub(r'[^0-9A-Za-z._-]', '_', str(info.get('CFBundleVersion', 'unknown')))
    archive = archive_directory / f'CoverZip-build{version}-{uuid.uuid4().hex[:12]}.app.zip'
    run('/usr/bin/ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', app, archive)
    verify_archive(app, archive)
    return archive


def registered_paths():
    paths = []
    for block in re.split(r'\n-+\n', run(LSREGISTER, '-dump')):
        if re.search(r'^identifier:\s+com\.dmng\.CoverZip\s*$', block, re.M):
            match = re.search(r'^path:\s+(.+?)\s+\(0x[0-9a-f]+\)\s*$', block, re.M)
            if match:
                paths.append(Path(match.group(1)))
    return paths


def managed_apps(root):
    apps = set(root.glob('.build*/Build/Products/*/CoverZip.app'))
    backup = root / '.local-backup'
    if backup.exists():
        apps.update(backup.rglob('*.app'))
    result = []
    for app in apps:
        if app.is_symlink() or root.resolve() not in app.resolve().parents:
            continue
        try:
            bundle_info(app)
        except (ValueError, OSError, plistlib.InvalidFileException):
            continue
        result.append(app)
    return sorted(result)


def cleanup(root, apply=False):
    if apply:
        bundle_info(INSTALLED)
        signature_team(INSTALLED)
    apps = managed_apps(root)
    for app in apps:
        if apply:
            archive = archive_bundle(app, root / '.local-backup/app-archives')
            # 未登録の場合は-10814になるため、解除結果は最後のDB照合で判定する。
            subprocess.run([LSREGISTER, '-u', str(app)], capture_output=True)
            shutil.rmtree(app)
            print(f'ZIP保管: {archive}')
        else:
            print(f'ZIP保管予定: {app}')
    if apply:
        for path in registered_paths():
            if path != INSTALLED and root.resolve() in path.resolve().parents:
                subprocess.run([LSREGISTER, '-u', str(path)], capture_output=True)
        run(LSREGISTER, '-f', INSTALLED)
        for extension in (INSTALLED / 'Contents/PlugIns').glob('*.appex'):
            run('/usr/bin/pluginkit', '-a', extension)
        remaining = registered_paths()
        if set(remaining) != {INSTALLED}:
            raise RuntimeError(f'インストール先以外の登録が残っています: {remaining}')
        print(f'Finderの登録確認: {INSTALLED} のみ')


def signature_team(app):
    run('/usr/bin/codesign', '--verify', '--deep', '--strict', app)
    details = subprocess.run(['/usr/bin/codesign', '-dv', str(app)], check=True, capture_output=True, text=True).stderr
    match = re.search(r'^TeamIdentifier=(.+)$', details, re.M)
    if not match or match.group(1) == 'not set':
        raise ValueError(f'開発チームの署名がありません: {app}')
    return match.group(1)


def install(source):
    bundle_info(source)
    source_team = signature_team(source)
    if INSTALLED.exists() and signature_team(INSTALLED) != source_team:
        raise ValueError('既存アプリと署名チームが異なります')
    if subprocess.run(['/usr/bin/pgrep', '-x', 'CoverZip'], capture_output=True).returncode == 0:
        raise RuntimeError('更新前にCoverZip本体を終了してください')
    # 導入先と同じボリュームで準備し、コピー失敗時は現在のアプリを保持する。
    with tempfile.TemporaryDirectory(prefix='.coverzip-install-', dir=INSTALLED.parent) as directory:
        stage = Path(directory) / 'CoverZip.app'
        previous = Path(directory) / 'previous.app'
        run('/usr/bin/ditto', source, stage)
        signature_team(stage)
        if INSTALLED.exists():
            saved = archive_bundle(INSTALLED, ROOT / '.local-backup/app-archives')
            print(f'旧版のZIP保管: {saved}')
            INSTALLED.rename(previous)
        try:
            stage.rename(INSTALLED)
            signature_team(INSTALLED)
        except Exception:
            if INSTALLED.exists():
                shutil.rmtree(INSTALLED)
            if previous.exists():
                previous.rename(INSTALLED)
            raise
    # 有効な既存のログイン項目だけを再起動し、旧バイナリが残らないようにする。
    service = f'gui/{os.getuid()}/com.dmng.CoverZip.KeyHelper'
    if subprocess.run(['/bin/launchctl', 'print', service], capture_output=True).returncode == 0:
        run('/bin/launchctl', 'kickstart', '-k', service)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--install-from', type=Path, help='導入する署名済みCoverZip.app')
    parser.add_argument('--apply', action='store_true', help='省略時は対象表示のみ')
    args = parser.parse_args()
    if args.install_from:
        source = args.install_from.resolve()
        if source not in managed_apps(ROOT):
            parser.error('導入元はこのrepoの .build*/Build/Products/*/CoverZip.app を指定してください')
        if args.apply:
            install(source)
        else:
            print(f'導入予定: {source} → {INSTALLED}')
    cleanup(ROOT, apply=args.apply)


if __name__ == '__main__':
    main()
