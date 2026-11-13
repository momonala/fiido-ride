# /// script
# requires-python = ">=3.12"
# ///
"""Runs sync.sh when Fiido Ride asks (GET /sync with the token from .env) and streams its progress back.

Response lines: "step <n> <total> <label>" while running, then "done <counts JSON>" or "error <message>".
"""

import hmac
import logging
import subprocess
import threading
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SYNC_SCRIPT = REPO / "sync" / "sync.sh"
SYNC_TIMEOUT_S = 300
ERROR_TAIL_CHARS = 500

log = logging.getLogger("fiido-sync")
sync_lock = threading.Lock()


def read_env() -> dict[str, str]:
    lines = (REPO / ".env").read_text().splitlines()
    return dict(line.split("=", 1) for line in lines if "=" in line)


class Handler(BaseHTTPRequestHandler):
    token = ""

    def do_GET(self) -> None:
        sent = self.headers.get("Authorization", "").removeprefix("Bearer ")
        if self.path != "/sync" or not hmac.compare_digest(sent, self.token):
            self.send_error(HTTPStatus.NOT_FOUND)
            return
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.end_headers()
        if not sync_lock.acquire(blocking=False):
            self.send_line("error a sync is already running")
            return
        try:
            self.stream_sync()
        finally:
            sync_lock.release()

    def stream_sync(self) -> None:
        process = subprocess.Popen(
            [str(SYNC_SCRIPT)], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1
        )
        timer = threading.Timer(SYNC_TIMEOUT_S, process.kill)
        timer.start()
        other_output: list[str] = []
        last = ""
        assert process.stdout is not None
        for raw in process.stdout:
            line = raw.rstrip("\n")
            if line.startswith("step "):
                self.send_line(line)
            elif line:
                other_output.append(line)
                last = line
        process.wait()
        timer.cancel()
        if process.returncode == 0:
            self.send_line(f"done {last}")
            log.info("sync ok: %s", last)
        else:
            message = "\n".join(other_output)[-ERROR_TAIL_CHARS:] or f"sync.sh exited {process.returncode}"
            self.send_line(f"error {message}".replace("\n", " | "))
            log.info("sync failed: %s", message)

    def send_line(self, line: str) -> None:
        self.wfile.write(f"{line}\n".encode())
        self.wfile.flush()

    def log_message(self, format: str, *args: object) -> None:
        pass


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(message)s")
    env = read_env()
    Handler.token = env["SYNC_TOKEN"]
    server = ThreadingHTTPServer(("", int(env["SYNC_PORT"])), Handler)
    log.info("listening on port %s", env["SYNC_PORT"])
    server.serve_forever()


if __name__ == "__main__":
    main()
