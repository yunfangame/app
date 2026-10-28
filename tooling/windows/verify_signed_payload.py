import hashlib
import json
from pathlib import Path
import struct
import sys


def verify_payload(unsigned, signed):
    if not __debug__:
        raise RuntimeError("Signed payload verification requires Python assertions")
    before = Path(unsigned).read_bytes()
    after = Path(signed).read_bytes()
    pe = struct.unpack_from('<I', before, 0x3c)[0]
    assert before[pe:pe + 4] == after[pe:pe + 4] == b'PE\0\0'
    optional = pe + 24
    magic = struct.unpack_from('<H', before, optional)[0]
    assert magic in (0x10b, 0x20b)
    security = optional + (96 if magic == 0x10b else 112) + 32
    assert struct.unpack_from('<II', before, security) == (0, 0)
    offset, size = struct.unpack_from('<II', after, security)
    assert offset == (len(before) + 7) // 8 * 8
    assert size > 8 and len(after) == offset + size
    assert after[len(before):offset] == bytes(offset - len(before))
    left, right = bytearray(before), bytearray(after[:len(before)])
    for start, length in [(optional + 64, 4), (security, 8)]:
        left[start:start + length] = bytes(length)
        right[start:start + length] = bytes(length)
    assert left == right, 'Unsigned payload changed during signing'
    return {
        'passed': True,
        'unsigned_sha256': hashlib.sha256(before).hexdigest(),
        'signed_sha256': hashlib.sha256(after).hexdigest(),
        'unsigned_bytes': len(before),
        'signed_bytes': len(after),
        'installer_content_preserved': True,
        'core_helper_payload_unchanged': True,
        'certificate_offset': offset,
        'certificate_bytes': size,
    }


if __name__ == '__main__':
    print(json.dumps(verify_payload(sys.argv[1], sys.argv[2]), indent=2))
