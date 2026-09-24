"""Private rclone remote-control channel for passing secrets without argv.

Anything on a command line is visible to every local user through /proc/<pid>/cmdline,
so credentials and tokens are sent to a short-lived `rclone rcd` in an HTTP request
body over a unix socket. The socket lives in a fresh 0700 directory, so only the
current user can connect to it.
"""

import http.client
import json
import os
import re
import shutil
import socket
import subprocess
import tempfile
import time
from typing import Iterable, Optional, Tuple

_STARTUP_TIMEOUT_SEC = 10.0
_REQUEST_TIMEOUT_SEC = 60.0


class RcError(Exception):
    """An rc call failed; the message never contains the request parameters."""


class _UnixHTTPConnection(http.client.HTTPConnection):
    def __init__(self, socket_path: str, timeout: float):
        super().__init__("localhost", timeout=timeout)
        self._socket_path = socket_path

    def connect(self):
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(self.timeout)
        sock.connect(self._socket_path)
        self.sock = sock


class RcloneRC:
    """Context manager running `rclone rcd` on a private unix socket."""

    def __init__(self, rclone_bin: str):
        self.rclone_bin = rclone_bin
        self._dir: Optional[str] = None
        self._socket_path = ""
        self._proc: Optional[subprocess.Popen] = None

    def __enter__(self) -> "RcloneRC":
        self._dir = tempfile.mkdtemp(prefix="odrive-rc-")  # created 0700
        self._socket_path = os.path.join(self._dir, "rc.sock")
        try:
            self._proc = subprocess.Popen(
                [self.rclone_bin, "rcd", "--rc-addr", f"unix://{self._socket_path}", "--rc-no-auth"],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            self._wait_until_ready()
        except BaseException:
            self.__exit__(None, None, None)
            raise
        return self

    def __exit__(self, exc_type, exc, tb) -> None:
        if self._proc is not None:
            self._proc.terminate()
            try:
                self._proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self._proc.kill()
                self._proc.wait()
            self._proc = None
        if self._dir is not None:
            shutil.rmtree(self._dir, ignore_errors=True)
            self._dir = None

    def _wait_until_ready(self) -> None:
        deadline = time.monotonic() + _STARTUP_TIMEOUT_SEC
        while time.monotonic() < deadline:
            if self._proc is not None and self._proc.poll() is not None:
                raise RcError("rclone rcd exited during startup")
            if os.path.exists(self._socket_path):
                try:
                    self.call("rc/noop", {}, timeout=2)
                    return
                except (OSError, RcError):
                    pass
            time.sleep(0.05)
        raise RcError("rclone rcd did not start in time")

    def call(self, method: str, params: dict, timeout: float = _REQUEST_TIMEOUT_SEC) -> dict:
        conn = _UnixHTTPConnection(self._socket_path, timeout)
        try:
            conn.request(
                "POST",
                "/" + method,
                body=json.dumps(params),
                headers={"Content-Type": "application/json"},
            )
            resp = conn.getresponse()
            raw = resp.read().decode("utf-8", errors="replace")
        finally:
            conn.close()
        try:
            data = json.loads(raw) if raw.strip() else {}
        except json.JSONDecodeError:
            data = {}
        if resp.status != 200:
            # rclone echoes the request back under "input"; only the error text is safe to surface
            raise RcError(str(data.get("error") or f"rclone rc {method} failed with HTTP {resp.status}"))
        return data


def config_create(rclone_bin: str, name: str, rclone_type: str, parameters: dict) -> Tuple[bool, str]:
    """Create a remote through the private rc channel; rclone obscures password fields itself."""
    try:
        with RcloneRC(rclone_bin) as rc:
            rc.call(
                "config/create",
                {
                    "name": name,
                    "type": rclone_type,
                    "parameters": parameters,
                    # Don't wait on follow-up config questions; the given values are saved regardless
                    "opt": {"nonInteractive": True, "obscure": True},
                },
            )
        return True, ""
    except (RcError, OSError, subprocess.SubprocessError) as e:
        return False, str(e)


_SECRET_KEY_RE = re.compile(r"pass|secret|token|2fa|key_id|private|credential", re.IGNORECASE)


def is_secret_key(key: str) -> bool:
    """Whether an rclone option name holds a credential (pass, secret_access_key, token, ...)."""
    return bool(_SECRET_KEY_RE.search(key))


_TOKEN_FIELD_RE = re.compile(r'("(?:access_token|refresh_token|id_token)"\s*:\s*")[^"]*(")')


def redact(text: str, secrets: Iterable[str] = ()) -> str:
    """Strip known secret values and OAuth token fields from text meant for users or logs."""
    out = _TOKEN_FIELD_RE.sub(r"\1***\2", text or "")
    for secret in secrets:
        if secret and len(secret) >= 3:
            out = out.replace(secret, "***")
    return out
