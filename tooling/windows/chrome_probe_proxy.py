import argparse
import json
import select
import socket
import socketserver
import threading
import time
import urllib.parse

parser = argparse.ArgumentParser()
parser.add_argument('--port', type=int, default=17890)
parser.add_argument('--log', required=True)
args = parser.parse_args()
lock = threading.Lock()


def log(**fields):
    with lock, open(args.log, 'a', encoding='utf-8') as stream:
        stream.write(json.dumps({'time': time.time(), **fields}) + '\n')


class Handler(socketserver.StreamRequestHandler):
    def handle(self):
        remote = None
        try:
            self.connection.settimeout(15)
            line = self.rfile.readline(16384).decode('ascii', errors='replace')
            method, authority, version = line.strip().split(' ', 2)
            headers = []
            while True:
                header = self.rfile.readline(16384)
                if header in (b'\r\n', b'\n', b''):
                    break
                headers.append(header)
            if method == 'CONNECT':
                host, port = authority.rsplit(':', 1)
            else:
                uri = urllib.parse.urlsplit(authority)
                if uri.scheme != 'http' or not uri.hostname:
                    raise ValueError('Unsupported HTTP proxy target')
                host, port = uri.hostname, uri.port or 80
            remote = socket.create_connection((host, int(port)), timeout=15)
            if method == 'CONNECT':
                self.connection.sendall(b'HTTP/1.1 200 Connection Established\r\n\r\n')
            else:
                path = urllib.parse.urlunsplit(('', '', uri.path or '/', uri.query, ''))
                request = f'{method} {path} {version}\r\n'.encode('ascii')
                request += b''.join(header for header in headers if not header.lower().startswith((b'proxy-connection:', b'connection:')))
                length = next((int(header.split(b':', 1)[1]) for header in headers if header.lower().startswith(b'content-length:')), 0)
                body = self.rfile.read(length) if length else b''
                remote.sendall(request + b'Connection: close\r\n\r\n' + body)
            log(method=method, host=host, port=int(port), stage='connected')
            sockets = [self.connection, remote]
            self.connection.setblocking(False)
            remote.setblocking(False)
            deadline = time.monotonic() + 240
            transferred = 0
            while time.monotonic() < deadline:
                ready, _, _ = select.select(sockets, [], [], 20)
                if not ready:
                    continue
                for source in ready:
                    data = source.recv(65536)
                    if not data:
                        log(host=host, stage='closed', bytes=transferred)
                        return
                    target = remote if source is self.connection else self.connection
                    target.settimeout(15)
                    target.sendall(data)
                    target.setblocking(False)
                    transferred += len(data)
        except Exception as error:
            log(stage='error', error=type(error).__name__, errno=getattr(error, 'errno', None))
        finally:
            if remote:
                remote.close()


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


with Server(('127.0.0.1', args.port), Handler) as server:
    log(stage='ready', port=args.port)
    server.serve_forever(poll_interval=0.2)
