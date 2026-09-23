import argparse
import hashlib
import json
import os
import pathlib
import re
import subprocess
import urllib.request
import zipfile


SQLITE_URL = 'https://sqlite.org/2026/sqlite-amalgamation-3530300.zip'
SQLITE_ZIP_SHA256 = '646421e12aac110282ef8cc68f1a62d4bb15fc7b8f09da0b53e29ee690500431'
SQLITE_C_SHA3 = '28e484abdaa43630e34040ef6ed92be973a1ad54107803d8af5145b889c23ed7'
SDK_FILE = 'packages/flutter_tools/lib/src/isolated/native_assets/macos/native_assets.dart'


def prepare(build_root, flutter_sdk, sdk_copy):
    source_root = pathlib.Path(__file__).resolve().parents[2]
    build_root = pathlib.Path(build_root).resolve()
    flutter_sdk = pathlib.Path(flutter_sdk).resolve()
    sdk_copy = pathlib.Path(sdk_copy).resolve()
    if any(
        first == second or first in second.parents or second in first.parents
        for first, second in [(build_root, source_root), (sdk_copy, flutter_sdk),
                              (sdk_copy, source_root), (sdk_copy, build_root)]
    ):
        raise ValueError('Use a separate project worktree and a separate SDK copy.')
    source_pubspec_before = (source_root / 'pubspec.yaml').read_bytes()
    source_sdk_before = (flutter_sdk / SDK_FILE).read_bytes()
    version = json.loads(subprocess.check_output(
        [str(flutter_sdk / 'bin/flutter'), '--version', '--machine'], text=True,
    ))
    if version['frameworkVersion'] != '3.44.4':
        raise ValueError('This preparation is pinned to Flutter 3.44.4.')
    lock = (build_root / 'pubspec.lock').read_text()
    sqlite_section = re.search(r'^  sqlite3:\n(.*?)(?=^  \S|\Z)', lock, re.M | re.S)
    if not sqlite_section or 'version: "3.5.0"' not in sqlite_section.group(1):
        raise ValueError('Review SQLite build options when changing sqlite3 3.5.0.')
    pubspec = build_root / 'pubspec.yaml'
    original_pubspec = pubspec.read_bytes()
    if re.search(rb'^hooks:', original_pubspec, re.M):
        raise ValueError('Refusing to overwrite existing hook settings.')
    if sdk_copy.exists():
        raise ValueError('SDK destination already exists; use a fresh copy.')
    sdk_copy.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(['cp', '-cR', str(flutter_sdk), str(sdk_copy)], check=True)
    sdk_file = sdk_copy / SDK_FILE
    upstream = sdk_file.read_text()
    if upstream.count('const targetMacOSVersion = 13;') != 1:
        raise ValueError('Unexpected Flutter native asset target implementation.')
    sdk_file.write_text(upstream.replace(
        'const targetMacOSVersion = 13;', 'const targetMacOSVersion = 12;',
    ))
    for name in ['flutter_tools.snapshot', 'flutter_tools.stamp']:
        (sdk_copy / 'bin/cache' / name).unlink(missing_ok=True)
    source_dir = build_root / '.dart_tool/fengwo_macos12'
    source_dir.mkdir(parents=True, exist_ok=True)
    archive = source_dir / 'sqlite-amalgamation-3530300.zip'
    with urllib.request.urlopen(SQLITE_URL, timeout=90) as response:
        archive.write_bytes(response.read())
    if hashlib.sha256(archive.read_bytes()).hexdigest() != SQLITE_ZIP_SHA256:
        raise ValueError('SQLite archive checksum mismatch.')
    with zipfile.ZipFile(archive) as package:
        for name in ['sqlite3.c', 'sqlite3.h']:
            data = package.read('sqlite-amalgamation-3530300/' + name)
            if name == 'sqlite3.c' and hashlib.sha3_256(data).hexdigest() != SQLITE_C_SHA3:
                raise ValueError('SQLite source checksum mismatch.')
            (source_dir / name).write_bytes(data)
    hook = (
        '\nhooks:\n'
        '  user_defines:\n'
        '    sqlite3:\n'
        '      source: source\n'
        '      path: .dart_tool/fengwo_macos12/sqlite3.c\n'
        '      defines:\n'
        '        defines:\n'
        '          - HAVE_STRCHRNUL=0\n'
        '      additional_flags:\n'
        '        - -Werror=unguarded-availability\n'
        '        - -Werror=unguarded-availability-new\n'
    )
    pubspec.write_bytes(original_pubspec + hook.encode())
    (source_dir / 'pubspec.before-hooks.yaml').write_bytes(original_pubspec)
    source_unchanged = source_pubspec_before == (source_root / 'pubspec.yaml').read_bytes()
    sdk_unchanged = source_sdk_before == (flutter_sdk / SDK_FILE).read_bytes()
    if not source_unchanged or not sdk_unchanged:
        raise ValueError('Original project or SDK changed while preparing the build.')
    result = {
        'minimumMacOS': '12.0',
        'flutterVersion': version['frameworkVersion'],
        'upstreamFlutterSdk': str(flutter_sdk),
        'isolatedFlutterSdk': str(sdk_copy),
        'nativeAssetTargetFile': SDK_FILE,
        'upstreamTargetFileSha256': hashlib.sha256(upstream.encode()).hexdigest(),
        'patchedTargetFileSha256': hashlib.sha256(sdk_file.read_bytes()).hexdigest(),
        'sqliteVersion': '3.53.3',
        'sqliteSourceUrl': SQLITE_URL,
        'sqliteArchiveSha256': SQLITE_ZIP_SHA256,
        'sqliteSourceSha3_256': SQLITE_C_SHA3,
        'hookConfigurationScope': 'isolated macOS build worktree only',
        'originalPubspecSha256': hashlib.sha256(original_pubspec).hexdigest(),
        'preparedPubspecSha256': hashlib.sha256(pubspec.read_bytes()).hexdigest(),
        'sourcePubspecUntouched': source_unchanged,
        'sourcePubspecSha256': hashlib.sha256(source_pubspec_before).hexdigest(),
        'upstreamSdkTargetFileUntouched': sdk_unchanged,
    }
    (source_dir / 'preparation.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--build-root', required=True)
    parser.add_argument('--flutter-sdk', required=True)
    parser.add_argument('--sdk-copy', required=True)
    arguments = parser.parse_args()
    if os.uname().sysname != 'Darwin':
        raise SystemExit('macOS is required.')
    prepare(arguments.build_root, arguments.flutter_sdk, arguments.sdk_copy)
