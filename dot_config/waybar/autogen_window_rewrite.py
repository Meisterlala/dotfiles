#!/usr/bin/env python3

import argparse
import json
import logging
import os
import re
import shlex
import shutil
import subprocess
import sys
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

try:
    from systemd.journal import JournalHandler
except Exception:
    JournalHandler = None

NERDFONT_GLYPHS_URL = (
    "https://raw.githubusercontent.com/ryanoasis/nerd-fonts/master/glyphnames.json"
)
NERDFONT_ICON_CATALOG_PATH = Path.home() / ".config/waybar/nerdfont-icons.txt"


def chezmoi_available() -> bool:
    return shutil.which("chezmoi") is not None


def resolve_config_path_for_chezmoi(
    config_target_path: Path,
) -> tuple[Path, Path | None]:
    """
    Returns (path_to_read_write, apply_target_path_or_none).
    If target is chezmoi-managed, read/write source file and later apply target path.
    """
    if not chezmoi_available():
        logging.debug("chezmoi not found; using direct config path")
        return config_target_path, None

    managed = subprocess.run(
        ["chezmoi", "managed", str(config_target_path)],
        capture_output=True,
        text=True,
    )
    if managed.returncode != 0:
        logging.debug("Config is not managed by chezmoi: %s", config_target_path)
        return config_target_path, None

    source = subprocess.run(
        ["chezmoi", "source-path", str(config_target_path)],
        check=True,
        capture_output=True,
        text=True,
    )
    source_path = Path(source.stdout.strip())
    logging.info("Config is chezmoi-managed; writing source file: %s", source_path)
    return source_path, config_target_path


def chezmoi_apply_target(target_path: Path) -> None:
    logging.info("Applying chezmoi target: %s", target_path)
    subprocess.run(
        ["chezmoi", "apply", str(target_path)],
        check=True,
        capture_output=True,
        text=True,
    )


def reload_waybar() -> None:
    logging.info("Reloading waybar via SIGUSR2")
    subprocess.run(
        ["killall", "-SIGUSR2", "waybar"],
        check=True,
        capture_output=True,
        text=True,
    )


def strip_jsonc(text: str) -> str:
    text = re.sub(r"//.*$", "", text, flags=re.MULTILINE)
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.DOTALL)
    text = re.sub(r",\s*([}\]])", r"\1", text)
    return text


def load_jsonc(path: Path) -> dict:
    data = strip_jsonc(path.read_text(encoding="utf-8"))
    return json.loads(data)


def parse_rule_key(rule_key: str):
    class_match = re.search(r"class<(.+?)>", rule_key)
    title_match = re.search(r"title<(.+?)>", rule_key)
    class_pat = class_match.group(1) if class_match else None
    title_pat = title_match.group(1) if title_match else None
    return class_pat, title_pat


def rule_matches(rule_key: str, window_class: str, window_title: str) -> bool:
    class_pat, title_pat = parse_rule_key(rule_key)
    if class_pat is not None and not re.fullmatch(class_pat, window_class):
        return False
    if title_pat is not None and not re.fullmatch(title_pat, window_title):
        return False
    if class_pat is None and title_pat is None:
        return False
    return True


def has_equivalent_class_rule(
    existing_rules: dict[str, str], window_class: str
) -> bool:
    """
    Treat class rules as equivalent when they differ only by case, eg Discord vs discord.
    This avoids duplicate mappings for the same app class.
    """
    target = window_class.casefold()
    for rule_key in existing_rules:
        class_pat, title_pat = parse_rule_key(rule_key)
        if title_pat is not None or class_pat is None:
            continue
        if class_pat.casefold() == target:
            return True
    return False


def get_open_windows() -> list[dict[str, str]]:
    proc = subprocess.run(
        ["hyprctl", "clients", "-j"],
        check=True,
        capture_output=True,
        text=True,
    )
    clients = json.loads(proc.stdout)
    windows = []
    for c in clients:
        cls = c.get("class") or c.get("initialClass") or ""
        title = c.get("title") or c.get("initialTitle") or ""
        if cls:
            windows.append(
                {
                    "class": cls,
                    "title": title,
                    "initialClass": c.get("initialClass") or "",
                    "initialTitle": c.get("initialTitle") or "",
                    "address": c.get("address") or "",
                    "workspace": str((c.get("workspace") or {}).get("name") or ""),
                    "pid": str(c.get("pid") or ""),
                    "xwayland": str(c.get("xwayland") or ""),
                    "mapped": str(c.get("mapped") or ""),
                }
            )
    return windows


def extract_unknown_classes(
    existing_rules: dict[str, str], windows: list[dict[str, str]]
) -> dict[str, dict]:
    unknown: dict[str, dict] = {}
    for w in windows:
        cls = w.get("class", "")
        title = w.get("title", "")
        matched = any(rule_matches(rule_key, cls, title) for rule_key in existing_rules)
        if not matched and has_equivalent_class_rule(existing_rules, cls):
            matched = True
        if not matched:
            entry = unknown.setdefault(
                cls,
                {
                    "class": cls,
                    "titles": [],
                    "initialClasses": [],
                    "initialTitles": [],
                    "workspaces": [],
                    "pids": [],
                    "xwayland": [],
                    "mapped": [],
                    "addresses": [],
                },
            )
            if title and title not in entry["titles"]:
                entry["titles"].append(title)
            if (
                w.get("initialClass")
                and w["initialClass"] not in entry["initialClasses"]
            ):
                entry["initialClasses"].append(w["initialClass"])
            if (
                w.get("initialTitle")
                and w["initialTitle"] not in entry["initialTitles"]
            ):
                entry["initialTitles"].append(w["initialTitle"])
            if w.get("workspace") and w["workspace"] not in entry["workspaces"]:
                entry["workspaces"].append(w["workspace"])
            if w.get("pid") and w["pid"] not in entry["pids"]:
                entry["pids"].append(w["pid"])
            if w.get("xwayland") and w["xwayland"] not in entry["xwayland"]:
                entry["xwayland"].append(w["xwayland"])
            if w.get("mapped") and w["mapped"] not in entry["mapped"]:
                entry["mapped"].append(w["mapped"])
            if w.get("address") and w["address"] not in entry["addresses"]:
                entry["addresses"].append(w["address"])
    return unknown


def load_icon_catalog(path: Path | None) -> str:
    if not path or not path.exists():
        return ""
    content = path.read_text(encoding="utf-8").strip()
    if not content:
        return ""
    return content


def split_glyph_name(key: str) -> tuple[str, str]:
    if "-" not in key:
        return key, ""
    prefix, short = key.split("-", 1)
    return prefix, short


def fetch_nerdfont_glyphs(url: str) -> dict:
    with urllib.request.urlopen(url, timeout=60) as response:
        return json.load(response)


def build_nerdfont_catalog_text(glyphs: dict, source_url: str) -> str:
    metadata = glyphs.get("METADATA", {}) if isinstance(glyphs, dict) else {}
    version = metadata.get("version", "unknown")
    source_date = metadata.get("date", "unknown")
    generated = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")

    header = [
        "# Nerd Font icon catalog",
        f"# Source: {source_url}",
        f"# Nerd Fonts version: {version}",
        f"# Nerd Fonts source date: {source_date}",
        f"# Generated: {generated}",
        "# Format: <glyph>\t<css_class>\t<short-name>",
        "",
    ]

    rows: list[str] = []
    for key in sorted(glyphs.keys()):
        if key == "METADATA":
            continue
        value = glyphs[key]
        glyph_char = value.get("char", "")
        _, short_name = split_glyph_name(key)
        rows.append(f"{glyph_char}\tnf-{key}\t{short_name}")

    return "\n".join(header + rows) + "\n"


def regenerate_nerdfont_icon_catalog(path: Path) -> None:
    logging.info("Downloading Nerd Font glyph metadata from %s", NERDFONT_GLYPHS_URL)
    glyphs = fetch_nerdfont_glyphs(NERDFONT_GLYPHS_URL)
    content = build_nerdfont_catalog_text(glyphs, NERDFONT_GLYPHS_URL)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")
    logging.info("Wrote Nerd Font icon catalog to %s", path)


def ensure_nerdfont_icon_catalog(path: Path, force_regenerate: bool) -> str:
    if force_regenerate:
        regenerate_nerdfont_icon_catalog(path)

    if not path.exists():
        logging.info("Icon catalog missing, regenerating: %s", path)
        regenerate_nerdfont_icon_catalog(path)
    else:
        with path.open("r", encoding="utf-8") as f:
            line_count = sum(1 for _ in f)
        logging.debug("Icon catalog found: %s (%d total lines)", path, line_count)
        if line_count <= 1:
            logging.info(
                "Icon catalog has %d line(s), regenerating: %s", line_count, path
            )
            regenerate_nerdfont_icon_catalog(path)

    content = load_icon_catalog(path)
    non_empty_lines = (
        len([ln for ln in content.splitlines() if ln.strip()]) if content else 0
    )
    logging.debug(
        "Icon catalog loaded from %s with %d non-empty lines",
        path,
        non_empty_lines,
    )
    return content


def parse_icon_catalog(
    content: str,
) -> tuple[dict[str, str], dict[str, str], dict[str, list[str]], set[str]]:
    by_css: dict[str, str] = {}
    by_short: dict[str, str] = {}
    short_dupes: dict[str, list[str]] = {}
    glyphs: set[str] = set()

    for raw_line in content.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        parts = raw_line.split("\t")
        if len(parts) < 3:
            continue
        glyph, css_name, short_name = parts[0], parts[1], parts[2]
        glyph = glyph.strip()
        css_name = css_name.strip()
        short_name = short_name.strip()
        if not glyph or not css_name or not short_name:
            continue

        by_css[css_name] = glyph
        glyphs.add(glyph)

        if short_name in by_short and by_short[short_name] != glyph:
            short_dupes.setdefault(short_name, [by_short[short_name]]).append(glyph)
        else:
            by_short[short_name] = glyph

    return by_css, by_short, short_dupes, glyphs


def resolve_icon_candidate(
    candidate: str,
    by_css: dict[str, str],
    by_short: dict[str, str],
    short_dupes: dict[str, list[str]],
    glyphs: set[str],
) -> tuple[str | None, str | None]:
    value = candidate.strip()
    if not value:
        return None, "empty value"

    if value in by_css:
        return by_css[value], None

    if value in short_dupes:
        return None, f"ambiguous short-name '{value}'"

    if value in by_short:
        return by_short[value], None

    if value in glyphs:
        return value, None

    return None, f"unknown icon '{value}'"


def extract_json_block(text: str) -> str:
    text = text.strip()
    try:
        json.loads(text)
        return text
    except Exception:
        pass

    fenced = re.search(r"```(?:json)?\s*(\{.*?\})\s*```", text, flags=re.DOTALL)
    if fenced:
        return fenced.group(1)

    braces = re.search(r"(\{.*\})", text, flags=re.DOTALL)
    if braces:
        return braces.group(1)

    raise ValueError("AI output did not contain a JSON object")


def summarize_prompt_for_debug(prompt: str) -> str:
    pattern = re.compile(
        r"(Allowed icon catalog \(prefer from this list\)\n)(.*?)(\nExisting rules\n)",
        flags=re.DOTALL,
    )

    def _replace(match: re.Match) -> str:
        catalog_text = match.group(2)
        line_count = len([ln for ln in catalog_text.splitlines() if ln.strip()])
        return (
            match.group(1)
            + f"[omitted in debug: {line_count} non-empty lines]\n"
            + match.group(3)
        )

    return pattern.sub(_replace, prompt)


def run_ai_command(
    ai_cmd: str,
    prompt: str,
    model: str | None = None,
    files: list[Path] | None = None,
) -> subprocess.CompletedProcess:
    base_cmd = shlex.split(ai_cmd)
    has_dir_flag = "--dir" in base_cmd

    if "{prompt}" in ai_cmd:
        cmd = shlex.split(ai_cmd.replace("{prompt}", prompt))
        stdin_data = None
    else:
        cmd = base_cmd + [prompt]
        stdin_data = None

    if model:
        cmd += ["--model", model]

    if files:
        # Avoid OpenCode external_directory permission prompts by setting the
        # run directory to the attached file's directory when caller did not
        # already provide --dir.
        if not has_dir_flag:
            cmd += ["--dir", str(files[0].parent)]
        for f in files:
            cmd += ["--file", str(f)]

    logging.info(
        "Calling AI command: %s (model=%s, files=%d, dir=%s)",
        " ".join(shlex.quote(x) for x in base_cmd),
        model if model else "default",
        len(files) if files else 0,
        str(files[0].parent) if files and not has_dir_flag else "unchanged",
    )
    logging.debug("AI attached files: %s", [str(f) for f in files] if files else [])

    return subprocess.run(
        cmd,
        input=stdin_data,
        capture_output=True,
        text=True,
        timeout=120,
    )


def call_ai(
    ai_cmd: str,
    prompt: str,
    model: str | None = None,
    files: list[Path] | None = None,
) -> dict[str, str]:
    max_attempts = 2
    current_prompt = prompt

    for attempt in range(1, max_attempts + 1):
        logging.debug(
            "AI prompt (attempt %d/%d):\n%s",
            attempt,
            max_attempts,
            summarize_prompt_for_debug(current_prompt),
        )

        try:
            proc = run_ai_command(ai_cmd, current_prompt, model=model, files=files)
        except subprocess.TimeoutExpired as e:
            raise RuntimeError(f"AI command timed out after 120s: {e}")

        if proc.returncode != 0:
            raise RuntimeError(
                f"AI command failed ({proc.returncode}): {proc.stderr.strip()}"
            )

        logging.debug(
            "AI raw stdout (attempt %d/%d):\n%s", attempt, max_attempts, proc.stdout
        )
        if proc.stderr.strip():
            logging.debug(
                "AI stderr (attempt %d/%d): %s",
                attempt,
                max_attempts,
                proc.stderr.strip(),
            )

        try:
            parsed = json.loads(extract_json_block(proc.stdout))
            if not isinstance(parsed, dict):
                raise ValueError("AI output JSON must be an object")
            return {str(k): str(v) for k, v in parsed.items()}
        except Exception as e:
            if attempt >= max_attempts:
                raise ValueError(
                    f"AI output is not valid JSON after {max_attempts} attempts: {e}"
                )

            logging.warning(
                "AI output rejected on attempt %d/%d: %s", attempt, max_attempts, e
            )
            current_prompt = (
                prompt
                + "\n\n"
                + "Your previous output (verbatim below) had errors and was not accepted:\n"
                + proc.stdout
                + "\nError:\n"
                + str(e)
                + "\n\nPlease return ONLY a valid JSON object following the required schema."
            )

    raise RuntimeError("Unreachable")


def build_prompt(
    existing_rules: dict[str, str],
    unknown: dict[str, dict],
    icon_catalog_line_count: int,
    icon_catalog_attached: bool,
) -> str:
    existing = json.dumps(existing_rules, ensure_ascii=False, indent=2)
    unknown_payload = []
    for cls in sorted(unknown.keys()):
        item = unknown[cls]
        unknown_payload.append(
            {
                "class": item["class"],
                "titles": item["titles"][:6],
                "initialClasses": item["initialClasses"][:4],
                "initialTitles": item["initialTitles"][:6],
                "workspaces": item["workspaces"][:4],
                "xwayland": item["xwayland"][:2],
                "mapped": item["mapped"][:2],
                "sampleAddresses": item["addresses"][:3],
            }
        )
    unknown_json = json.dumps(unknown_payload, ensure_ascii=False, indent=2)

    catalog_header = (
        f"Attached Nerd Font icon catalog has {icon_catalog_line_count} non-empty lines. Prefer icons from the attached file."
        if icon_catalog_attached
        else "No icon catalog file attached. Use common Nerd Font glyphs."
    )

    parts = [
        "Task",
        "Choose icon glyphs for Hyprland Waybar `window-rewrite` rules.",
        "",
        "Output format (strict)",
        "- Return only a JSON object, no markdown, no prose.",
        "- Key format: `class<APP_CLASS>`",
        "- Value format: icon name from attached catalog (prefer `nf-...` css class, e.g. `nf-md-phone_sync`).",
        "",
        "Constraints",
        '- Add entries only for classes listed in "Unknown classes".',
        "- Do not modify, rename, or remove existing rules.",
        "- Keep style consistent with existing mappings (Nerd Font style).",
        "- Prefer app-specific icons over generic placeholders.",
        "- If uncertain, use a clear category icon (chat, browser, terminal, files, media, code, game, etc).",
        "- Avoid duplicate semantic picks when a better specific icon exists.",
        "- Do not return glyph characters unless absolutely necessary.",
        "",
        catalog_header,
    ]

    parts.append("")

    parts.extend(
        [
            "Existing rules",
            existing,
            "",
            "New, unknown window(s)",
            unknown_json,
            "",
        ]
    )

    return "\n".join(parts)


def send_notification(
    summary: str,
    body: str,
    urgency: str = "normal",
    icon: str = "preferences-desktop-icons",
) -> None:
    cmd = [
        "notify-send",
        "-a",
        "waybar-autogen",
        "-i",
        icon,
        "-u",
        urgency,
        summary,
        body,
    ]
    try:
        subprocess.run(cmd, check=False, capture_output=True, text=True)
        logging.info("Sent desktop notification: %s", summary)
    except Exception as e:
        logging.warning("Failed to send desktop notification: %s", e)


def send_success_notification(added_mappings: list[tuple[str, str, str]]) -> None:
    if not added_mappings:
        return

    summary = f"Waybar icon rules updated ({len(added_mappings)})"
    lines = [f"{icon}   ({css_name}) {cls}" for cls, icon, css_name in added_mappings]
    body = "\n".join(lines[:8])
    if len(lines) > 8:
        body += f"\n+{len(lines) - 8} more"
    send_notification(
        summary,
        body,
        urgency="normal",
        icon="preferences-desktop-icons",
    )


class MaxLevelFilter(logging.Filter):
    def __init__(self, max_level: int):
        super().__init__()
        self.max_level = max_level

    def filter(self, record: logging.LogRecord) -> bool:
        return record.levelno <= self.max_level


def configure_logging(level_name: str) -> None:
    level = getattr(logging, level_name.upper(), logging.INFO)
    root = logging.getLogger()
    root.setLevel(level)
    root.handlers.clear()

    if JournalHandler is not None:
        # Native journald logging with proper PRIORITY mapping.
        handler = JournalHandler(SYSLOG_IDENTIFIER="waybar-window-rewrite-autogen")
        handler.setLevel(logging.DEBUG)
        handler.setFormatter(logging.Formatter("%(message)s"))
        root.addHandler(handler)
    else:
        formatter = logging.Formatter("%(levelname)s %(message)s")

        stdout_handler = logging.StreamHandler(sys.stdout)
        stdout_handler.setLevel(logging.DEBUG)
        stdout_handler.addFilter(MaxLevelFilter(logging.INFO))
        stdout_handler.setFormatter(formatter)

        stderr_handler = logging.StreamHandler(sys.stderr)
        stderr_handler.setLevel(logging.WARNING)
        stderr_handler.setFormatter(formatter)

        root.addHandler(stdout_handler)
        root.addHandler(stderr_handler)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Auto-generate waybar window-rewrite icons"
    )
    parser.add_argument(
        "--config",
        default=str(Path.home() / ".config/waybar/hyprland-workspaces.jsonc"),
        help="Path to hyprland-workspaces.jsonc",
    )
    parser.add_argument(
        "--regenerate",
        action="store_true",
        help="Regenerate ~/.config/waybar/nerdfont-icons.txt before running",
    )
    parser.add_argument(
        "--ai-cmd",
        default=os.environ.get("OPENCODE_AI_CMD", "opencode run"),
        help="AI command to run. Prompt is appended as last arg unless {prompt} is used.",
    )
    parser.add_argument(
        "--model",
        default=os.environ.get("OPENCODE_MODEL", ""),
        help="Model in provider/model format (or set OPENCODE_MODEL)",
    )
    parser.add_argument(
        "--dry-run", action="store_true", help="Print changes without writing"
    )
    parser.add_argument(
        "--notify",
        action="store_true",
        default=True,
        help="Send desktop notification on successful updates (default: true)",
    )
    parser.add_argument(
        "--no-notify",
        action="store_false",
        dest="notify",
        help="Disable desktop notifications",
    )
    parser.add_argument(
        "--log-level",
        default=os.environ.get("WAYBAR_REWRITE_AUTOGEN_LOG_LEVEL", "INFO"),
        help="Log level (DEBUG, INFO, WARNING, ERROR)",
    )
    args = parser.parse_args()

    configure_logging(args.log_level)

    config_target_path = Path(args.config).expanduser()
    config_path, chezmoi_apply_path = resolve_config_path_for_chezmoi(
        config_target_path
    )
    logging.info("Loading config: %s", config_path)
    doc = load_jsonc(config_path)

    ws = doc.get("hyprland/workspaces", {})
    rewrite = ws.get("window-rewrite", {})
    if not isinstance(rewrite, dict):
        print("window-rewrite is not an object", file=sys.stderr)
        return 1

    windows = get_open_windows()
    logging.info("Detected %d open windows", len(windows))
    unknown = extract_unknown_classes(rewrite, windows)
    if not unknown:
        logging.info("No unknown windows found")
        return 0

    logging.info("Found %d unknown classes", len(unknown))
    for cls in sorted(unknown.keys()):
        item = unknown[cls]
        logging.info(
            "Unknown class=%s titles=%s initialClasses=%s initialTitles=%s workspaces=%s xwayland=%s mapped=%s addresses=%s",
            item["class"],
            item["titles"],
            item["initialClasses"],
            item["initialTitles"],
            item["workspaces"],
            item["xwayland"],
            item["mapped"],
            item["addresses"],
        )

    icon_catalog_path = NERDFONT_ICON_CATALOG_PATH
    icon_catalog = ensure_nerdfont_icon_catalog(icon_catalog_path, args.regenerate)
    icon_catalog_line_count = (
        len([ln for ln in icon_catalog.splitlines() if ln.strip()])
        if icon_catalog
        else 0
    )
    icon_catalog_attached = icon_catalog_line_count > 0

    if icon_catalog_attached:
        logging.info("Loaded icon catalog: %s", icon_catalog_path)
    else:
        logging.info("No icon catalog found or empty: %s", icon_catalog_path)

    icon_by_css, icon_by_short, short_name_dupes, icon_glyphs = parse_icon_catalog(
        icon_catalog
    )
    logging.debug(
        "Parsed icon catalog: css=%d short=%d dup-short=%d glyphs=%d",
        len(icon_by_css),
        len(icon_by_short),
        len(short_name_dupes),
        len(icon_glyphs),
    )

    prompt = build_prompt(
        rewrite,
        unknown,
        icon_catalog_line_count=icon_catalog_line_count,
        icon_catalog_attached=icon_catalog_attached,
    )
    model = args.model.strip() if args.model else None
    if model:
        logging.info("Using model: %s", model)
    else:
        logging.info("Using default model from opencode config")

    try:
        ai_map = call_ai(
            args.ai_cmd,
            prompt,
            model=model,
            files=[icon_catalog_path] if icon_catalog_attached else None,
        )
    except Exception as e:
        logging.error("AI mapping generation failed: %s", e)
        if args.notify:
            send_notification(
                "Waybar icon autogen failed",
                f"AI output failed twice and was rejected.\nError: {e}",
                urgency="critical",
                icon="dialog-error",
            )
        return 1

    logging.info("AI returned %d candidate mappings", len(ai_map))

    added = 0
    added_mappings: list[tuple[str, str, str]] = []
    css_by_glyph: dict[str, str] = {}
    for css_name, glyph in icon_by_css.items():
        if glyph not in css_by_glyph:
            css_by_glyph[glyph] = css_name
    for cls in sorted(unknown.keys()):
        key = f"class<{cls}>"
        icon_candidate = ai_map.get(key, "").strip()
        if not icon_candidate:
            continue
        icon, icon_err = resolve_icon_candidate(
            icon_candidate,
            icon_by_css,
            icon_by_short,
            short_name_dupes,
            icon_glyphs,
        )
        if icon is None:
            logging.warning("Skipping mapping %s: %s", key, icon_err)
            continue
        if has_equivalent_class_rule(rewrite, cls):
            logging.info("Skipping mapping for class-equivalent existing rule: %s", key)
            continue
        if key not in rewrite:
            rewrite[key] = icon
            added += 1
            resolved_css_name = (
                icon_candidate
                if icon_candidate.startswith("nf-")
                else css_by_glyph.get(icon, "?")
            )
            added_mappings.append((cls, icon, resolved_css_name))
            logging.info(
                "Adding mapping: %s -> %s (from '%s')", key, icon, icon_candidate
            )

    if added == 0:
        logging.warning("AI returned no valid new mappings")
        return 0

    ws["window-rewrite"] = rewrite
    doc["hyprland/workspaces"] = ws

    output = json.dumps(doc, ensure_ascii=False, indent=2) + "\n"
    if args.dry_run:
        logging.info("Dry-run mode: printing updated config")
        print(output)
        if args.notify:
            send_success_notification(added_mappings)
    else:
        config_path.write_text(output, encoding="utf-8")
        logging.info("Added %d new window-rewrite rule(s) to %s", added, config_path)
        if chezmoi_apply_path is not None:
            try:
                chezmoi_apply_target(chezmoi_apply_path)
            except Exception as e:
                logging.error("Failed to apply chezmoi target: %s", e)
                if args.notify:
                    send_notification(
                        "Waybar icon apply failed",
                        f"Updated chezmoi source but apply failed.\nError: {e}",
                        urgency="critical",
                        icon="dialog-error",
                    )
                return 1

        try:
            reload_waybar()
        except Exception as e:
            logging.error("Failed to reload waybar: %s", e)
            if args.notify:
                send_notification(
                    "Waybar reload failed",
                    f"Rules were updated, but waybar reload failed.\nError: {e}",
                    urgency="critical",
                    icon="dialog-error",
                )
            return 1

        if args.notify:
            send_success_notification(added_mappings)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
