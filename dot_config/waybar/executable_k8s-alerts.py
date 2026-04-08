#!/usr/bin/env python3
import json
import os
import re
import subprocess
import sys
from urllib.parse import urlparse
from pathlib import Path
from xml.sax.saxutils import escape as xml_escape


ICON_ALERT = ""
ICON_ERROR = ""
TIMEOUT = os.environ.get("K8S_ALERTS_TIMEOUT", "8s")
WRAP_WIDTH = int(os.environ.get("K8S_ALERTS_WRAP_WIDTH", "60"))
URL_RE = re.compile(r"https?://[^\s)\]>\"']+")
BREAK_CHARS = " /-._:?&="


def split_segments_with_urls(text: str) -> list[tuple[str, bool]]:
    segments: list[tuple[str, bool]] = []
    last = 0
    for match in URL_RE.finditer(text):
        start, end = match.span()
        if start > last:
            segments.append((text[last:start], False))

        raw_url = match.group(0)
        parsed = urlparse(raw_url)
        host = (parsed.netloc or parsed.path).rstrip("/")
        display = host or raw_url
        segments.append((display, True))
        last = end

    if last < len(text):
        segments.append((text[last:], False))

    if not segments:
        segments.append((text, False))
    return segments


def wrap_segments(segments: list[tuple[str, bool]], width: int) -> list[list[tuple[str, bool]]]:
    lines: list[list[tuple[str, bool]]] = [[]]
    current_len = 0

    def new_line() -> None:
        nonlocal current_len
        lines.append([])
        current_len = 0

    for text, is_url in segments:
        remaining_text = text
        while remaining_text:
            if current_len >= width:
                new_line()

            room = max(1, width - current_len)
            if len(remaining_text) <= room:
                chunk = remaining_text
                remaining_text = ""
            else:
                chunk = remaining_text[:room]
                break_at = -1
                for ch in BREAK_CHARS:
                    idx = chunk.rfind(ch)
                    if idx > break_at:
                        break_at = idx
                if break_at > 0:
                    chunk = remaining_text[: break_at + 1]
                elif not is_url and current_len > 0:
                    new_line()
                    continue
                remaining_text = remaining_text[len(chunk) :]

            if current_len == 0:
                chunk = chunk.lstrip()
                if not chunk:
                    continue

            lines[-1].append((chunk, is_url))
            current_len += len(chunk)

    if not lines[-1]:
        lines.pop()
    return lines or [[("", False)]]


def render_wrapped_line(raw_line: str, width: int) -> list[str]:
    segments = split_segments_with_urls(raw_line)
    wrapped = wrap_segments(segments, width)
    rendered: list[str] = []
    for line in wrapped:
        out = ""
        for chunk, is_url in line:
            esc = xml_escape(chunk)
            if is_url:
                out += f"<span foreground='#89b4fa'>{esc}</span>"
            else:
                out += esc
        rendered.append(out)
    return rendered


def emit(text: str, tooltip: str, class_name: str) -> None:
    print(json.dumps({"text": text, "tooltip": tooltip, "class": class_name}, ensure_ascii=False))


def error_out(message: str) -> None:
    tip = f"<span foreground='#f38ba8'><b>Cluster error</b></span>\r{xml_escape(message)}"
    emit(ICON_ERROR, tip, "critical")
    sys.exit(0)


def run_kubectl(args: list[str]) -> str:
    cmd = ["kubectl", f"--request-timeout={TIMEOUT}", *args]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        return ""
    return proc.stdout


def find_cache_file() -> Path:
    cache_home = Path(os.environ.get("XDG_CACHE_HOME", str(Path.home() / ".cache"))) / "waybar"
    try:
        cache_home.mkdir(parents=True, exist_ok=True)
        return cache_home / "alertmanager-namespace"
    except Exception:
        return Path(f"/tmp/waybar-alertmanager-namespace-{os.getuid()}")


def discover_namespace() -> str:
    raw = run_kubectl(["get", "svc", "-A", "-o", "json"])
    if not raw:
        return ""
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return ""
    for item in data.get("items", []):
        md = item.get("metadata", {})
        if md.get("name") == "alertmanager-operated":
            return md.get("namespace", "")
    return ""


def get_namespace(cache_file: Path) -> str:
    env_ns = os.environ.get("ALERTMANAGER_NAMESPACE", "").strip()
    if env_ns:
        return env_ns
    if cache_file.exists():
        cached = cache_file.read_text(encoding="utf-8").strip()
        if cached:
            return cached
    ns = discover_namespace()
    if ns:
        try:
            cache_file.write_text(ns + "\n", encoding="utf-8")
        except Exception:
            pass
    return ns


def format_alert(alert: dict) -> str:
    labels = alert.get("labels", {})
    ann = alert.get("annotations", {})
    sev = str(labels.get("severity", "unknown")).lower()
    name = xml_escape(str(labels.get("alertname", "unknown")))
    ns = xml_escape(str(labels.get("namespace", "-")))
    msg = str(ann.get("summary") or ann.get("description") or ann.get("message") or "")
    msg = msg.replace("\\n", "\n")

    name_color = "#cdd6f4"
    if sev in ("critical", "error"):
        name_color = "#f38ba8"
    elif sev == "warning":
        name_color = "#f9e2af"

    header = f"<b><span foreground='{name_color}'>{name}</span></b> <span foreground='#bac2de'>({ns})</span>:"
    if not msg:
        return header

    wrapped_lines: list[str] = []
    for raw_line in (msg.splitlines() or [msg]):
        if not raw_line:
            wrapped_lines.append("")
            continue
        wrapped_lines.extend(render_wrapped_line(raw_line, WRAP_WIDTH))

    rendered_lines: list[str] = []
    for line in wrapped_lines:
        rendered_lines.append(f"    {line}")

    indented = "\r".join(rendered_lines)
    return f"{header}\r{indented}"


def main() -> None:
    if subprocess.run(["kubectl", "version", "--client"], capture_output=True).returncode != 0:
        error_out("Missing dependency: kubectl")

    ctx = subprocess.run(["kubectl", "config", "current-context"], capture_output=True, text=True)
    if ctx.returncode != 0 or not ctx.stdout.strip():
        error_out("No current Kubernetes context configured.")

    cache_file = find_cache_file()
    namespace = get_namespace(cache_file)
    if not namespace:
        error_out("Cannot find Alertmanager service (alertmanager-operated).")

    raw = run_kubectl([
        "get",
        "--raw",
        f"/api/v1/namespaces/{namespace}/services/http:alertmanager-operated:9093/proxy/api/v2/alerts",
    ])
    if not raw:
        refreshed = discover_namespace()
        if refreshed and refreshed != namespace:
            namespace = refreshed
            try:
                cache_file.write_text(namespace + "\n", encoding="utf-8")
            except Exception:
                pass
            raw = run_kubectl([
                "get",
                "--raw",
                f"/api/v1/namespaces/{namespace}/services/http:alertmanager-operated:9093/proxy/api/v2/alerts",
            ])

    if not raw:
        error_out("Cannot connect to cluster or Alertmanager API.")

    alerts: list[dict] = []
    try:
        alerts = json.loads(raw)
    except json.JSONDecodeError:
        error_out("Invalid JSON returned by Alertmanager API.")

    active = [a for a in alerts if a.get("status", {}).get("state") == "active"]
    watchdog_running = any(a.get("labels", {}).get("alertname", "") == "Watchdog" for a in active)

    visible = [
        a
        for a in active
        if a.get("labels", {}).get("alertname", "") not in ("Watchdog", "InfoInhibitor")
    ]

    severities = {str(a.get("labels", {}).get("severity", "")).lower() for a in visible}
    alert_class = "warning"
    if "critical" in severities:
        alert_class = "critical"
    elif "error" in severities:
        alert_class = "error"

    visible_sorted = sorted(
        visible,
        key=lambda a: (
            str(a.get("labels", {}).get("severity", "unknown")),
            str(a.get("labels", {}).get("alertname", "unknown")),
            str(a.get("labels", {}).get("namespace", "-")),
        ),
    )

    tooltip_lines = [format_alert(a) for a in visible_sorted]
    tooltip = "\r".join(tooltip_lines) if tooltip_lines else "<span foreground='#a6adc8'>No active alerts</span>"

    if not watchdog_running:
        emit(ICON_ERROR, f"<b><span foreground='#f38ba8'>Watchdog alert is missing</span></b>\r\r{tooltip}", "critical")
        return

    if visible:
        icon = ICON_ALERT
        if alert_class == "critical":
            icon = ICON_ERROR
        emit(f"{icon} {len(visible)}", tooltip, alert_class)
        return

    emit("", "", "ok")


if __name__ == "__main__":
    main()
