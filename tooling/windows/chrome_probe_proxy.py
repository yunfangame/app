import argparse
import json
import select
import socket
import socketserver
import threading
import time

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
            while self.rfile.readline(16384) not in (b'\r\n', b'\n', b''):
                pass
            if method != 'CONNECT':
                self.connection.sendall(b'HTTP/1.1 405 Method Not Allowed\r\nContent-Length: 0\r\n\r\n')
                log(method=method, error='non_connect')
                return
            host, port = authority.rsplit(':', 1)
            remote = socket.create_connection((host, int(port)), timeout=15)
            self.connection.sendall(b'HTTP/1.1 200 Connection Established\r\n\r\n')
            log(method=method, host=host, port=int(port), stage='connected')
            sockets = [self.connection, remote]
            self.connection.setblocking(False)
            remote.setblocking(False)
            deadline = time.monotonic() + 240
            transferred = 0
            while time.monotonic() < deadline:
                ready, _, _ = select.select(sockets, [], [], 20)
                if not ready:
                    break
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
