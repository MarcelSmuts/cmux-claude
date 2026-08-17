#!/usr/bin/env python3
# Local-only server backing todos.html: serves the static page (shipped alongside this
# script, so it travels with the skill) and gives it direct read/write access to
# todos.md, so the browser never needs its own filesystem permission (no file picker,
# no File System Access API). Binds to 127.0.0.1 only.
import http.server
import os

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
HTML = os.path.join(SCRIPT_DIR, "todos.html")

# Same resolution as config.sh: todos.md lives next to the config, outside the skill
# folder, since — unlike this code — it's the user's personal data.
CONFIG = os.environ.get(
    "CMUXCLAUDE_CONFIG",
    os.path.join(os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config")), "cmux-claude", "config"),
)
TODOS = os.environ.get("CMUXCLAUDE_TODOS", os.path.join(os.path.dirname(CONFIG), "todos.md"))
PORT = 8943


class Handler(http.server.BaseHTTPRequestHandler):
    def _send(self, code, body, ctype="text/plain; charset=utf-8"):
        data = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path in ("/", "/todos.html"):
            with open(HTML, "r", encoding="utf-8") as f:
                self._send(200, f.read(), "text/html; charset=utf-8")
        elif self.path == "/api/todos":
            with open(TODOS, "r", encoding="utf-8") as f:
                self._send(200, f.read())
        else:
            self._send(404, "not found")

    def do_POST(self):
        if self.path == "/api/todos":
            length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(length).decode("utf-8")
            tmp = TODOS + ".tmp"
            with open(tmp, "w", encoding="utf-8") as f:
                f.write(body)
            os.replace(tmp, TODOS)
            self._send(200, "ok")
        else:
            self._send(404, "not found")

    def log_message(self, fmt, *args):
        pass


if __name__ == "__main__":
    http.server.HTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
