#!/usr/bin/env python3
"""
Fetch OpenAI Codex (ChatGPT plan) usage and print JSON for Waybar.
"""

import datetime
import json
import subprocess


def human_delta(dt, now):
    if not dt:
        return ""
    delta = dt - now
    secs = int(delta.total_seconds())
    if secs <= 0:
        return "now"

    days, rem = divmod(secs, 86400)
    hours, rem = divmod(rem, 3600)
    mins, _ = divmod(rem, 60)

    res = []
    if days:
        res.append(f"{days}d")
    if hours:
        res.append(f"{hours}h")
    res.append(f"{mins}m")
    return "".join(res)


def call_rate_limits():
    req_init = {
        "jsonrpc": "2.0",
        "id": "1",
        "method": "initialize",
        "params": {
            "clientInfo": {"name": "waybar-codex-usage", "version": "1.0"},
            "capabilities": {"experimentalApi": True},
        },
    }
    req_limits = {
        "jsonrpc": "2.0",
        "id": "2",
        "method": "account/rateLimits/read",
        "params": {},
    }
    req_initialized = {"jsonrpc": "2.0", "method": "initialized", "params": {}}

    proc = subprocess.Popen(
        ["codex", "app-server"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )

    assert proc.stdin is not None
    proc.stdin.write(json.dumps(req_init) + "\n")
    proc.stdin.write(json.dumps(req_initialized) + "\n")
    proc.stdin.write(json.dumps(req_limits) + "\n")
    proc.stdin.close()

    try:
        lines = []
        for _ in range(20):
            line = proc.stdout.readline() if proc.stdout else ""
            if not line:
                break
            lines.append(line.strip())
            try:
                msg = json.loads(line)
            except json.JSONDecodeError:
                continue
            if str(msg.get("id")) == "2":
                res = msg.get("result") or {}
                return (res.get("rateLimits") or {}), None
        err = (proc.stderr.read() if proc.stderr else "").strip()
        return None, err or "No account/rateLimits/read response from codex app-server"
    finally:
        try:
            proc.terminate()
            proc.wait(timeout=1)
        except Exception:
            try:
                proc.kill()
            except Exception:
                pass


def main():
    try:
        limits, err = call_rate_limits()
    except FileNotFoundError:
        print(
            json.dumps(
                {
                    "text": "Codex: n/a",
                    "tooltip": "codex CLI not found",
                    "class": "error",
                }
            )
        )
        return
    except Exception as e:
        print(
            json.dumps(
                {"text": "Codex: err", "tooltip": f"{e}", "class": "error"}
            )
        )
        return

    if not limits:
        print(
            json.dumps(
                {
                    "text": "Codex: n/a",
                    "tooltip": err or "No usage data (run `codex login`)",
                    "class": "error",
                }
            )
        )
        return

    now = datetime.datetime.now(datetime.timezone.utc)
    primary = limits.get("primary") or {}
    secondary = limits.get("secondary") or {}
    credits = limits.get("credits") or {}

    primary_pct = int(round(float(primary.get("usedPercent", 0))))
    secondary_pct = int(round(float(secondary.get("usedPercent", 0))))
    max_pct = max(primary_pct, secondary_pct)

    cls = "critical" if max_pct >= 90 else "warning" if max_pct >= 66 else "normal"

    tooltip = []
    windows = [
        ("5h window", primary),
        ("weekly window", secondary),
    ]
    for label, win in windows:
        if not win:
            continue
        used = int(round(float(win.get("usedPercent", 0))))
        mins = win.get("windowDurationMins")
        resets_at = win.get("resetsAt")
        reset_dt = (
            datetime.datetime.fromtimestamp(int(resets_at), datetime.timezone.utc)
            if resets_at is not None
            else None
        )

        tooltip.append(f"<span weight='bold' color='#b4befe'>{label}</span>")
        tooltip.append(f"used: <span color='#fab387'>{used}%</span>")
        if reset_dt:
            tooltip.append(
                f"reset in: <span color='#f9e2af'><b>{human_delta(reset_dt, now)}</b></span>"
            )
            fmt = "%H:%M" if (mins or 0) <= 300 else "%d.%m.%Y"
            tooltip.append(
                f"reset at: <span color='#a6adc8'>{reset_dt.astimezone().strftime(fmt)}</span>"
            )
        tooltip.append("")

    if credits and (credits.get("hasCredits") or credits.get("unlimited")):
        tooltip.append("<span weight='bold' color='#b4befe'>credits</span>")
        tooltip.append(
            f"has credits: <span color='#a6adc8'>{str(credits.get('hasCredits', False)).lower()}</span>"
        )
        tooltip.append(
            f"unlimited: <span color='#a6adc8'>{str(credits.get('unlimited', False)).lower()}</span>"
        )
        bal = credits.get("balance")
        if bal is not None:
            tooltip.append(f"balance: <span color='#a6adc8'>{bal}</span>")

    print(
        json.dumps(
            {
                "text": f"{primary_pct}%",
                "tooltip": f"<tt>{'\n'.join(tooltip).strip()}</tt>"
                if tooltip
                else "No usage data",
                "class": cls,
                "percentage": max_pct,
            }
        )
    )


if __name__ == "__main__":
    main()
