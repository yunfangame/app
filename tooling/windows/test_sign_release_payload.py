import struct
from pathlib import Path
import tempfile
import unittest

from sign_release_payload import code_kind, verify_script_content
from verify_signed_payload import verify_payload


class SigningIntegrityTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)

    def pe_pair(self):
        before = bytearray(512)
        before[:2] = b'MZ'
        struct.pack_into('<I', before, 0x3c, 128)
        before[128:132] = b'PE\0\0'
        struct.pack_into('<H', before, 152, 0x20b)
        after = bytearray(before)
        struct.pack_into('<II', after, 152 + 112 + 32, 512, 16)
        struct.pack_into('<I', after, 152 + 64, 1234)
        after.extend(b'0' * 16)
        left, right = self.root / 'before.exe', self.root / 'after.exe'
        left.write_bytes(before)
        right.write_bytes(after)
        return left, right

    def test_unsigned_content_survives_pe_signature_envelope(self):
        left, right = self.pe_pair()
        self.assertTrue(verify_payload(left, right)['passed'])

    def test_changed_pe_code_is_rejected(self):
        left, right = self.pe_pair()
        data = bytearray(right.read_bytes())
        data[400] = 1
        right.write_bytes(data)
        with self.assertRaises(AssertionError):
            verify_payload(left, right)

    def test_hidden_pe_file_is_still_discovered(self):
        left, _ = self.pe_pair()
        hidden = self.root / 'binary.dat'
        hidden.write_bytes(left.read_bytes())
        self.assertEqual(code_kind(hidden), 'pe')

    def test_fake_dll_is_rejected(self):
        path = self.root / 'fake.dll'
        path.write_text('invalid')
        with self.assertRaises(ValueError):
            code_kind(path)

    def test_unsupported_executable_script_is_rejected(self):
        path = self.root / 'cleanup.cmd'
        path.write_text('echo cleanup')
        with self.assertRaises(ValueError):
            code_kind(path)

    def test_script_signature_preserves_executable_text(self):
        before, after = self.root / 'a.ps1', self.root / 'b.ps1'
        before.write_bytes(b'Write-Output "test"\r\n')
        after.write_bytes(b'Write-Output "test"\r\n\r\n# SIG # Begin signature block\r\n# encoded\r\n# SIG # End signature block\r\n')
        verify_script_content(before, after)
        after.write_bytes(after.read_bytes().replace(b'"test"', b'"changed"'))
        with self.assertRaises(ValueError):
            verify_script_content(before, after)


if __name__ == '__main__':
    unittest.main()
