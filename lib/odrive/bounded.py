"""Size-capped subprocess output and file reads.

Listings, errors and logs come from cloud content that can be arbitrarily
large or hostile. Nothing here ever holds more than a fixed number of bytes:
subprocess output beyond the cap is discarded (and the process is stopped
once its stdout overflows), and logs are read from the end only.
"""

import os
import subprocess
import threading
from dataclasses import dataclass
from typing import List, Optional

from .rclone_rc import die_with_parent

_CHUNK = 64 * 1024


@dataclass
class BoundedResult:
    returncode: Optional[int]  # None if the process was killed for timing out
    stdout: bytes
    stderr: bytes
    stdout_truncated: bool
    timed_out: bool


def run_bounded(cmd: List[str], timeout: float, max_stdout: int = 0, max_stderr: int = 64 * 1024) -> BoundedResult:
    """Run cmd keeping at most max_stdout / max_stderr bytes of its output.

    max_stdout=0 discards stdout entirely. When stdout passes its cap the
    process is killed (its remaining output is unwanted), and the result is
    marked truncated; stderr past its cap is read and dropped so the process
    never blocks on a full pipe. The process also dies with odrive.
    """
    proc = subprocess.Popen(
        cmd,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE if max_stdout > 0 else subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        preexec_fn=die_with_parent(),
    )
    out, err = bytearray(), bytearray()
    state = {"truncated": False, "timed_out": False}

    def pump(stream, buf, cap, stop_when_full):
        with stream:
            while True:
                chunk = stream.read1(_CHUNK) if hasattr(stream, "read1") else stream.read(_CHUNK)
                if not chunk:
                    return
                room = cap - len(buf)
                if room > 0:
                    buf += chunk[:room]
                if len(chunk) > room and stop_when_full and not state["truncated"]:
                    state["truncated"] = True
                    proc.kill()

    def on_timeout():
        state["timed_out"] = True
        proc.kill()

    readers = [threading.Thread(target=pump, args=(proc.stderr, err, max_stderr, False), daemon=True)]
    if proc.stdout is not None:
        readers.append(threading.Thread(target=pump, args=(proc.stdout, out, max_stdout, True), daemon=True))
    timer = threading.Timer(timeout, on_timeout)
    timer.daemon = True
    timer.start()
    try:
        for t in readers:
            t.start()
        for t in readers:
            t.join()
        proc.wait()
    finally:
        timer.cancel()
        if proc.poll() is None:
            proc.kill()
            proc.wait()

    timed_out = state["timed_out"] and not state["truncated"]
    return BoundedResult(
        returncode=None if timed_out else proc.returncode,
        stdout=bytes(out),
        stderr=bytes(err),
        stdout_truncated=state["truncated"],
        timed_out=timed_out,
    )


def tail_text(path: os.PathLike, max_bytes: int = 64 * 1024) -> str:
    """The last max_bytes of a text file, starting at a line boundary."""
    with open(path, "rb") as f:
        f.seek(0, os.SEEK_END)
        size = f.tell()
        start = max(0, size - max_bytes)
        f.seek(start)
        data = f.read(max_bytes)
    if start > 0:
        # Drop the partial first line the cut landed in
        newline = data.find(b"\n")
        data = data[newline + 1:] if newline != -1 else b""
    return data.decode("utf-8", errors="replace")
