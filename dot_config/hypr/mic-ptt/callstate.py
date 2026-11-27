"""Discord call state from its own RTC log, not microphone activity.

Stock Discord logs voice connections as 'default' and screen shares as 'stream'.
This is an undocumented log format; unknown/missing state stays silent.
"""

import os
import re
import time
from pathlib import Path

LOG = Path.home() / ".config/discord/logs/renderer_js.log"
VOICE = re.compile(
    r"\[RTCConnection\([^,\n]+, default\)\] "
    r"(?:RTC connection state: \S+ => (\S+)|Destroy RTCConnection)"
)
process = None
since = ""
handle = None
connected = False


def process_key(pid):
    # Linux stat field 22 identifies the process even if its PID gets reused.
    fields = Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split()
    if fields[0] == "Z":
        raise ProcessLookupError(pid)
    return pid, int(fields[19])


def find_discord():
    for node in Path("/proc").iterdir():
        if not node.name.isdecimal():
            continue
        try:
            if node.stat().st_uid != os.getuid():
                continue
            if (node / "comm").read_text().strip() != "Discord":
                continue
            args = (node / "cmdline").read_bytes().split(b"\0")
            # Electron can rewrite argv into one space-separated process title.
            executable = Path(os.readlink(node / "exe")).name.removesuffix(" (deleted)")
            if executable != "Discord":
                continue
            if any(b"--type=" in arg for arg in args):
                continue
            return process_key(node.name)
        except (OSError, ValueError, IndexError):
            continue
    return None


def read_events(file):
    global connected
    while True:
        position = file.tell()
        line = file.readline()
        if not line:
            return
        if not line.endswith(b"\n"):
            file.seek(position)  # Wait for an unfinished log write.
            return
        text = line.decode(errors="replace")
        if not text.startswith("[") or text[1:20] < since:
            continue
        if "[BUILD INFO]" in text or "splashScreenPreload: signalReady" in text:
            connected = False
        match = VOICE.search(text)
        if match:
            connected = match[1] == "RTC_CONNECTED"


def in_call():
    global process, since, handle, connected
    current = None
    if process:
        try:
            if process_key(process[0]) == process:
                current = process
        except (OSError, ValueError, IndexError):
            pass
    if not current:
        current = find_discord()
    if current != process:
        close()
        process = current
        if current:
            # Ignore logs from previous Discord runs, even after a crash.
            with open("/proc/stat") as stat:
                boot = next(int(line.split()[1]) for line in stat if line.startswith("btime "))
            started = boot + current[1] / os.sysconf("SC_CLK_TCK")
            since = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(started))
            # The call may predate the current log after Discord rotated it.
            try:
                with LOG.with_name("renderer_js.old.log").open("rb") as old:
                    read_events(old)
            except OSError:
                pass
    if not process:
        return False
    try:
        info = LOG.stat()
        if handle:
            read_events(handle)  # Drain the old inode before following rotation.
            opened = os.fstat(handle.fileno())
            if (opened.st_dev, opened.st_ino) != (info.st_dev, info.st_ino):
                handle.close()
                handle = None
            elif info.st_size < handle.tell():
                handle.seek(0)
                connected = False
        if not handle:
            handle = LOG.open("rb")
        read_events(handle)
    except OSError:
        # No evidence of a current connection: suppress sounds, not PTT itself.
        if handle:
            handle.close()
            handle = None
        connected = False
    return connected


def close():
    global process, handle, connected
    if handle:
        handle.close()
        handle = None
    process = None
    connected = False
