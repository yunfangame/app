import base64
import json
import os
from pathlib import Path
import shutil
import socket
import struct
import subprocess
import threading
import unittest

import chain_fixture as fixture


class ChainFixtureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.servers = []
        for port, role in [(31811, 'node'), (31813, 'exit-a')]:
            server = fixture.ProxyServer(('127.0.0.1', port), fixture.ProxyHandler)
            server.role = role
            threading.Thread(target=server.serve_forever, daemon=True).start()
            cls.servers.append(server)
        origin = fixture.ThreadingHTTPServer(('127.0.0.1', 31815), fixture.HttpHandler)
        threading.Thread(target=origin.serve_forever, daemon=True).start()
        cls.servers.append(origin)

    @classmethod
    def tearDownClass(cls):
        for server in cls.servers:
            server.shutdown()
            server.server_close()

    def connect_node(self, password=b'synthetic-node-pass'):
        client = socket.create_connection(('127.0.0.1', 31811), 3)
        self.addCleanup(client.close)
        client.sendall(b'\x05\x01\x02')
        self.assertEqual(fixture.read_exact(client, 2), b'\x05\x02')
        user = b'synthetic-node'
        client.sendall(b'\x01' + bytes([len(user)]) + user + bytes([len(password)]) + password)
        response = fixture.read_exact(client, 2)
        if password != b'synthetic-node-pass':
            self.assertEqual(response, b'\x01\x01')
            return client
        self.assertEqual(response, b'\x01\x00')
        client.sendall(b'\x05\x01\x00\x01\x7f\x00\x00\x01' + struct.pack('!H', 31813))
        self.assertEqual(fixture.read_exact(client, 10)[:2], b'\x05\x00')
        return client

    def connect_exit(self, client, auth=True):
        client.sendall(b'\x05\x01' + bytes([2 if auth else 0]))
        self.assertEqual(fixture.read_exact(client, 2), bytes([5, 2 if auth else 0]))
        if auth:
            user, password = b'synthetic-exit', b'synthetic-exit-pass'
            client.sendall(b'\x01' + bytes([len(user)]) + user + bytes([len(password)]) + password)
            self.assertEqual(fixture.read_exact(client, 2), b'\x01\x00')
        host = b'localhost'
        client.sendall(b'\x05\x01\x00\x03' + bytes([len(host)]) + host + struct.pack('!H', 31815))
        return fixture.read_exact(client, 10)

    def assert_origin(self, client):
        client.sendall(b'GET /host-test HTTP/1.0\r\nHost: localhost\r\n\r\n')
        body = bytearray()
        while True:
            part = client.recv(4096)
            if not part:
                break
            body.extend(part)
        self.assertTrue(bytes(body).endswith(b'FENGWO_CHAIN_FIXTURE_OK'))

    def test_authenticated_and_no_auth_two_hop_requests(self):
        for auth in [True, False]:
            name = 'host-auth-' + str(auth)
            fixture.STATE.configure({'name': name, 'exit_auth': auth})
            client = self.connect_node()
            self.assertEqual(self.connect_exit(client, auth)[:2], b'\x05\x00')
            self.assert_origin(client)
            records = fixture.STATE.snapshot(name)['connections']
            self.assertEqual([record['role'] for record in records], ['node', 'exit-a'])
            self.assertTrue(records[1]['peer_is_node'])
            self.assertTrue(all(record['authenticated'] and record['connected'] for record in records))
            self.assertTrue(all(record['up_bytes'] > 0 and record['down_bytes'] > 0 for record in records))

    def test_first_hop_authentication_and_exit_connect_rejection(self):
        fixture.STATE.configure({'name': 'host-node-reject'})
        self.connect_node(b'wrong-synthetic-password')
        self.assertEqual(fixture.STATE.snapshot('host-node-reject')['origin_requests'], [])
        fixture.STATE.configure({'name': 'host-exit-reject', 'behavior': 'reject'})
        client = self.connect_node()
        self.assertEqual(self.connect_exit(client)[:2], b'\x05\x02')
        self.assertEqual(fixture.STATE.snapshot('host-exit-reject')['origin_requests'], [])

    def test_http_authenticated_exit_over_selected_node(self):
        fixture.STATE.configure({'name': 'host-http-exit', 'protocol': 'http'})
        client = self.connect_node()
        token = base64.b64encode(b'synthetic-exit:synthetic-exit-pass')
        client.sendall(b'CONNECT localhost:31815 HTTP/1.1\r\nProxy-Authorization: Basic ' + token + b'\r\n\r\n')
        self.assertIn(b'200 Connection Established', fixture.read_header(client))
        self.assert_origin(client)
        records = fixture.STATE.snapshot('host-http-exit')['connections']
        self.assertTrue(records[-1]['peer_is_node'])


class HttpClientTests(unittest.TestCase):
    def test_loopback_origin_is_never_implicitly_bypassed(self):
        paths = []

        class Handler(fixture.BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_GET(self):
                paths.append(self.path)
                body = b'STRICT_PROXY_CLIENT_OK'
                self.send_response(200)
                self.send_header('Content-Type', 'text/plain; charset=utf-8')
                self.send_header('Content-Length', str(len(body)))
                self.end_headers()
                self.wfile.write(body)

        server = fixture.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        try:
            executable = os.environ.get('FENGWO_TEST_PWSH') or shutil.which('pwsh')
            if not executable:
                raise RuntimeError('The exact HTTP proxy fixture requires PowerShell 7')
            source = str(Path(__file__).with_name('core_windows_fixture.cs').resolve()).replace("'", "''")
            command = f"Add-Type -Path '{source}'; $r=[FengWoRealWindowsTests.HttpProbe]::Get('http://127.0.0.1:31815/explicit-proxy','host-proxy',3,{server.server_port}); @{{status=$r.Status;body=$r.Body}} | ConvertTo-Json -Compress"
            result = subprocess.run([executable, '-NoProfile', '-Command', command], check=True, capture_output=True, text=True, timeout=20)
            response = json.loads(result.stdout)
            self.assertEqual(response, {'status': 200, 'body': 'STRICT_PROXY_CLIENT_OK'})
            self.assertEqual(paths, ['http://127.0.0.1:31815/explicit-proxy'])
        finally:
            server.shutdown()
            server.server_close()


if __name__ == '__main__':
    unittest.main()
