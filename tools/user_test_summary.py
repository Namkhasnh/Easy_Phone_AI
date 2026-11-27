"""Summary of the small usability test (docs/USER_TEST_KIT.md) for the thesis.

Reads docs/user_test/tasks.csv and docs/user_test/sus.csv (or the paths given) and prints Markdown tables:
per task, per age group, overall, SUS. Standard library only:  python3 tools/user_test_summary.py [tasks.csv sus.csv]
"""

import csv
import statistics
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TASKS = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "docs/user_test/tasks.csv"
SUS = Path(sys.argv[2]) if len(sys.argv) > 2 else ROOT / "docs/user_test/sus.csv"
GROUPS = ["young", "middle", "older"]


def read(path: Path) -> list[dict]:
    if not path.exists():
        return []
    with path.open(encoding="utf-8") as f:
        return [r for r in csv.DictReader(f) if r.get("participant", "").strip()]


def stats(rows: list[dict]) -> tuple[str, str, str, str, str]:
    if not rows:
        return ("–",) * 5
    success = [float(r["success"]) for r in rows]
    seconds = [float(r["seconds"]) for r in rows if float(r["success"]) > 0]
    edits = [float(r.get("edits") or 0) for r in rows]
    helped = [float(r.get("help") or 0) for r in rows]
    done = sum(1 for s in success if s > 0) / len(success)
    return (f"{len(rows)}", f"{done:.0%}", f"{statistics.median(seconds):.0f} s" if seconds else "–",
            f"{statistics.mean(edits):.2f}", f"{statistics.mean(helped):.0%}")


def sus_score(r: dict) -> float:
    q = [int(r[f"q{i}"]) for i in range(1, 11)]
    return sum((q[i] - 1) if i % 2 == 0 else (5 - q[i]) for i in range(10)) * 2.5


def main() -> None:
    rows = read(TASKS)
    people = {r["participant"]: r["age_group"] for r in rows}
    print(f"# User test summary — {len(people)} participants, {len(rows)} task runs\n")
    head = "| {} | Runs | Success | Median time (done) | Edits / task | Asked for help |\n|---|---|---|---|---|---|"
    print(head.format("Task"))
    by_task = defaultdict(list)
    for r in rows:
        by_task[r["task"]].append(r)
    for task in sorted(by_task):
        print("| {} | {} | {} | {} | {} | {} |".format(task, *stats(by_task[task])))
    print("| **All** | {} | {} | {} | {} | {} |\n".format(*stats(rows)))
    print(head.format("Age group"))
    for g in GROUPS:
        print("| {} | {} | {} | {} | {} | {} |".format(g, *stats([r for r in rows if r["age_group"] == g])))
    voice = [r for r in rows if r.get("input") == "voice"]
    text = [r for r in rows if r.get("input") == "text"]
    print(f"\nInput: voice {len(voice)} runs ({stats(voice)[1]} success), text {len(text)} runs ({stats(text)[1]} success)\n")

    sus = read(SUS)
    if sus:
        scores = {r["participant"]: sus_score(r) for r in sus}
        print("| SUS | n | Mean | Min | Max |\n|---|---|---|---|---|")
        groups = [("All", list(scores.values()))] + [
            (g, [s for p, s in scores.items() if people.get(p) == g]) for g in GROUPS]
        for name, vals in groups:
            if vals:
                print(f"| {name} | {len(vals)} | {statistics.mean(vals):.1f} | {min(vals):.1f} | {max(vals):.1f} |")
        print("\nSUS reading: 68 = average, ≥ 80 = good, < 50 = poor.")


if __name__ == "__main__":
    main()
