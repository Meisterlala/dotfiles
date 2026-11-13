#!/usr/bin/env python3

import os
import queue
import selectors
import subprocess
import threading
import time
from pathlib import Path

from evdev import InputDevice, ecodes, list_devices

DEVICE_KEYS = {
    "Glove80 Keyboard": ecodes.KEY_F14,
    "Valve Software Steam Controller Puck Keyboard": ecodes.KEY_INSERT,
}
SCRIPT = Path.home() / ".config/hypr/mic-push-to-mute.sh"


def mic(state):
    subprocess.run([str(SCRIPT), state], check=False)


class PushToTalk:
    def __init__(self):
        self.held = set()

    def update(self, path, down):
        was_talking = bool(self.held)
        if down:
            self.held.add(path)
        else:
            self.held.discard(path)
        if bool(self.held) != was_talking:
            mic("unmute" if self.held else "mute")


def watch_steam_keys(events):
    # Steam can inject keyboard mappings with XTEST instead of evdev.
    # Observe only synthetic Insert requests, not physical keyboard Insert.
    from Xlib import X, XK, display
    from Xlib.ext import record

    while True:
        connection = None
        try:
            connection = display.Display()
            opcode = connection.query_extension("XTEST").major_opcode
            insert = connection.keysym_to_keycode(XK.string_to_keysym("Insert"))

            def receive(reply):
                if reply.category != record.FromClient or reply.client_swapped:
                    return
                data = reply.data
                while len(data) >= 4:
                    size = int.from_bytes(data[2:4], "little") * 4
                    if size < 4 or size > len(data):
                        break
                    request, data = data[:size], data[size:]
                    if (len(request) >= 8 and request[0] == opcode
                            and request[1] == 2 and request[5] == insert
                            and request[4] in (X.KeyPress, X.KeyRelease)):
                        events.put(request[4] == X.KeyPress)

            context = connection.record_create_context(0, [record.AllClients], [{
                "core_requests": (0, 0), "core_replies": (0, 0),
                "ext_requests": (opcode, opcode, 2, 2),
                "ext_replies": (0, 0, 0, 0),
                "delivered_events": (0, 0), "device_events": (0, 0),
                "errors": (0, 0), "client_started": False, "client_died": False,
            }])
            print("Listening for Steam XTEST Insert", flush=True)
            connection.record_enable_context(context, receive)
        except Exception as error:
            print(f"XTEST listener reconnecting: {error}", flush=True)
        finally:
            events.put(False)
            if connection is not None:
                connection.close()
        time.sleep(2)


def controller_r5(report):
    # SDL's TritonMTUNoQuat{,32TS}: report ID, sequence, LE uint32 buttons.
    # https://github.com/libsdl-org/SDL/blob/main/src/joystick/hidapi/SDL_hidapi_steam_triton.c
    if len(report) < 46 or report[0] not in (0x42, 0x45, 0x47):
        return None
    return bool(int.from_bytes(report[2:6], "little") & 0x100)


class ControllerR5:
    def __init__(self):
        self.armed = False
        self.down = False

    def update(self, down):
        # Connecting while held must not open the mic. Require release first.
        if not down:
            self.armed = True
        down = down and self.armed
        if down == self.down:
            return None
        self.down = down
        return down


def watch_controller(events):
    # Passive hidraw reads: no grabs, feature writes, or Steam configuration changes.
    selector = selectors.DefaultSelector()
    devices = {}

    def remove(path):
        fd, button, _ = devices.pop(path)
        selector.unregister(fd)
        os.close(fd)
        events.put((path, False))

    next_discovery = 0
    while True:
        now = time.monotonic()
        if now >= next_discovery:
            for node in Path("/sys/class/hidraw").glob("hidraw*"):
                path = str(Path("/dev") / node.name)
                if path in devices:
                    continue
                fd = None
                try:
                    identity = (node / "device/uevent").read_text()
                    if not any(value in identity for value in (
                        "HID_ID=0003:000028DE:00001304",  # Steam Controller Puck
                        "HID_ID=0003:000028DE:00001302",  # Wired Triton
                    )):
                        continue
                    if b"\x85\x42" not in (node / "device/report_descriptor").read_bytes():
                        continue
                    fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
                    selector.register(fd, selectors.EVENT_READ, path)
                    devices[path] = [fd, ControllerR5(), now]
                    print(f"Listening directly to Steam Controller R5: {path}", flush=True)
                except OSError:
                    if fd is not None:
                        os.close(fd)
            next_discovery = now + 1
        for ready, _ in selector.select(timeout=0.05):
            path = ready.data
            try:
                report = os.read(ready.fd, 256)
                if not report:
                    remove(path)
                    continue
                down = controller_r5(report)
                if down is not None:
                    devices[path][2] = time.monotonic()
                    changed = devices[path][1].update(down)
                    if changed is not None:
                        print(f"Controller R5 {'pressed' if changed else 'released'}", flush=True)
                        events.put((path, changed))
            except BlockingIOError:
                pass
            except OSError:
                remove(path)
        for path, (_, button, last_report) in list(devices.items()):
            if time.monotonic() - last_report > 0.5:
                # Radio loss can leave hidraw open: fail closed and re-arm on release.
                if button.down:
                    print("Controller R5 released (input timeout)", flush=True)
                    events.put((path, False))
                button.down = False
                button.armed = False
            if not Path(path).exists():
                remove(path)


def main():
    selector = selectors.DefaultSelector()
    devices = {}
    ptt = PushToTalk()
    steam_events = queue.SimpleQueue()
    controller_events = queue.SimpleQueue()

    def remove(path):
        dev = devices.pop(path)
        selector.unregister(dev)
        dev.close()
        ptt.update(path, False)

    def discover():
        paths = set(list_devices())
        for path in list(devices):
            if path not in paths:
                remove(path)
        for path in paths - devices.keys():
            dev = None
            try:
                dev = InputDevice(path)
                key = DEVICE_KEYS.get(dev.name)
                if key is None or key not in dev.capabilities().get(ecodes.EV_KEY, []):
                    dev.close()
                    continue
                selector.register(dev, selectors.EVENT_READ)
                devices[path] = dev
                print(f"Listening to {dev.name}: {path} ({ecodes.KEY[key]})", flush=True)
            except OSError:
                if dev is not None:
                    dev.close()

    # Always start muted; only a fresh press opens the microphone.
    mic("mute")
    threading.Thread(target=watch_steam_keys, args=(steam_events,), daemon=True).start()
    threading.Thread(target=watch_controller, args=(controller_events,), daemon=True).start()
    next_discovery = 0
    try:
        while True:
            if time.monotonic() >= next_discovery:
                discover()
                next_discovery = time.monotonic() + 1
            while not steam_events.empty():
                ptt.update("steam-xtest", steam_events.get_nowait())
            while not controller_events.empty():
                path, down = controller_events.get_nowait()
                ptt.update(path, down)
            for ready, _ in selector.select(timeout=0.01):
                dev = ready.fileobj
                key = DEVICE_KEYS[dev.name]
                try:
                    for event in dev.read():
                        if event.type == ecodes.EV_SYN and event.code == ecodes.SYN_DROPPED:
                            # Lost input: fail closed until a fresh press.
                            ptt.update(dev.path, False)
                        elif event.type == ecodes.EV_KEY and event.code == key:
                            if event.value in (0, 1):  # Ignore autorepeat.
                                ptt.update(dev.path, event.value == 1)
                except OSError:
                    remove(dev.path)
    finally:
        for dev in devices.values():
            dev.close()
        selector.close()
        mic("mute")


if __name__ == "__main__":
    main()
