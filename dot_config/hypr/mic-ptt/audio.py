"""Native libpulse calls, pumped by the input loop. No worker subprocesses.

This module owns one connection. The Structure declarations describe the C ABI
from pulse/introspect.h; application logic is plain functions and module state.
"""

import ctypes as C
import logging
import os
import time
import wave
from pathlib import Path

log = logging.getLogger(__name__)
P = C.c_void_p
U = C.c_uint32


class SampleSpec(C.Structure):
    _fields_ = [("format", C.c_int), ("rate", U), ("channels", C.c_uint8)]


class ChannelMap(C.Structure):
    _fields_ = [("channels", C.c_uint8), ("map", C.c_int * 32)]


class Volume(C.Structure):
    _fields_ = [("channels", C.c_uint8), ("values", U * 32)]


class SourceOutput(C.Structure):
    _fields_ = [
        ("index", U), ("name", C.c_char_p), ("owner_module", U),
        ("client", U), ("source", U), ("sample_spec", SampleSpec),
        ("channel_map", ChannelMap), ("buffer_usec", C.c_uint64),
        ("source_usec", C.c_uint64), ("resample_method", C.c_char_p),
        ("driver", C.c_char_p), ("proplist", P), ("corked", C.c_int),
        ("volume", Volume), ("mute", C.c_int),
    ]


InfoCallback = C.CFUNCTYPE(None, P, C.POINTER(SourceOutput), C.c_int, P)
EventCallback = C.CFUNCTYPE(None, P, C.c_int, U, P)
SuccessCallback = C.CFUNCTYPE(None, P, C.c_int, P)

lib = None
loop = None
context = None
operations = []
muted = True
controlling = False
failure = None
stream = None
drain = None
pcm = b""
spec = None


def load_library():
    library = C.CDLL("libpulse.so.0")
    # Explicit signatures prevent ctypes from truncating native pointers.
    signatures = {
        "pa_mainloop_new": (P, []),
        "pa_mainloop_get_api": (P, [P]),
        "pa_mainloop_iterate": (C.c_int, [P, C.c_int, P]),
        "pa_mainloop_free": (None, [P]),
        "pa_context_new": (P, [P, C.c_char_p]),
        "pa_context_connect": (C.c_int, [P, C.c_char_p, C.c_int, P]),
        "pa_context_get_state": (C.c_int, [P]),
        "pa_context_errno": (C.c_int, [P]),
        "pa_strerror": (C.c_char_p, [C.c_int]),
        "pa_context_disconnect": (None, [P]),
        "pa_context_unref": (None, [P]),
        "pa_context_set_subscribe_callback": (None, [P, EventCallback, P]),
        "pa_context_subscribe": (P, [P, C.c_int, SuccessCallback, P]),
        "pa_context_get_source_output_info_list": (P, [P, InfoCallback, P]),
        "pa_context_get_source_output_info": (P, [P, U, InfoCallback, P]),
        "pa_context_set_source_output_mute": (P, [P, U, C.c_int, SuccessCallback, P]),
        "pa_proplist_gets": (C.c_char_p, [P, C.c_char_p]),
        "pa_operation_get_state": (C.c_int, [P]),
        "pa_operation_unref": (None, [P]),
        "pa_stream_new": (P, [P, C.c_char_p, C.POINTER(SampleSpec), P]),
        "pa_stream_connect_playback": (C.c_int, [P, C.c_char_p, P, C.c_int, C.POINTER(Volume), P]),
        "pa_stream_get_state": (C.c_int, [P]),
        "pa_stream_write": (C.c_int, [P, P, C.c_size_t, P, C.c_int64, C.c_int]),
        "pa_stream_drain": (P, [P, P, P]),
        "pa_stream_disconnect": (C.c_int, [P]),
        "pa_stream_unref": (None, [P]),
    }
    for name, (result, args) in signatures.items():
        fn = getattr(library, name)
        fn.restype, fn.argtypes = result, args
    return library


def capture_app(binary, pid):
    if binary == "electron" and pid.isdecimal():
        try:
            for arg in Path(f"/proc/{pid}/cmdline").read_bytes().split(b"\0"):
                if arg.startswith(b"--user-data-dir="):
                    binary = os.path.basename(os.fsdecode(arg).rstrip("/"))
                    break
        except OSError:
            pass
    return binary in ("Discord", "yurios-desktop-shell")


def operation(op):
    if not op:
        raise RuntimeError("PulseAudio request could not be queued")
    operations.append(op)


@SuccessCallback
def subscribed(ctx, success, userdata):
    global failure
    if not success:
        failure = "Could not subscribe to capture streams"


@SuccessCallback
def mute_done(ctx, success, userdata):
    if not success:
        # A stream may have disappeared since enumeration.
        log.warning("Could not update capture mute: %s", error_message())


def error_message():
    return lib.pa_strerror(lib.pa_context_errno(context)).decode()


@InfoCallback
def source_info(ctx, info, eol, userdata):
    global failure
    if eol or not info:
        return
    try:
        source = info.contents
        def prop(key):
            value = lib.pa_proplist_gets(source.proplist, key)
            return value.decode(errors="replace") if value else ""
        if capture_app(prop(b"application.process.binary"), prop(b"application.process.id")):
            if not controlling:
                log.info("Found target capture stream %s (muted=%s)", source.index, bool(source.mute))
            elif bool(source.mute) != muted:
                operation(lib.pa_context_set_source_output_mute(
                    ctx, source.index, int(muted), mute_done, None))
    except Exception as error:
        # Never let a Python exception escape a C callback.
        failure = str(error)


@EventCallback
def source_event(ctx, event, index, userdata):
    global failure
    # New/changed source outputs, not removals or other object types.
    if (event & 15) == 3 and (event & 48) != 32:
        try:
            operation(lib.pa_context_get_source_output_info(ctx, index, source_info, None))
        except Exception as error:
            failure = str(error)


def connect(sound, *, control=True):
    global lib, loop, context, muted, controlling, failure, pcm, spec
    lib = load_library()
    muted, controlling, failure, pcm = True, control, None, b""
    try:
        with wave.open(str(sound), "rb") as wav:
            if wav.getsampwidth() != 2 or wav.getcomptype() != "NONE":
                raise ValueError("notification must be 16-bit PCM WAV")
            spec = SampleSpec(3, wav.getframerate(), wav.getnchannels())  # S16LE
            pcm = wav.readframes(wav.getnframes())
    except (OSError, ValueError, wave.Error) as error:
        log.warning("Notification disabled: %s", error)
    try:
        loop = lib.pa_mainloop_new()
        if not loop:
            raise RuntimeError("Could not allocate PulseAudio mainloop")
        context = lib.pa_context_new(lib.pa_mainloop_get_api(loop), b"Microphone push-to-talk")
        if not context or lib.pa_context_connect(context, None, 0, None) < 0:
            raise RuntimeError("Could not connect to PulseAudio")
        deadline = time.monotonic() + 5
        while lib.pa_context_get_state(context) != 4:  # READY
            pump()
            if time.monotonic() > deadline:
                raise RuntimeError("PulseAudio connection timed out")
            time.sleep(0.01)
        lib.pa_context_set_subscribe_callback(context, source_event, None)
        operation(lib.pa_context_subscribe(context, 8, subscribed, None))  # SOURCE_OUTPUT
        refresh()
    except BaseException:
        close()
        raise


def refresh():
    operation(lib.pa_context_get_source_output_info_list(context, source_info, None))


def set_muted(value):
    global muted
    muted = value
    refresh()


def pump():
    if lib.pa_mainloop_iterate(loop, 0, None) < 0:
        raise RuntimeError("PulseAudio mainloop failed")
    if failure:
        raise RuntimeError(failure)
    if lib.pa_context_get_state(context) in (5, 6):
        raise RuntimeError(f"PulseAudio disconnected: {error_message()}")
    pending = []
    for op in operations:
        if lib.pa_operation_get_state(op) == 0:
            pending.append(op)
        else:
            lib.pa_operation_unref(op)
    operations[:] = pending
    pump_sound()


def play_sound():
    global stream
    if not pcm:
        return
    close_sound()
    stream = lib.pa_stream_new(context, b"PTT release", C.byref(spec), None)
    if not stream:
        log.warning("Could not create notification stream")
        return
    volume = Volume(spec.channels)
    for i in range(spec.channels):
        volume.values[i] = 49152  # Preserve the old paplay volume.
    if lib.pa_stream_connect_playback(stream, None, None, 0, C.byref(volume), None) < 0:
        close_sound()


def pump_sound():
    global drain
    if not stream:
        return
    state = lib.pa_stream_get_state(stream)
    if state in (3, 4):  # FAILED / TERMINATED
        close_sound()
    elif state == 2 and not drain:  # READY
        # NULL free callback asks libpulse to copy the short PCM sample.
        if lib.pa_stream_write(stream, pcm, len(pcm), None, 0, 0) < 0:
            close_sound()
            return
        drain = lib.pa_stream_drain(stream, None, None)
        if not drain:
            close_sound()
    elif drain and lib.pa_operation_get_state(drain) != 0:
        close_sound()


def close_sound():
    global stream, drain
    if drain:
        lib.pa_operation_unref(drain)
        drain = None
    if stream:
        lib.pa_stream_disconnect(stream)
        lib.pa_stream_unref(stream)
        stream = None


def close():
    global context, loop
    if controlling and context and lib.pa_context_get_state(context) == 4:
        try:
            set_muted(True)
            deadline = time.monotonic() + 1
            while operations and time.monotonic() < deadline:
                pump()
                time.sleep(0.005)
        except RuntimeError:
            pass
    close_sound()
    for op in operations:
        lib.pa_operation_unref(op)
    operations.clear()
    if context:
        lib.pa_context_disconnect(context)
        lib.pa_context_unref(context)
        context = None
    if loop:
        lib.pa_mainloop_free(loop)
        loop = None
