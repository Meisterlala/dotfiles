#!/usr/bin/env python3
import json
import re
import subprocess

# Mapping: "process_name": "Friendly Display Name"
FRIENDLY_NAMES = {
    "discord": "Discord",
    "zen": "Zen Browser",
    "firefox": "Firefox",
    "chromium": "Chromium",
    "brave": "Brave Browser",
    "vlc": "VLC Media Player",
    "mpv": "mpv Player",
    "steam": "Steam",
    "webcord": "WebCord",
    "jellyfin-desktop": "Jellyfin",
}


def get_hypridle_state():
    try:
        cmd = ["journalctl", "--user", "-u", "hypridle", "-n", "300", "--no-pager"]
        logs = subprocess.check_output(cmd, text=True).splitlines()
    except Exception:
        return {"text": "!", "tooltip": "Failed to read logs"}

    active_locks = {}
    reported_count = 0

    for line in logs:
        # Capture the 'Official' count
        count_match = re.search(r"Inhibit locks: (-?\d+)", line)
        if count_match:
            reported_count = int(count_match.group(1))
            if reported_count <= 0:
                active_locks.clear()

        # Track Inhibit
        if "ScreenSaver inhibit: true" in line:
            match = re.search(r"from (.*?) \(owner: (.*?)\) with content (.*)", line)
            if match:
                prog_path, owner_id, reason = match.groups()
                raw_name = prog_path.split("/")[-1] if prog_path else "unknown"
                display_name = FRIENDLY_NAMES.get(raw_name.lower(), raw_name)
                active_locks[owner_id] = f"<b>{display_name}</b>: {reason}"

        # Track Uninhibit
        elif "ScreenSaver inhibit: false" in line:
            match = re.search(r"owner: ([:\d\.]+)", line)
            if match:
                owner_id = match.group(1)
                active_locks.pop(owner_id, None)

    parsed_count = len(active_locks)

    # HIDING LOGIC:
    # If count is 0 or less, set text to "" so Waybar hides the widget.
    if reported_count <= 0:
        return {"text": "", "tooltip": "", "class": "idle"}

    # TOOLTIP LOGIC:
    tooltip_lines = list(active_locks.values())
    if reported_count > parsed_count:
        diff = reported_count - parsed_count
        tooltip_lines.append(f"<i>+ {diff} unidentified lock(s)</i>")

    return {
        "text": str(reported_count),
        "tooltip": "\n".join(tooltip_lines),
        "class": "active",
        "alt": "active",
    }


if __name__ == "__main__":
    print(json.dumps(get_hypridle_state()))
