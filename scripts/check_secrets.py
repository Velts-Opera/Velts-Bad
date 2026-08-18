from __future__ import annotations

import re
import subprocess
from pathlib import Path

SECRET_ASSIGNMENT = re.compile(
    r"^[ \t]*[+-]?[ \t]*([A-Z0-9_]*(?:SECRET|TOKEN|API_KEY))[ \t]*=[ \t]*([^#\r\n]+?)[ \t]*$",
    re.MULTILINE,
)
DIRECT_PATTERNS = (
    re.compile(r"gsk_[A-Za-z0-9_-]{20,}"),
    re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
)
SAFE_MARKERS = (
    "replace",
    "example",
    "placeholder",
    "changeme",
    "your_",
    "your-",
    "sua_",
    "sua-",
    "<",
    "${",
    "$env:",
    "$($",
)


def tracked_files() -> list[Path]:
    output = subprocess.check_output(["git", "ls-files", "-z"], text=False)
    return [Path(item.decode("utf-8")) for item in output.split(b"\0") if item]


def looks_like_real_secret(value: str) -> bool:
    cleaned = value.strip().strip("\"'")
    if not cleaned:
        return False
    lowered = cleaned.casefold()
    return not any(marker in lowered for marker in SAFE_MARKERS)


def scan_text(text: str, *, location: str) -> list[str]:
    findings: list[str] = []

    for pattern in DIRECT_PATTERNS:
        if pattern.search(text):
            findings.append(f"{location}: credential-shaped material detected")

    for match in SECRET_ASSIGNMENT.finditer(text):
        if looks_like_real_secret(match.group(2)):
            findings.append(
                f"{location}: non-placeholder value assigned to {match.group(1)}"
            )

    return findings


def scan_worktree() -> list[str]:
    findings: list[str] = []
    for path in tracked_files():
        if not path.is_file() or path.stat().st_size > 2_000_000:
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        findings.extend(scan_text(text, location=str(path)))
    return findings


def scan_history() -> list[str]:
    """Scan textual git diffs without echoing any matched secret material."""
    history = subprocess.check_output(
        [
            "git",
            "log",
            "--all",
            "--no-ext-diff",
            "--no-textconv",
            "--format=commit:%H",
            "-p",
            "--",
        ],
        text=False,
    ).decode("utf-8", errors="replace")

    findings: list[str] = []
    current_commit = "unknown"
    current_file = "unknown"
    chunk: list[str] = []

    def flush() -> None:
        if not chunk:
            return
        location = f"history {current_commit[:12]}:{current_file}"
        findings.extend(scan_text("\n".join(chunk), location=location))
        chunk.clear()

    for line in history.splitlines():
        if line.startswith("commit:"):
            flush()
            current_commit = line.removeprefix("commit:").strip()
            current_file = "unknown"
            continue
        if line.startswith("diff --git a/"):
            flush()
            parts = line.split(" b/", 1)
            current_file = parts[1] if len(parts) == 2 else "unknown"
            continue
        if line.startswith("+++") or line.startswith("---") or line.startswith("@@"):
            continue
        if line.startswith("+") or line.startswith("-"):
            chunk.append(line)

    flush()
    return findings


def main() -> int:
    findings = [*scan_worktree(), *scan_history()]

    if findings:
        print("Secret scan failed. Values are intentionally suppressed:")
        for finding in sorted(set(findings)):
            print(f"- {finding}")
        return 1

    print("Worktree + git history secret scan: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
