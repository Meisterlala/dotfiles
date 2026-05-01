#!/usr/bin/env python3
import json
import re
import subprocess
from pathlib import Path
from xml.sax.saxutils import escape as xml_escape


NVIDIA_PACKAGES = (
    "nvidia-utils",
    "nvidia-dkms",
    "nvidia-open-dkms",
    "nvidia",
    "nvidia-open",
    "nvidia-lts",
)

def run(args: list[str], timeout: int = 3) -> tuple[int, str, str]:
    try:
        proc = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
        return proc.returncode, proc.stdout.strip(), proc.stderr.strip()
    except Exception as exc:
        return 1, "", str(exc)


def normalize_version(version: str) -> str:
    version = version.strip()
    if ":" in version:
        version = version.split(":", 1)[1]
    return version.split("-", 1)[0]


def installed_userspace_version() -> str:
    code, out, _ = run(["pacman", "-Q", *NVIDIA_PACKAGES])
    if code != 0 and not out:
        return ""

    fallback = ""
    for line in out.splitlines():
        parts = line.split(maxsplit=1)
        if len(parts) != 2:
            continue
        version = normalize_version(parts[1])
        if parts[0] == "nvidia-utils":
            return version
        if not fallback:
            fallback = version
    return fallback


def kernel_module_version() -> str:
    loaded_version = Path("/sys/module/nvidia/version")
    if loaded_version.exists():
        try:
            return loaded_version.read_text(encoding="utf-8").strip()
        except Exception:
            pass

    code, out, _ = run(["modinfo", "-F", "version", "nvidia"])
    if code == 0 and out:
        return out.splitlines()[0].strip()
    return ""


def nvidia_smi_error() -> str:
    code, out, err = run(["nvidia-smi", "--query-gpu=driver_version", "--format=csv,noheader"], timeout=5)
    if code == 0:
        return ""
    message = f"{out}\n{err}"
    if "Driver/library version mismatch" in message:
        return "driver/library version mismatch"
    if "Failed to initialize NVML" in message:
        return "NVML initialization failed"
    return "failed"


def vulkan_error() -> str:
    code, _, err = run(["vulkaninfo", "--summary"], timeout=3)
    if code == 0:
        return ""
    if "No such file" in err or "not found" in err:
        return ""
    match = re.search(r"ERROR_[A-Z0-9_]+", err)
    if match:
        return f"initialization failed ({match.group(0)})"
    return "initialization failed"


def opengl_error() -> str:
    code, _, err = run(["glxinfo", "-B"], timeout=3)
    if code == 0:
        return ""
    if "No such file" in err or "not found" in err:
        return ""
    if "unable to open display" in err.lower():
        return "cannot open display"
    return "initialization failed"


def egl_error() -> str:
    code, out, err = run(["eglinfo"], timeout=3)
    message = f"{out}\n{err}"
    if code == 0 and "failed" not in message.lower() and "error" not in message.lower():
        return ""
    if "No such file" in message or "not found" in message:
        return ""
    if "failed to create dri2 screen" in message.lower():
        return "failed to create DRI2 screen"
    if "amdgpu_device_initialize failed" in message:
        return "GPU initialization failed"
    return "initialization failed"


def nvidia_device_paths() -> list[str]:
    return sorted(str(path) for path in Path("/dev").glob("nvidia*"))


def nvidia_users() -> list[dict[str, str]]:
    paths = nvidia_device_paths()
    if not paths:
        return []

    code, out, _ = run(["lsof", "-nP", "-w", "-F", "pcu", *paths], timeout=5)
    if code != 0 and not out:
        return []

    users: dict[str, dict[str, str]] = {}
    current_pid = ""
    for line in out.splitlines():
        if not line:
            continue

        field = line[0]
        value = line[1:]

        if field == "p":
            current_pid = value
            users.setdefault(current_pid, {"pid": current_pid, "command": "", "user": ""})
        elif current_pid and field == "c":
            users[current_pid]["command"] = value
        elif current_pid and field == "u":
            users[current_pid]["user"] = value

    return sorted(
        users.values(),
        key=lambda item: (item.get("command", "").lower(), int(item.get("pid", "0") or 0)),
    )


def process_args(pid: str) -> str:
    if not pid:
        return ""

    try:
        raw = Path(f"/proc/{pid}/cmdline").read_bytes()
    except Exception:
        return ""

    return " ".join(part.decode("utf-8", errors="replace") for part in raw.split(b"\0") if part)


def display_command(user: dict[str, str]) -> str:
    command = user.get("command") or "unknown"
    args = process_args(user.get("pid", ""))
    args_lower = args.lower()

    if "mysuperwhisper" in args_lower:
        return "MySuperWhisper"

    return command


def display_users(users: list[dict[str, str]]) -> list[dict[str, object]]:
    display: dict[str, dict[str, object]] = {}
    for user in users:
        command = display_command(user)
        entry = display.setdefault(command, {"command": command, "pids": []})
        pids = entry["pids"]
        if isinstance(pids, list):
            pids.append(user.get("pid", ""))

    return sorted(display.values(), key=lambda item: str(item["command"]).lower())


def format_nvidia_users(users: list[dict[str, str]]) -> list[str]:
    if not users:
        return ["<b>NVIDIA users:</b> none detected"]

    lines = ["<b>NVIDIA users:</b>"]
    for user in display_users(users):
        command = str(user["command"])
        label = f"- {command}"
        lines.append(xml_escape(label))
    return lines


def emit(text: str, tooltip: str, class_name: str) -> None:
    print(json.dumps({"text": text, "tooltip": tooltip, "class": class_name}, ensure_ascii=False))


def main() -> None:
    installed_version = installed_userspace_version()
    if not installed_version:
        emit("", "No NVIDIA packages found", "ok")
        return

    module_version = kernel_module_version()
    users = nvidia_users()

    problems: list[str] = []
    if not module_version:
        problems.append("No NVIDIA module found for the running kernel")
    elif normalize_version(module_version) != normalize_version(installed_version):
        problems.append("NVIDIA userspace and kernel module versions differ")

    if not problems:
        emit("", f"NVIDIA driver OK: {xml_escape(installed_version)}", "ok")
        return

    smi_error = nvidia_smi_error()
    if smi_error:
        problems.append("nvidia-smi cannot talk to the driver")

    vk_error = vulkan_error()
    if vk_error:
        problems.append("Vulkan cannot create an instance")

    gl_error = opengl_error()
    if gl_error:
        problems.append("OpenGL cannot initialize")

    egl_error_message = egl_error()
    if egl_error_message:
        problems.append("EGL cannot initialize")

    lines = [
        "<b>NVIDIA driver problem</b>",
        *[f"<span foreground='#f38ba8'>- {xml_escape(problem)}</span>" for problem in problems],
        "",
        f"<b>Installed userspace:</b> {xml_escape(installed_version)}",
        f"<b>Running kernel module:</b> {xml_escape(module_version or 'missing')}",
    ]

    if smi_error:
        lines.append(f"<b>NVML:</b> {xml_escape(smi_error)}")

    if vk_error:
        lines.append(f"<b>Vulkan:</b> {xml_escape(vk_error)}")

    if gl_error:
        lines.append(f"<b>OpenGL:</b> {xml_escape(gl_error)}")

    if egl_error_message:
        lines.append(f"<b>EGL:</b> {xml_escape(egl_error_message)}")

    lines.extend(["", *format_nvidia_users(users)])

    emit("󰢮", "\r".join(lines), "critical")


if __name__ == "__main__":
    main()
