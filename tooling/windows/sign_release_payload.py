import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess

from verify_signed_payload import verify_payload


PUBLISHER = '27e3e2e77a0c5f3428eeb95a35825d4cf0c8710e760e9c8cb12b447d39603252'
SIGNABLE_SCRIPTS = {'.ps1', '.ps1xml', '.psc1', '.psd1', '.psm1', '.cdxml', '.mof', '.js'}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def security_size(data):
    pe = struct.unpack_from('<I', data, 0x3c)[0]
    if data[pe:pe + 4] != b'PE\0\0':
        raise ValueError('Invalid PE signature')
    optional = pe + 24
    magic = struct.unpack_from('<H', data, optional)[0]
    if magic not in (0x10b, 0x20b):
        raise ValueError('Invalid PE optional header')
    security = optional + (96 if magic == 0x10b else 112) + 32
    return struct.unpack_from('<II', data, security)[1]


def code_kind(path):
    data = path.read_bytes()
    if data.startswith(b'MZ'):
        security_size(data)
        return 'pe'
    if path.suffix.lower() in {'.exe', '.dll', '.sys', '.e32', '.e64'}:
        raise ValueError('Executable extension without a PE image: ' + path.name)
    if path.suffix.lower() in SIGNABLE_SCRIPTS:
        return 'script'
    if path.suffix.lower() in {'.bat', '.cmd', '.vbs'}:
        raise ValueError('Unsupported executable script: ' + path.name)
    return None


def verify_script_content(before, after):
    source = before.read_bytes().decode('utf-8-sig').replace('\r\n', '\n')
    signed = after.read_bytes().decode('utf-8-sig').replace('\r\n', '\n')
    prefix = '// SIG // ' if before.suffix.lower() == '.js' else '# SIG # '
    marker = prefix + 'Begin signature block'
    if marker in source or signed.count(marker) != 1:
        raise ValueError('Unexpected script signature block')
    content, signature = signed.split(marker)
    if content.rstrip('\n') != source.rstrip('\n') or prefix + 'End signature block' not in signature:
        raise ValueError('Signing changed script content')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--input', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--signing-config', type=Path, required=True)
    parser.add_argument('--native-inventory', type=Path, required=True)
    parser.add_argument('--crl-directory', type=Path)
    parser.add_argument('--reuse', type=Path)
    args = parser.parse_args()
    source, output, config = args.input.resolve(), args.output.resolve(), args.signing_config.resolve()
    if output.exists() or not source.is_dir() or output.is_relative_to(source):
        raise ValueError('Use a new output directory outside the input tree')
    files = sorted(source.rglob('*'))
    if any(p.is_symlink() for p in files):
        raise ValueError('Symlinks are not permitted in a signing input')
    inventory = json.loads(args.native_inventory.read_text(encoding='utf-8-sig'))
    trusted = {'bundle/' + row['path']: row for row in inventory}
    if len(trusted) != len(inventory):
        raise ValueError('Duplicate native signature inventory entries')
    certificate = subprocess.check_output(['/opt/homebrew/bin/openssl', 'x509', '-in', str(config / 'ov-leaf-public.pem'), '-outform', 'DER'])
    if hashlib.sha256(certificate).hexdigest() != PUBLISHER:
        raise ValueError('Unexpected OV certificate')
    env = dict(os.environ, OPENSSL_CONF=str(config / 'openssl-ov-public.cnf'), OPENSSL_MODULES='/opt/homebrew/lib/ossl-modules', PKCS11_MODULE_PATH='/usr/local/lib/SimplySignPKCS/SimplySignPKCS-MS-1.1.24.dylib')
    output.mkdir(parents=True)
    logs = output / 'signing-logs'
    logs.mkdir()
    rows = []

    def invoke(name, command, required=True):
        if command[0] == 'verify' and args.crl_directory:
            command = command + ['-ignore-cdp', '-CRLfile', str(args.crl_directory / 'publisher.pem'), '-TSA-CRLfile', str(args.crl_directory / 'timestamp.pem')]
        result = subprocess.run(['/opt/homebrew/bin/osslsigncode', *command], env=env, capture_output=True, timeout=180)
        (logs / name).write_bytes(result.stdout + result.stderr)
        if required and result.returncode:
            raise RuntimeError('Signing or verification failed; no login/PIN retry: ' + name)
        return result.returncode

    for path in files:
        if not path.is_file():
            continue
        relative = path.relative_to(source)
        target = output / 'payload' / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        kind = code_kind(path)
        row = {'path': relative.as_posix(), 'unsigned_sha256': sha(path), 'kind': kind}
        if kind:
            data = path.read_bytes()
            existing = security_size(data) > 0 if kind == 'pe' else b'# SIG # Begin signature block' in data
            log_id = f'{len(rows):04d}'
            if existing:
                proof = trusted.get(relative.as_posix())
                if not proof or proof['status'] != 'Valid' or proof['sha256'] != row['unsigned_sha256'] or not proof['timestamped']:
                    raise ValueError('Existing signature lacks matching native Windows acceptance: ' + str(relative))
                shutil.copy2(path, target)
                row['action'] = 'preserved_trusted_signature'
                row['native_windows_signature'] = proof
            else:
                reusable = args.reuse / relative if args.reuse else None
                if reusable and reusable.is_file() and not reusable.is_symlink():
                    shutil.copy2(reusable, target)
                    row['reused_after_signature_and_content_verification'] = True
                else:
                    invoke(log_id + '-sign.log', ['sign', '-provider', 'pkcs11prov', '-pkcs11module', env['PKCS11_MODULE_PATH'], '-certs', str(config / 'ov-leaf-public.pem'), '-ac', str(config / 'ov-intermediates-public.pem'), '-key', 'pkcs11:token=Code%20Signing;id=%92%45%43%36%2D%8E%AB%76%53%15%63%B8%BC%BB%AE%8F%95%3B%10%93;type=private', '-h', 'sha256', '-n', 'FengWo 1.1.1', '-i', 'https://fengwo.io', '-comm', '-ts', 'http://time.certum.pl', '-in', str(path), '-out', str(target)])
                invoke(log_id + '-verify.log', ['verify', '-require-leaf-hash', 'sha256:' + PUBLISHER, '-in', str(target)])
                if kind == 'pe':
                    row['content_verification'] = verify_payload(path, target)
                else:
                    verify_script_content(path, target)
                    row['script_content_preserved'] = True
                row['action'] = 'ov_signed'
                row['publisher_certificate_sha256'] = PUBLISHER
        else:
            shutil.copy2(path, target)
            row['action'] = 'copied_unchanged'
        if sha(path) != row['unsigned_sha256']:
            raise ValueError('Input changed while signing')
        row['sha256'] = sha(target)
        row['bytes'] = target.stat().st_size
        rows.append(row)
        (output / 'progress.json').write_text(json.dumps(rows, indent=2) + '\n')
        if kind:
            print(json.dumps({'path': row['path'], 'action': row['action'], 'sha256': row['sha256']}), flush=True)
    receipt = {'schema': 'fengwo-fully-signed-payload-v1', 'passed': True, 'files': rows, 'sac_enforcement_test_passed': False, 'publication_allowed': False}
    (output / 'signed-payload.json').write_text(json.dumps(receipt, indent=2) + '\n')


if __name__ == '__main__':
    os.umask(0o077)
    main()
