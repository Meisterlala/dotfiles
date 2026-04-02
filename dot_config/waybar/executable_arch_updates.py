#!/usr/bin/env python3
import datetime as dt
import json
import os
import re
import subprocess
from pathlib import Path

PARU_TIMEOUT = int(os.environ.get("WAYBAR_UPDATES_TIMEOUT", "120"))
MAX_LIST = int(os.environ.get("WAYBAR_UPDATES_MAX_LIST", "120"))


def parse_duration(value: str, default_seconds: int) -> dt.timedelta:
    value = (value or "").strip().lower()
    if not value:
        return dt.timedelta(seconds=default_seconds)

    total = 0
    for amount, unit in re.findall(r"(\d+)\s*([smhd])", value):
        n = int(amount)
        if unit == "s":
            total += n
        elif unit == "m":
            total += n * 60
        elif unit == "h":
            total += n * 3600
        elif unit == "d":
            total += n * 86400

    if total <= 0:
        return dt.timedelta(seconds=default_seconds)
    return dt.timedelta(seconds=total)


REMIND_INTERVAL = parse_duration(
    os.environ.get("WAYBAR_UPDATES_REMIND_INTERVAL", "12h"), 12 * 3600
)

LINE_RE = re.compile(
    r"^(?P<pkg>\S+)\s+(?P<old>\S+)\s+->\s+(?P<new>\S+)(?:\s+\[(?P<flag>[^\]]+)\])?$"
)


def run_cmd(args: list[str], timeout: int = PARU_TIMEOUT) -> tuple[int, str, str]:
    try:
        proc = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
        return proc.returncode, proc.stdout, proc.stderr
    except Exception as exc:
        return 1, "", str(exc)


def parse_upgrade_lines(raw: str) -> list[dict]:
    updates: list[dict] = []
    for line in raw.splitlines():
        line = line.strip()
        if not line:
            continue
        match = LINE_RE.match(line)
        if not match:
            continue
        flag = (match.group("flag") or "").lower()
        if "ignored" in flag:
            continue
        updates.append(
            {
                "name": match.group("pkg"),
                "old": match.group("old"),
                "new": match.group("new"),
            }
        )
    return updates


def repo_for_packages(package_names: list[str]) -> dict[str, str]:
    if not package_names:
        return {}

    code, out, _ = run_cmd(["pacman", "-Si", *package_names], timeout=90)
    if code != 0 or not out:
        return {name: "repo" for name in package_names}

    result: dict[str, str] = {}
    current_name = ""
    current_repo = "repo"

    def flush_block() -> None:
        if current_name:
            result[current_name] = current_repo or "repo"

    for raw_line in out.splitlines() + [""]:
        line = raw_line.strip()
        if not line:
            flush_block()
            current_name = ""
            current_repo = "repo"
            continue
        if line.startswith("Name"):
            parts = line.split(":", 1)
            current_name = parts[1].strip() if len(parts) > 1 else ""
        elif line.startswith("Repository"):
            parts = line.split(":", 1)
            current_repo = parts[1].strip() if len(parts) > 1 else "repo"
    for name in package_names:
        result.setdefault(name, "repo")
    return result


def pango_escape(text: str) -> str:
    return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def state_file() -> Path:
    cache = (
        Path(os.environ.get("XDG_CACHE_HOME", str(Path.home() / ".cache"))) / "waybar"
    )
    return cache / "arch-updates-state.json"


def load_state(path: Path) -> dict:
    if not path.exists():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}


def save_state(path: Path, state: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(state, ensure_ascii=False, indent=2), encoding="utf-8")


def last_completed_upgrade_epoch() -> int:
    log_path = Path("/var/log/pacman.log")
    if not log_path.exists():
        return 0
    latest = 0
    pending_full_upgrade = 0
    marker = "starting full system upgrade"
    completed_marker = "[ALPM] transaction completed"
    try:
        with log_path.open("r", encoding="utf-8", errors="ignore") as fh:
            for line in fh:
                if not line.startswith("[") or len(line) < 20:
                    continue
                stamp = line[1:20]
                try:
                    ts = int(dt.datetime.strptime(stamp, "%Y-%m-%dT%H:%M:%S").timestamp())
                except Exception:
                    continue

                if marker in line:
                    pending_full_upgrade = ts
                    continue

                if pending_full_upgrade and completed_marker in line:
                    latest = max(latest, pending_full_upgrade)
                    pending_full_upgrade = 0
    except Exception:
        return 0
    return latest


def classify_updates(repo_updates: list[dict], aur_updates: list[dict]) -> list[dict]:
    mapping = repo_for_packages([item["name"] for item in repo_updates])
    result: list[dict] = []

    for item in repo_updates:
        source = mapping.get(item["name"], "repo").lower()
        result.append({**item, "source": source})

    for item in aur_updates:
        source = "devel" if item["new"] == "latest-commit" else "aur"
        result.append({**item, "source": source})

    order = {"core": 0, "extra": 1, "multilib": 2, "aur": 3, "devel": 4, "repo": 5}
    result.sort(key=lambda x: (order.get(x["source"], 9), x["name"]))
    return result


def build_tooltip(items: list[dict]) -> str:
    colors = {
        "core": "#f38ba8",
        "extra": "#89dceb",
        "multilib": "#b4befe",
        "aur": "#f9e2af",
        "devel": "#fab387",
        "repo": "#94e2d5",
    }
    counts: dict[str, int] = {}
    for item in items:
        counts[item["source"]] = counts.get(item["source"], 0) + 1

    summary = []
    for key in ["core", "extra", "multilib", "aur", "devel"]:
        if counts.get(key, 0) > 0:
            summary.append(
                f"<span foreground='{colors[key]}'>{key}: {counts[key]}</span>"
            )

    lines = ["<b>Available updates</b>"]
    if summary:
        lines.append("  ".join(summary))
    lines.append("")

    for item in items[:MAX_LIST]:
        src = item["source"]
        src_color = colors.get(src, "#a6adc8")
        lines.append(
            f"<span foreground='{src_color}'>{src}</span>/<b>{pango_escape(item['name'])}</b> "
            f"<span foreground='#a6adc8'>{pango_escape(item['old'])}</span> "
            f"<span foreground='#89b4fa'>-></span> "
            f"<span foreground='#cdd6f4'>{pango_escape(item['new'])}</span>"
        )

    if len(items) > MAX_LIST:
        lines.append("")
        lines.append(
            f"<span foreground='#a6adc8'>... and {len(items) - MAX_LIST} more</span>"
        )

    return "<tt>" + "\n".join(lines).strip() + "</tt>"


def main() -> None:
    state_path = state_file()
    state = load_state(state_path)
    now = dt.datetime.now()

    # Keep a tiny state: last seen full-upgrade timestamp + snooze-until.
    latest_upgrade = last_completed_upgrade_epoch()
    prev_upgrade = int(state.get("last_upgrade_epoch", 0) or 0)
    if latest_upgrade and latest_upgrade != prev_upgrade:
        state["last_upgrade_epoch"] = latest_upgrade
        state["snooze_until"] = (
            dt.datetime.fromtimestamp(latest_upgrade) + REMIND_INTERVAL
        ).isoformat(timespec="seconds")
        save_state(state_path, state)

    snooze_until_raw = str(state.get("snooze_until", "")).strip()
    if snooze_until_raw:
        try:
            snooze_until = dt.datetime.fromisoformat(snooze_until_raw)
            if now < snooze_until:
                print(
                    json.dumps(
                        {
                            "text": "",
                            "tooltip": "",
                            "class": "updated",
                            "alt": "updated",
                            "percentage": 0,
                        }
                    )
                )
                return
        except Exception:
            pass

    repo_code, repo_out, repo_err = run_cmd(
        ["paru", "-Qu", "--repo", "--color", "never"]
    )
    aur_code, aur_out, aur_err = run_cmd(
        ["paru", "-Qua", "--devel", "--color", "never"]
    )

    if repo_code != 0 and aur_code != 0:
        tooltip = pango_escape(
            (repo_err or aur_err or "Failed to query updates").strip()
        )
        print(
            json.dumps(
                {"text": "", "tooltip": tooltip, "class": "error", "alt": "error"}
            )
        )
        return

    repo_updates = parse_upgrade_lines(repo_out)
    aur_updates = parse_upgrade_lines(aur_out)
    items = classify_updates(repo_updates, aur_updates)

    if not items:
        print(
            json.dumps(
                {
                    "text": "",
                    "tooltip": "System is up to date",
                    "class": "updated",
                    "alt": "updated",
                }
            )
        )
        state["snooze_until"] = ""
        save_state(state_path, state)
        return

    tooltip = build_tooltip(items)

    count = len(items)
    level = "critical" if count >= 50 else "warning" if count >= 15 else "normal"
    print(
        json.dumps(
            {
                "text": str(count),
                "tooltip": tooltip,
                "class": ["updates", level],
                "alt": level,
                "percentage": min(100, count),
            }
        )
    )
    state["snooze_until"] = ""
    save_state(state_path, state)


if __name__ == "__main__":
    main()
