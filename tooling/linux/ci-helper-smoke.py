import http.client
import json
import os
from pathlib import Path
import socket
import struct
import subprocess
import sys
import time
import uuid


class HelperConnection(http.client.HTTPConnection):
    def connect(self):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.settimeout(self.timeout)
        self.sock.connect('/run/flclash/helper.sock')


def request(method, path, body=None, expected=200):
    connection = HelperConnection('localhost', timeout=20)
    try:
        connection.request(method, path, body=json.dumps(body) if body else None,
                           headers={'Content-Type': 'application/json'})
        response = connection.getresponse()
        data = response.read().decode()
        assert response.status == expected, (response.status, data)
        return data
    finally:
        connection.close()


def wait_for_exit(pid):
    for _ in range(100):
        if not Path(f'/proc/{pid}').exists():
            return
        time.sleep(0.1)
    raise AssertionError(f'Core {pid} did not exit')


def receive_exact(connection, size):
    result = b''
    while len(result) < size:
        part = connection.recv(size - len(result))
        assert part, 'Core disconnected before replying'
        result += part
    return result


def main():
    assert sys.platform == 'linux' and os.environ.get('GITHUB_ACTIONS') == 'true'
    assert os.getuid() != 0
    bundle = Path(sys.argv[1]).resolve()
    digest = json.loads((bundle / 'manifest.json').read_text())['coreSha256']
    assert request('GET', f'/ping?coreSha256={digest}').strip() == str(bundle / 'FlClashHelperService')
    request('GET', '/ping?coreSha256=' + '0' * 64, expected=409)
    address = f'/tmp/FlClashSocket_{os.getpid()}.sock'
    listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    listener.bind(address)
    listener.listen(1)
    listener.settimeout(15)
    session = uuid.uuid4().hex
    try:
        started = json.loads(request('POST', '/start', {'address': address, 'sessionId': session}))
        assert started['sessionId'] == session and started['pid'] > 0
        connection, _ = listener.accept()
        with connection:
            connection.settimeout(15)
            message = json.dumps({'id': 'smoke', 'method': 'ciUnknownMethod', 'arguments': None}).encode()
            connection.sendall(struct.pack('<I', len(message)) + message)
            for _ in range(30):
                size = struct.unpack('<I', receive_exact(connection, 4))[0]
                assert size <= 64 * 1024 * 1024
                reply = json.loads(receive_exact(connection, size))
                if isinstance(reply, dict) and reply.get('id') == 'smoke':
                    assert reply.get('error'), reply
                    break
            else:
                raise AssertionError('No framed IPC response from installed Core')
            request('POST', '/stop', {'sessionId': uuid.uuid4().hex}, expected=409)
            assert Path(f'/proc/{started["pid"]}').exists()
            stopped = json.loads(request('POST', '/stop', {'sessionId': session}))
            assert stopped['stopped'] is True
        wait_for_exit(started['pid'])
        session = uuid.uuid4().hex
        restarted = json.loads(request('POST', '/start', {'address': address, 'sessionId': session}))
        connection, _ = listener.accept()
        with connection:
            subprocess.run(['sudo', 'systemctl', 'stop', 'flclash-helper.service'], check=True)
            wait_for_exit(restarted['pid'])
        print('Installed Helper hash, IPC, session isolation and service-shutdown cleanup passed.')
    finally:
        listener.close()
        os.unlink(address)


if __name__ == '__main__':
    main()
