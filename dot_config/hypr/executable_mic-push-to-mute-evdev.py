#!/usr/bin/env python3

import subprocess
from pathlib import Path

from evdev import InputDevice, ecodes, list_devices

DEVICE_NAME = "Glove80 Keyboard"
SCRIPT = Path.home() / ".config/hypr/mic-push-to-mute.sh"


def find_keyboard():
    for path in list_devices():
        dev = InputDevice(path)

        if dev.name == DEVICE_NAME:
            return dev

        dev.close()

    raise RuntimeError(f"Could not find {DEVICE_NAME!r}")


def mic(state):
    subprocess.run([str(SCRIPT), state], check=False)


dev = find_keyboard()
print(f"Listening to {dev.name}: {dev.path}")

# Always start muted.
mic("mute")

try:
    for event in dev.read_loop():
        if event.type != ecodes.EV_KEY:
            continue

        if event.code != ecodes.KEY_F14:
            continue

        if event.value == 1:  # press
            print("F14 DOWN -> unmute")
            mic("unmute")

        elif event.value == 0:  # release
            print("F14 UP -> mute")
            mic("mute")

finally:
    # Fail safe.
    mic("mute")
