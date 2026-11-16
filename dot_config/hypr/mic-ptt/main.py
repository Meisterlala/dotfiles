#!/usr/bin/env python3
"""Per-application microphone push-to-talk."""

import argparse
import logging
import signal
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import audio
import callstate
import inputs
import state

CALL_CACHE_SECONDS = 0.25


def main():
    parser = argparse.ArgumentParser(description="Per-app microphone push-to-talk")
    parser.add_argument("--check", action="store_true",
                        help="check native audio connection without changing audio or watching input")
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
    stop = threading.Event()
    for sig in (signal.SIGINT, signal.SIGTERM):
        signal.signal(sig, lambda *_: stop.set())
    ptt = {"held": set(), "deadline": None}
    blocked_sources = set()
    checker = None
    call_check = None
    call_checked_at = 0
    try:
        audio.connect(Path(__file__).with_name("release.wav"), control=not args.check)
        if args.check:
            deadline = time.monotonic() + 2
            while audio.operations and time.monotonic() < deadline and not stop.is_set():
                audio.pump()
                time.sleep(0.01)
            if audio.operations:
                raise RuntimeError("PulseAudio check timed out")
            logging.info("Native PulseAudio connection OK; no audio changes made")
            logging.info("Discord in call: %s", "yes" if callstate.in_call() else "no")
            return

        # One worker serializes log reads; it sleeps between button presses.
        checker = ThreadPoolExecutor(max_workers=1, thread_name_prefix="call-check")

        def on_event(source, down, deliberate=True):
            nonlocal call_check, call_checked_at
            if source in blocked_sources:
                if not down and deliberate:
                    blocked_sources.discard(source)
                return
            if not deliberate and source in ptt["held"]:
                # A controller can report through HID, evdev and XTEST together.
                # Losing one active source invalidates the whole hold session.
                on_resume()
                return
            now = time.monotonic()
            first_press = down and not ptt["held"]
            state.update(ptt, source, down, now, audio.set_muted, deliberate=deliberate)
            if first_press:
                # Reuse recent results and never queue duplicate in-flight work.
                if call_check is None or (
                    call_check.done() and now - call_checked_at >= CALL_CACHE_SECONDS
                ):
                    call_check = checker.submit(callstate.in_call)
                    call_checked_at = now

        def play_sound():
            # Use the result selected at press time; never wait on disk I/O.
            if call_check is not None and call_check.done():
                try:
                    in_call = call_check.result()
                except Exception as error:
                    logging.warning("Call-state check failed: %s", error)
                    return
                if in_call:
                    audio.play_sound()

        def on_resume():
            nonlocal call_check, call_checked_at
            blocked_sources.update(ptt["held"])
            state.reset(ptt, audio.set_muted)
            audio.close_sound()
            if call_check is not None:
                call_check.cancel()
            call_check = None
            call_checked_at = 0
            audio.pump()

        def on_tick():
            state.tick(ptt, time.monotonic(), audio.set_muted, play_sound)
            audio.pump()
            # Input threads wake the selector directly; idle audio needs less polling.
            timeout = 0.01 if audio.operations or audio.stream else 0.05
            if ptt["deadline"] is not None:
                timeout = min(timeout, max(0, ptt["deadline"] - time.monotonic()))
            return timeout

        inputs.run(on_event, on_tick, on_resume, stop)
    finally:
        stop.set()
        try:
            audio.close()
        finally:
            if checker is not None:
                checker.shutdown(wait=True, cancel_futures=True)
            callstate.close()


if __name__ == "__main__":
    main()
