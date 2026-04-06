import argparse
import json
import os
import re
import signal
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--host', default='127.0.0.1')
    parser.add_argument('--port', type=int, required=True)
    parser.add_argument('--capture', required=True)
    parser.add_argument('--message-id-start', type=int, default=7000)
    args = parser.parse_args()

    os.makedirs(os.path.dirname(os.path.abspath(args.capture)), exist_ok=True)
    counter = {'message_id': args.message_id_start}
    route_re = re.compile(r'^/bot([^/]+)/(sendMessage|sendChatAction)$')

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, format, *items):
            return

        def _write_json(self, status: int, payload: dict) -> None:
            body = json.dumps(payload).encode('utf-8')
            self.send_response(status)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            if self.path == '/health':
                self._write_json(200, {'ok': True, 'status': 'ready'})
                return
            self._write_json(404, {'ok': False, 'description': 'not found'})

        def do_POST(self):
            match = route_re.match(self.path)
            if not match:
                self._write_json(404, {'ok': False, 'description': 'not found'})
                return
            token = match.group(1)
            method = match.group(2)
            length = int(self.headers.get('Content-Length', '0'))
            raw = self.rfile.read(length)
            try:
                payload = json.loads(raw.decode('utf-8')) if raw else {}
            except Exception as exc:
                self._write_json(400, {'ok': False, 'description': f'invalid json: {exc}'})
                return

            record = {
                'path': self.path,
                'token': token,
                'method': method,
                'body': payload,
            }
            with open(args.capture, 'a', encoding='utf-8') as handle:
                handle.write(json.dumps(record, separators=(',', ':')))
                handle.write('\n')

            if method == 'sendMessage':
                counter['message_id'] += 1
                self._write_json(200, {
                    'ok': True,
                    'result': {
                        'message_id': counter['message_id'],
                        'chat': {'id': payload.get('chat_id')},
                        'text': payload.get('text', ''),
                    },
                })
                return

            if method == 'sendChatAction':
                self._write_json(200, {'ok': True, 'result': True})
                return

            self._write_json(404, {'ok': False, 'description': 'unsupported method'})

    server = ThreadingHTTPServer((args.host, args.port), Handler)

    def shutdown(_signum=None, _frame=None):
        server.shutdown()

    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT, shutdown)
    try:
        server.serve_forever(poll_interval=0.1)
    finally:
        server.server_close()
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
