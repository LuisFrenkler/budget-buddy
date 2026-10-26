# Serves build/web for local testing. Every response says "no-cache", so the
# browser checks for a newer build on each reload instead of showing an old
# main.dart.js from its cache.
#   python3 tool/serve_web.py   ->  http://127.0.0.1:8765
import functools
import http.server
import os

ROOT = os.path.join(os.path.dirname(__file__), "..", "build", "web")


class NoCacheHandler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cache-Control", "no-cache, must-revalidate")
        super().end_headers()


if __name__ == "__main__":
    handler = functools.partial(NoCacheHandler, directory=os.path.abspath(ROOT))
    http.server.ThreadingHTTPServer(("127.0.0.1", 8765), handler).serve_forever()
