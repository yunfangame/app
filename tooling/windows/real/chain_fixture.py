import argparse
import base64
import json
import os
import select
import socket
import socketserver
import struct
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


class State:
    def __init__(self):
        self.lock = threading.RLock()
        self.case = {'name': 'initial'}
        self.records = []
        self.origin_requests = []
        self.forwarders = set()
        self.origin_sources = {}

    def configure(self, value):
        with self.lock:
            self.case = dict(value)

    def record(self, role, peer):
        with self.lock:
            item = {'case': self.case['name'], 'role': role, 'authenticated': False,
                    'connected': False, 'target_host': None, 'target_port': None,
                    'target_address_type': None, 'up_bytes': 0, 'down_bytes': 0,
                    'error': None, 'finished': False, 'peer_is_node': peer[1] in self.forwarders}
            self.records.append(item)
            return item, dict(self.case)

    def snapshot(self, case):
        with self.lock:
            return {'case': case, 'connections': [dict(x) for x in self.records if x['case'] == case],
                    'origin_requests': [dict(x) for x in self.origin_requests if x['case'] == case]}


STATE = State()


def read_exact(sock, length):
    data = bytearray()
    while len(data) < length:
        part = sock.recv(length - len(data))
        if not part:
            raise EOFError('peer_closed')
        data.extend(part)
    return bytes(data)


def read_header(sock):
    data = bytearray()
    while not data.endswith(b'\r\n\r\n'):
        if len(data) >= 16384:
            raise ValueError('header_bound')
        data.extend(read_exact(sock, 1))
    return bytes(data)


def open_target(host, port, role, record):
    if role == 'node':
        if port not in (31813, 31814, 31815) or host not in ('localhost', '127.0.0.1'):
            raise ValueError('node_target_not_allowed')
    elif not (port == 31815 and host in ('localhost', '127.0.0.1')):
        if port not in (80, 443):
            raise ValueError('exit_target_not_allowed')
        if host not in ('www.cloudflare.com', 'cp.cloudflare.com', 'www.gstatic.com'):
            allowed = set()
            for name in ('www.cloudflare.com', 'cp.cloudflare.com', 'www.gstatic.com'):
                allowed.update(x[4][0] for x in socket.getaddrinfo(name, port, socket.AF_INET, socket.SOCK_STREAM))
            if host not in allowed:
                raise ValueError('exit_address_not_allowed')
    target = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    target.settimeout(10)
    target.bind(('127.0.0.1' if role == 'node' else '0.0.0.0', 0))
    if role == 'node':
        with STATE.lock:
            STATE.forwarders.add(target.getsockname()[1])
    if port == 31815:
        with STATE.lock:
            STATE.origin_sources[target.getsockname()[1]] = {'role': role, 'case': record['case'], 'listener_port': record['listener_port']}
    try:
        target.connect((host, port))
        record['connected'] = True
        return target
    except BaseException:
        target.close()
        raise


def relay(client, target, record):
    client.setblocking(False)
    target.setblocking(False)
    deadline = time.monotonic() + 30
    while time.monotonic() < deadline:
        readable, _, _ = select.select([client, target], [], [], 0.25)
        for source in readable:
            data = source.recv(65536)
            if not data:
                return
            destination = target if source is client else client
            destination.settimeout(10)
            destination.sendall(data)
            destination.setblocking(False)
            record['up_bytes' if source is client else 'down_bytes'] += len(data)


class ProxyHandler(socketserver.BaseRequestHandler):
    def handle(self):
        role = self.server.role
        record, case = STATE.record(role, self.client_address)
        record['listener_port'] = self.server.server_address[1]
        client = self.request
        client.settimeout(12)
        target = None
        try:
            if role != 'node' and case.get('via_node_only', True) and not record['peer_is_node']:
                raise ValueError('exit_requires_selected_node')
            if role != 'node' and case.get('behavior') == 'timeout':
                record['error'] = 'synthetic_handshake_timeout'
                time.sleep(8)
                return
            if role != 'node' and case.get('protocol') == 'http':
                header = read_header(client).decode('ascii')
                lines = header.split('\r\n')
                parts = lines[0].split(' ')
                if len(parts) != 3 or parts[0] != 'CONNECT':
                    raise ValueError('expected_http_connect')
                host, port = parts[1].rsplit(':', 1)
                token = base64.b64encode(b'synthetic-exit:synthetic-exit-pass').decode('ascii')
                if not any(line.lower() == ('proxy-authorization: basic ' + token).lower() for line in lines):
                    client.sendall(b'HTTP/1.1 407 Proxy Authentication Required\r\nContent-Length: 0\r\n\r\n')
                    record['error'] = 'authentication_rejected'
                    return
                record['authenticated'] = True
                record['target_address_type'] = 'http-connect'
                record['target_host'], record['target_port'] = host, int(port)
                target = open_target(host, int(port), role, record)
                client.sendall(b'HTTP/1.1 200 Connection Established\r\n\r\n')
            else:
                version, methods_length = read_exact(client, 2)
                if version != 5:
                    raise ValueError('expected_socks5')
                methods = read_exact(client, methods_length)
                auth = role == 'node' or case.get('exit_auth', True)
                method = 2 if auth else 0
                if method not in methods:
                    client.sendall(b'\x05\xff')
                    raise ValueError('auth_method_not_offered')
                client.sendall(bytes([5, method]))
                if auth:
                    version, username_length = read_exact(client, 2)
                    username = read_exact(client, username_length)
                    password = read_exact(client, read_exact(client, 1)[0])
                    expected = (b'synthetic-node', b'synthetic-node-pass') if role == 'node' else (b'synthetic-exit', b'synthetic-exit-pass')
                    accepted = version == 1 and (username, password) == expected
                    client.sendall(bytes([1, 0 if accepted else 1]))
                    if not accepted:
                        record['error'] = 'authentication_rejected'
                        return
                record['authenticated'] = True
                version, command, reserved, address_type = read_exact(client, 4)
                if version != 5 or command != 1 or reserved != 0:
                    raise ValueError('expected_socks_connect')
                if address_type == 1:
                    host = socket.inet_ntop(socket.AF_INET, read_exact(client, 4))
                elif address_type == 3:
                    host = read_exact(client, read_exact(client, 1)[0]).decode('ascii')
                elif address_type == 4:
                    host = socket.inet_ntop(socket.AF_INET6, read_exact(client, 16))
                else:
                    raise ValueError('invalid_socks_address_type')
                port = struct.unpack('!H', read_exact(client, 2))[0]
                record['target_host'], record['target_port'] = host, port
                record['target_address_type'] = address_type
                if role != 'node' and case.get('behavior') == 'reject':
                    client.sendall(b'\x05\x02\x00\x01\x7f\x00\x00\x01\x00\x00')
                    record['error'] = 'connect_rejected'
                    return
                target = open_target(host, port, role, record)
                client.sendall(b'\x05\x00\x00\x01\x7f\x00\x00\x01\x00\x00')
            relay(client, target, record)
        except (OSError, EOFError, ValueError) as error:
            record['error'] = type(error).__name__
        finally:
            if target:
                target.close()
            record['finished'] = True


class ProxyServer(socketserver.ThreadingTCPServer):
    daemon_threads = True
    allow_reuse_address = False


class HttpHandler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def send_json(self, value):
        body = json.dumps(value).encode('utf-8')
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        length = int(self.headers.get('Content-Length', '0'))
        if self.path != '/case' or length > 8192:
            self.send_error(400)
            return
        value = json.loads(self.rfile.read(length))
        if not isinstance(value.get('name'), str):
            self.send_error(400)
            return
        STATE.configure(value)
        self.send_json({'ready': True, 'case': value['name']})

    def do_GET(self):
        if self.server.server_port == 31816:
            name = self.path.removeprefix('/snapshot/')
            self.send_json(STATE.snapshot(name))
            return
        self.origin(False)

    def do_HEAD(self):
        self.origin(True)

    def origin(self, head):
        name = self.headers.get('X-FengWo-Chain-Case', STATE.case['name'])
        with STATE.lock:
            source = STATE.origin_sources.get(self.client_address[1], {})
            case = dict(STATE.case)
            role = source.get('role')
            expected = None if case.get('mode') == 'direct' else ('node' if case.get('disabled') else 'exit')
            actual = 'exit' if role in ('exit-a', 'exit-b') else role
            accepted = expected is None or (actual == expected and source.get('case') == name)
            STATE.origin_requests.append({'case': name, 'path': self.path, 'peer_role': role, 'peer_listener_port': source.get('listener_port'), 'expected_hop_verified': accepted})
        if not accepted:
            self.send_error(403, 'The fixture origin requires the expected proxy hop')
            return
        time.sleep(0.02)
        body = b'FENGWO_CHAIN_FIXTURE_OK'
        self.send_response(200)
        self.send_header('Content-Type', 'text/plain; charset=utf-8')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        if not head:
            self.wfile.write(body)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--ready', required=True)
    args = parser.parse_args()
    if os.name != 'nt' or os.environ.get('GITHUB_ACTIONS') != 'true' or os.environ.get('RUNNER_OS') != 'Windows':
        raise SystemExit('An isolated Windows GitHub Actions runner is required')
    servers = []
    for port, role in [(31811, 'node'), (31812, 'node'), (31813, 'exit-a'), (31814, 'exit-b')]:
        server = ProxyServer(('127.0.0.1', port), ProxyHandler)
        server.role = role
        threading.Thread(target=server.serve_forever, daemon=True).start()
        servers.append(server)
    origin = ThreadingHTTPServer(('127.0.0.1', 31815), HttpHandler)
    threading.Thread(target=origin.serve_forever, daemon=True).start()
    control = ThreadingHTTPServer(('127.0.0.1', 31816), HttpHandler)
    Path(args.ready).write_text(json.dumps({'pid': os.getpid(), 'ports': [31811, 31812, 31813, 31814, 31815, 31816], 'synthetic_only': True}), encoding='utf-8')
    try:
        control.serve_forever()
    finally:
        for server in servers + [origin, control]:
            server.server_close()


if __name__ == '__main__':
    main()
