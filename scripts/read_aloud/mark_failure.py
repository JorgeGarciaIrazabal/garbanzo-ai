"""Record an abnormal worker process exit when Python cannot run cleanup."""

import json
import sys
from pathlib import Path


def main():
    if len(sys.argv) != 3:
        raise SystemExit("Usage: mark_failure.py REPORT EXIT_CODE")
    report = Path(sys.argv[1])
    exit_code = int(sys.argv[2])
    data = json.loads(report.read_text()) if report.is_file() else {}
    if data.get("status") in {"completed", "failed", "interrupted", "worker_crashed"}:
        return
    data.update(
        status="worker_crashed",
        process_exit_code=exit_code,
        error=f"Synthesis worker exited with code {exit_code}",
    )
    temporary = report.with_suffix(".tmp")
    temporary.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
    temporary.replace(report)


if __name__ == "__main__":
    main()
