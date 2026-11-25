#!/usr/bin/env python3
"""One-shot HTTP server for tests/test_webhook_args.sh: takes a single POST,
writes what it received to a JSON file, answers 204 and exits."""
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path


def make_handler(out_path: Path):
    class Handler(BaseHTTPRequestHandler):
        def do_POST(self):
            length = int(self.headers.get("Content-Length") or 0)
            body = self.rfile.read(length).decode("utf-8", "replace")
            out_path.write_text(json.dumps({
                "path": self.path,
                "body": body,
                "content_type": self.headers.get("Content-Type"),
            }))
            self.send_response(204)
            self.end_headers()

        def log_message(self, format, *args):  # noqa: A002 - signature of the base class
            pass

    return Handler


def main():
    port = int(sys.argv[1])
    server = HTTPServer(("127.0.0.1", port), make_handler(Path(sys.argv[2])))
    server.timeout = 40
    server.handle_request()


if __name__ == "__main__":
    main()
