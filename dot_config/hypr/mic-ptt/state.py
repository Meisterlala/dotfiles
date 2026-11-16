"""Button aggregation and the cancellable release delay."""

RELEASE_DELAY_SECONDS = 0.05


def update(state, source, down, now, set_muted, *, deliberate=True):
    was_talking = bool(state["held"])
    if down:
        state["held"].add(source)
    else:
        state["held"].discard(source)
    if state["held"]:
        # During release debounce the mic is still open: just cancel the mute.
        if not was_talking and state["deadline"] is None:
            set_muted(False)
        state["deadline"] = None
    elif was_talking:
        if deliberate:
            state["deadline"] = now + RELEASE_DELAY_SECONDS
        else:
            # Lost input is a safety mute, never a user notification.
            state["deadline"] = None
            set_muted(True)


def reset(state, set_muted):
    state["held"].clear()
    state["deadline"] = None
    set_muted(True)


def tick(state, now, set_muted, play_sound):
    if state["deadline"] is not None and now >= state["deadline"]:
        state["deadline"] = None
        set_muted(True)
        play_sound()
