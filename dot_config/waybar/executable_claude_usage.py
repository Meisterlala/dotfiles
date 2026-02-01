#!/usr/bin/env python3
"""
Fetch Claude (Anthropic) usage and print JSON for Waybar.
"""

import datetime
import json
import os
import urllib.request
import urllib.error


def load_token():
    paths = [
        os.environ.get("CLAUDE_CREDENTIALS"),
        "~/.claude/.credentials.json",
    ]
    for p in paths:
        if not p:
            continue
        p = os.path.expanduser(p)
        if not os.path.exists(p):
            continue
        try:
            with open(p, "r", encoding="utf-8") as f:
                data = json.load(f)
                # Specific check for Claude Code credentials format
                token = data.get("claudeAiOauth", {}).get("accessToken")
                if token:
                    return token
                # Fallback for generic formats
                for k in ["accessToken", "access_token", "token"]:
                    if k in data:
                        return data[k]
        except Exception:
            continue
    return None


def parse_dt(s):
    if not s:
        return None
    try:
        return datetime.datetime.fromisoformat(s.replace("Z", "+00:00"))
    except Exception:
        return None


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


def get_pct(val):
    try:
        v = float(val)
        return int(round(v * 100 if v <= 1.1 else v))
    except (ValueError, TypeError):
        return None


def main():
    token = load_token()
    if not token:
        print(
            json.dumps(
                {"text": "Claude: n/a", "tooltip": "No token found", "class": "error"}
            )
        )
        return

    req = urllib.request.Request(
        "https://api.anthropic.com/api/oauth/usage",
        headers={
            "Authorization": f"Bearer {token}",
            "anthropic-beta": "oauth-2025-04-20",
            "User-Agent": "claude-code/2.0.0",
        },
    )

    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = json.load(resp)
    except urllib.error.HTTPError as e:
        # If this is an authentication error, hide the text (Waybar should show nothing)
        if getattr(e, "code", None) == 401:
            print(json.dumps({"text": "", "tooltip": "", "class": "error"}))
            return
        print(json.dumps({"text": "Claude: err", "tooltip": str(e), "class": "error"}))
        return
    except Exception as e:
        print(json.dumps({"text": "Claude: err", "tooltip": str(e), "class": "error"}))
        return

    now = datetime.datetime.now(datetime.timezone.utc)
    windows = {
        "5h": data.get("five_hour") or {},
        "weekly": data.get("seven_day") or data.get("weekly") or {},
    }

    five_pct = get_pct(windows["5h"].get("utilization") or data.get("utilization"))
    weekly_pct = get_pct(windows["weekly"].get("utilization"))

    tooltip = []
    for label, win in windows.items():
        pct = get_pct(win.get("utilization"))
        if pct is None and label == "5h":
            pct = five_pct
        if pct is None:
            continue

        tooltip.append(f"<span weight='bold' color='#b4befe'>{label} window</span>")
        tooltip.append(f"usage: <span color='#fab387'>{pct}%</span>")

        resets_at = parse_dt(win.get("resets_at"))
        if resets_at:
            human = human_delta(resets_at, now)
            fmt = "%H:%M" if label == "5h" else "%d.%m.%Y"
            tstr = resets_at.astimezone().strftime(fmt)
            tooltip.append(f"reset in: <span color='#f9e2af'><b>{human}</b></span>")
            tooltip.append(f"reset at: <span color='#a6adc8'>{tstr}</span>")
        tooltip.append("")

    # Class logic
    max_pct = max(filter(None, [five_pct, weekly_pct]), default=0)
    cls = "critical" if max_pct >= 90 else "warning" if max_pct >= 66 else "normal"

    # Hide text only when usage is 100% (which incorrectly means full budget/0% used)
    text = "" if five_pct == 100 else (f"{five_pct}%" if five_pct else "")

    print(
        json.dumps(
            {
                "text": text,
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
