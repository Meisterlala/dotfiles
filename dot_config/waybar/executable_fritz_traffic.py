#!/usr/bin/env python3
import json
import os
import sys
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path

import requests
from requests.auth import HTTPDigestAuth


SERVICE = "urn:dslforum-org:service:WANCommonInterfaceConfig:1"
ACTION = "X_AVM-DE_GetOnlineMonitor"
ICON_TRAFFIC = "󰤨"
ICON_ERROR = "󰤭"
SAMPLE_COUNT = 5

SOAP_BODY = f"""<?xml version="1.0"?>
<s:Envelope s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/" xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
  <s:Body>
    <u:{ACTION} xmlns:u="{SERVICE}">
      <NewSyncGroupIndex>0</NewSyncGroupIndex>
    </u:{ACTION}>
  </s:Body>
</s:Envelope>
"""


@dataclass(frozen=True)
class Config:
    url: str
    user: str
    password: str
    down_limit_mbit: float
    up_limit_mbit: float
    warn_at: float
    critical_at: float
    hide_at: float
    timeout_seconds: float
    hide_errors: bool
    state_file: Path


@dataclass(frozen=True)
class Traffic:
    down_mbit: float
    up_mbit: float

    def down_ratio(self, config: Config) -> float:
        return self.down_mbit / config.down_limit_mbit if config.down_limit_mbit > 0 else 0.0

    def up_ratio(self, config: Config) -> float:
        return self.up_mbit / config.up_limit_mbit if config.up_limit_mbit > 0 else 0.0

    def max_ratio(self, config: Config) -> float:
        return max(self.down_ratio(config), self.up_ratio(config))


def load_env_file() -> None:
    env_file = config_dir() / "waybar" / "fritz_traffic.env"
    if not env_file.exists():
        return

    try:
        lines = env_file.read_text(encoding="utf-8").splitlines()
    except OSError:
        return

    for line in lines:
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue

        key, value = line.split("=", 1)
        key = key.strip()
        if key and key not in os.environ:
            os.environ[key] = value.strip().strip('"').strip("'")


def config_dir() -> Path:
    return Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config")))


def cache_dir() -> Path:
    return Path(os.environ.get("XDG_CACHE_HOME", str(Path.home() / ".cache")))


def env_float(name: str, default: float) -> float:
    try:
        return float(os.environ.get(name, str(default)))
    except ValueError:
        return default


def load_config() -> Config:
    load_env_file()
    return Config(
        url=os.environ.get("FRITZBOX_URL", "http://fritz.box:49000").rstrip("/"),
        user=os.environ.get("FRITZBOX_USER", ""),
        password=os.environ.get("FRITZBOX_PASSWORD", ""),
        down_limit_mbit=env_float("FRITZ_TRAFFIC_DOWN_LIMIT_MBIT", 250),
        up_limit_mbit=env_float("FRITZ_TRAFFIC_UP_LIMIT_MBIT", 50),
        warn_at=env_float("FRITZ_TRAFFIC_WARN_AT", 0.75),
        critical_at=env_float("FRITZ_TRAFFIC_CRITICAL_AT", 0.90),
        hide_at=env_float("FRITZ_TRAFFIC_HIDE_AT", 0.65),
        timeout_seconds=env_float("FRITZ_TRAFFIC_TIMEOUT", 4),
        hide_errors=os.environ.get("FRITZ_TRAFFIC_HIDE_ERRORS", "1") == "1",
        state_file=cache_dir() / "waybar" / "fritz_traffic.json",
    )


def emit(text: str, tooltip: str = "", class_name: str = "") -> None:
    print(json.dumps({"text": text, "tooltip": tooltip, "class": class_name}, ensure_ascii=False))


def fail(config: Config, message: str) -> None:
    text = "" if config.hide_errors else ICON_ERROR
    emit(text, message, "error")
    sys.exit(0)


def fetch_online_monitor(config: Config) -> str:
    try:
        response = requests.post(
            f"{config.url}/upnp/control/wancommonifconfig1",
            data=SOAP_BODY.encode("utf-8"),
            headers={
                "Content-Type": 'text/xml; charset="utf-8"',
                "SOAPAction": f'"{SERVICE}#{ACTION}"',
            },
            auth=HTTPDigestAuth(config.user, config.password),
            timeout=config.timeout_seconds,
        )
    except requests.RequestException as exc:
        fail(config, f"FRITZ!Box traffic request failed: {exc}")

    if response.status_code == 401:
        fail(config, "FRITZ!Box rejected the configured user/password")
    if response.status_code >= 400:
        fail(config, f"FRITZ!Box traffic request failed: HTTP {response.status_code}")

    return response.text


def xml_text(root: ET.Element, name: str) -> str:
    for element in root.iter():
        if element.tag.endswith(name):
            return element.text or ""
    return ""


def parse_samples(raw: str) -> list[int]:
    samples: list[int] = []
    for part in raw.replace(";", ",").split(","):
        try:
            samples.append(int(part.strip()))
        except ValueError:
            pass
    return samples


def average_mbit(samples: list[int]) -> float:
    recent = samples[-SAMPLE_COUNT:]
    if not recent:
        return 0.0

    # FRITZ!OS names these fields *_bps, but this model returns bytes per second.
    return sum(recent) * 8 / len(recent) / 1_000_000


def parse_traffic(xml: str, config: Config) -> Traffic:
    try:
        root = ET.fromstring(xml)
    except ET.ParseError as exc:
        fail(config, f"Could not parse FRITZ!Box response: {exc}")

    return Traffic(
        down_mbit=average_mbit(parse_samples(xml_text(root, "Newds_current_bps"))),
        up_mbit=average_mbit(parse_samples(xml_text(root, "Newus_current_bps"))),
    )


def load_visible_state(config: Config) -> bool:
    try:
        return bool(json.loads(config.state_file.read_text(encoding="utf-8")).get("visible"))
    except Exception:
        return False


def save_visible_state(config: Config, visible: bool) -> None:
    try:
        config.state_file.parent.mkdir(parents=True, exist_ok=True)
        config.state_file.write_text(json.dumps({"visible": visible}), encoding="utf-8")
    except Exception:
        pass


def should_show(config: Config, traffic: Traffic) -> bool:
    ratio = traffic.max_ratio(config)
    visible = ratio >= config.warn_at or (load_visible_state(config) and ratio >= config.hide_at)
    save_visible_state(config, visible)
    return visible


def format_rate(mbit: float) -> str:
    if mbit >= 100:
        return f"{mbit:.0f}M"
    if mbit >= 10:
        return f"{mbit:.1f}M"
    return f"{mbit:.2f}M"


def tooltip(config: Config, traffic: Traffic) -> str:
    down_ratio = traffic.down_ratio(config) * 100
    up_ratio = traffic.up_ratio(config) * 100
    return (
        "FRITZ!Box traffic\n"
        f"Down: {traffic.down_mbit:.1f} / {config.down_limit_mbit:.0f} Mbit/s ({down_ratio:.0f}%)\n"
        f"Up:   {traffic.up_mbit:.1f} / {config.up_limit_mbit:.0f} Mbit/s ({up_ratio:.0f}%)"
    )


def module_text(config: Config, traffic: Traffic) -> str:
    parts = []
    if traffic.down_ratio(config) >= config.warn_at:
        parts.append(f"↓{format_rate(traffic.down_mbit)}")
    if traffic.up_ratio(config) >= config.warn_at:
        parts.append(f"↑{format_rate(traffic.up_mbit)}")
    return f"{ICON_TRAFFIC} {' '.join(parts)}"


def main() -> None:
    config = load_config()
    traffic = parse_traffic(fetch_online_monitor(config), config)
    tip = tooltip(config, traffic)

    if not should_show(config, traffic):
        emit("", tip, "normal")
        return

    class_name = "critical" if traffic.max_ratio(config) >= config.critical_at else "warning"
    emit(module_text(config, traffic), tip, class_name)


if __name__ == "__main__":
    main()
