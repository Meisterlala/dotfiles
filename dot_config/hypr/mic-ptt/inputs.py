"""Passive keyboard, Steam XTEST and controller R5 input. Never grabs devices."""

import logging
import os
import queue
import selectors
import threading
import time
from pathlib import Path

from evdev import InputDevice, ecodes, list_devices

log = logging.getLogger(__name__)
DEVICE_KEYS = {
    "Glove80 Keyboard": ecodes.KEY_F14,
    "Valve Software Steam Controller Puck Keyboard": ecodes.KEY_INSERT,
}


def boot_time():
    return time.clock_gettime(time.CLOCK_BOOTTIME)


def watch_steam_keys(emit, stop):
    # Physical Insert on an unrelated keyboard must not open the mic.
    from Xlib import X, XK, display
    from Xlib.ext import record

    while not stop.is_set():
        connection = None
        try:
            connection = display.Display()
            opcode = connection.query_extension("XTEST").major_opcode
            insert = connection.keysym_to_keycode(XK.string_to_keysym("Insert"))
            keys = connection.query_keymap()
            armed = not bool(keys[insert // 8] & (1 << (insert % 8)))
            sleep_offset = boot_time() - time.monotonic()

            def receive(reply):
                nonlocal armed, sleep_offset
                offset = boot_time() - time.monotonic()
                if offset - sleep_offset > 0.5:
                    armed = False
                    emit("steam-xtest", False, False)
                sleep_offset = offset
                if reply.category != record.FromClient or reply.client_swapped:
                    return
                data = reply.data
                while len(data) >= 4:
                    size = int.from_bytes(data[2:4], "little") * 4
                    if size < 4 or size > len(data):
                        break
                    request, data = data[:size], data[size:]
                    if (len(request) >= 8 and request[0] == opcode
                            and request[1] == 2 and request[5] == insert):
                        if request[4] == X.KeyRelease:
                            armed = True
                            emit("steam-xtest", False)
                        elif request[4] == X.KeyPress and armed:
                            emit("steam-xtest", True)

            context = connection.record_create_context(0, [record.AllClients], [{
                "core_requests": (0, 0), "core_replies": (0, 0),
                "ext_requests": (opcode, opcode, 2, 2),
                "ext_replies": (0, 0, 0, 0),
                "delivered_events": (0, 0), "device_events": (0, 0),
                "errors": (0, 0), "client_started": False, "client_died": False,
            }])
            log.info("Listening for Steam XTEST Insert")
            connection.record_enable_context(context, receive)
        except Exception as error:
            log.warning("XTEST listener reconnecting: %s", error)
        finally:
            emit("steam-xtest", False, False)
            if connection is not None:
                connection.close()
        stop.wait(2)


def controller_r5(report):
    # SDL TritonMTUNoQuat{,32TS}: report ID, sequence, LE uint32 buttons.
    if len(report) < 46 or report[0] not in (0x42, 0x45, 0x47):
        return None
    return bool(int.from_bytes(report[2:6], "little") & 0x100)


def watch_controller(emit, stop):
    selector = selectors.DefaultSelector()
    devices = {}

    def remove(path):
        device = devices.pop(path)
        selector.unregister(device["fd"])
        os.close(device["fd"])
        emit(path, False, False)

    next_discovery = 0
    sleep_offset = boot_time() - time.monotonic()
    try:
        while not stop.is_set():
            now = boot_time()
            offset = now - time.monotonic()
            resumed = offset - sleep_offset > 0.5
            sleep_offset = offset
            for path, device in list(devices.items()):
                if resumed:
                    # Discard reports queued before suspend, then require release.
                    try:
                        while os.read(device["fd"], 256):
                            pass
                        remove(path)
                        continue
                    except BlockingIOError:
                        pass
                    except OSError:
                        remove(path)
                        continue
                if resumed or now - device["last"] > 0.5:
                    if device["down"]:
                        emit(path, False, False)
                    device["down"] = device["armed"] = False
            if now >= next_discovery:
                for path in list(devices):
                    if not Path(path).exists():
                        remove(path)
                for node in Path("/sys/class/hidraw").glob("hidraw*"):
                    path = str(Path("/dev") / node.name)
                    if path in devices:
                        continue
                    fd = None
                    try:
                        identity = (node / "device/uevent").read_text()
                        if not any(value in identity for value in (
                            "HID_ID=0003:000028DE:00001304",  # Puck
                            "HID_ID=0003:000028DE:00001302",  # Wired Triton
                        )):
                            continue
                        if b"\x85\x42" not in (node / "device/report_descriptor").read_bytes():
                            continue
                        fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
                        selector.register(fd, selectors.EVENT_READ, path)
                        devices[path] = dict(fd=fd, armed=False, down=False, last=now)
                        log.info("Listening to controller R5: %s", path)
                    except OSError:
                        if fd is not None:
                            os.close(fd)
                next_discovery = now + 1
            timeout = max(0, next_discovery - boot_time())
            for device in devices.values():
                if device["armed"] or device["down"]:
                    timeout = min(timeout, max(0, device["last"] + 0.5 - boot_time()))
            ready_events = selector.select(timeout=timeout)
            # Batch high-rate HID reports, preserving every button transition.
            if ready_events and stop.wait(0.01):
                break
            for ready, _ in ready_events:
                # The next iteration handles resume before consuming any reports.
                if boot_time() - time.monotonic() - sleep_offset > 0.5:
                    break
                path = ready.data
                try:
                    for _ in range(64):
                        report = os.read(ready.fd, 256)
                        if not report:
                            remove(path)
                            break
                        down = controller_r5(report)
                        if down is None:
                            continue
                        device = devices[path]
                        stamp = boot_time()
                        if stamp - device["last"] > 0.5:
                            if device["down"]:
                                emit(path, False, False)
                            device["down"] = device["armed"] = False
                        device["last"] = stamp
                        if not down:
                            if not device["armed"]:
                                emit(path, False)
                            device["armed"] = True
                        down = down and device["armed"]
                        if down != device["down"]:
                            device["down"] = down
                            emit(path, down)
                except BlockingIOError:
                    pass
                except OSError:
                    remove(path)
    finally:
        for path in list(devices):
            remove(path)
        selector.close()


def run(on_event, on_tick, on_resume, stop):
    selector = selectors.DefaultSelector()
    devices = {}
    events = queue.SimpleQueue()
    wake = os.eventfd(0, os.EFD_NONBLOCK | os.EFD_CLOEXEC)
    selector.register(wake, selectors.EVENT_READ, "wakeup")
    cutoff = 0
    blocked = set()
    seen_sources = {"steam-xtest"}
    last_boot, last_mono = boot_time(), time.monotonic()

    def emit(source, down, deliberate=True):
        if stop.is_set():
            return
        events.put((source, down, deliberate, boot_time()))
        try:
            os.eventfd_write(wake, 1)
        except OSError:
            if not stop.is_set():
                raise

    def supervise(watcher):
        try:
            watcher(emit, stop)
        except Exception:
            log.exception("Input listener failed: %s", watcher.__name__)
        finally:
            if not stop.is_set():
                emit(None, watcher.__name__, False)

    def remove(path):
        device = devices.pop(path)["device"]
        selector.unregister(device)
        device.close()
        on_event(path, False, False)

    def discover():
        paths = set(list_devices())
        for path in list(devices):
            if path not in paths:
                remove(path)
        for path in paths - devices.keys():
            device = None
            try:
                device = InputDevice(path)
                key = DEVICE_KEYS.get(device.name)
                if key is None or key not in device.capabilities().get(ecodes.EV_KEY, []):
                    device.close()
                    continue
                armed = key not in device.active_keys()
                selector.register(device, selectors.EVENT_READ)
                devices[path] = dict(device=device, armed=armed, dropped=False)
                if armed:
                    on_event(path, False)  # Known-up baseline, not a button press.
                log.info("Listening to %s: %s", device.name, path)
            except OSError:
                if device is not None:
                    device.close()

    def check_resume():
        nonlocal last_boot, last_mono, cutoff
        boot, mono = boot_time(), time.monotonic()
        resumed = (boot - last_boot) - (mono - last_mono) > 0.5 or mono - last_mono > 2
        last_boot, last_mono = boot, mono
        if not resumed:
            return False
        cutoff = boot
        blocked.update(seen_sources)
        on_resume()
        for path, item in list(devices.items()):
            device = item["device"]
            try:
                try:
                    while True:
                        for _ in device.read():  # Discard pre-resume key events.
                            pass
                except BlockingIOError:
                    pass
                item["armed"] = DEVICE_KEYS[device.name] not in device.active_keys()
                item["dropped"] = False
                if item["armed"]:
                    on_event(path, False)
            except OSError:
                remove(path)
        log.info("Resumed: muted silently; stale input discarded")
        return True

    for watcher in (watch_steam_keys, watch_controller):
        threading.Thread(target=supervise, args=(watcher,), daemon=True).start()
    next_discovery = 0
    try:
        while not stop.is_set():
            check_resume()
            now = time.monotonic()
            if now >= next_discovery:
                discover()
                next_discovery = now + 1
            while True:
                try:
                    path, down, deliberate, stamp = events.get_nowait()
                except queue.Empty:
                    break
                if path is None:
                    raise RuntimeError(f"Input listener stopped: {down}")
                seen_sources.add(path)
                if stamp < cutoff:
                    continue
                if path in blocked:
                    if not down and deliberate:
                        blocked.discard(path)
                    else:
                        continue
                on_event(path, down, deliberate)
            timeout = on_tick()
            ready_events = selector.select(timeout=min(timeout, max(0, next_discovery - time.monotonic())))
            if check_resume():
                continue
            for ready, _ in ready_events:
                if ready.data == "wakeup":
                    try:
                        os.eventfd_read(wake)
                    except BlockingIOError:
                        pass
                    continue
                device = ready.fileobj
                item = devices[device.path]
                key = DEVICE_KEYS[device.name]
                try:
                    for event in device.read():
                        if event.type == ecodes.EV_SYN:
                            if event.code == ecodes.SYN_DROPPED:
                                item["armed"] = False
                                item["dropped"] = True
                                on_event(device.path, False, False)
                            elif event.code == ecodes.SYN_REPORT:
                                item["dropped"] = False
                        elif not item["dropped"] and event.type == ecodes.EV_KEY and event.code == key:
                            if event.value == 0:
                                item["armed"] = True
                                on_event(device.path, False)
                            elif event.value == 1 and item["armed"]:
                                on_event(device.path, True)
                except OSError:
                    remove(device.path)
    finally:
        stop.set()
        for item in devices.values():
            item["device"].close()
        selector.close()
        os.close(wake)
