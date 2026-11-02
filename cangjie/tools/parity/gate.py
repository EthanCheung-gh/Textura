#!/usr/bin/env python3
"""Three-tier parity acceptance gate (docs/PARITY.md §2.1).

Tiers, all hard:

  structure  long 1px-rule registration error <= 1.5px
             global best exact shift == (0, 0)
             edge coverage (both directions) >= 90%
  visual     1px-Gaussian-blurred SSIM >= 0.95
  raw        pixels with ΔRGB <= 32 >= 95%

All metrics come from `metrics.py` (same directory); this script only applies the
protocol thresholds, prints a human-readable table and writes a JSON report.
`diff.py` remains the localisation tool (side-by-side + heatmap) and is not used
for the verdict.

Exit status:
  0  every selected pair passes all three tiers
  1  at least one pair violates a tier
  2  usage error, missing directory, unknown route, or size mismatch

Usage:
  python3 tools/parity/gate.py [REF] [OUT] [--theme light|dark|both]
                              [--route NAME ...] [--json PATH]
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

# Importing metrics must not leave __pycache__ inside the repository.
sys.dont_write_bytecode = True

import metrics  # noqa: E402  (must follow sys.dont_write_bytecode)

ROUTES = ("dashboard", "calendar", "okr", "gtd", "gantt", "sop", "settings")
THEMES = ("light", "dark")

MAX_RULE_DELTA_PX = 1.5
MIN_EDGE_COVERAGE = 0.90
MIN_BLUR_SSIM = metrics.BLUR_MIN_SSIM  # 0.95
MAX_DELTA_RGB = 32
MIN_RAW_WITHIN = metrics.RAW_MIN_WITHIN  # 0.95

EXIT_PASS = 0
EXIT_FAIL = 1
EXIT_USAGE = 2


def parse_routes(values: list[str] | None) -> list[str]:
    """`--route a --route b` and `--route a,b` are both accepted."""
    if not values:
        return []
    routes: list[str] = []
    for value in values:
        for part in value.split(","):
            part = part.strip()
            if part and part not in routes:
                routes.append(part)
    return routes


def split_name(name: str) -> tuple[str, str]:
    """`dashboard-light` -> ("dashboard", "light"); unknown suffix -> ("...", "")."""
    stem = Path(name).stem
    for theme in THEMES:
        suffix = f"-{theme}"
        if stem.endswith(suffix):
            return stem[: -len(suffix)], theme
    return stem, ""


def resolve_pairs(
    reference: Path, candidate: Path, themes: list[str], routes: list[str]
) -> list[tuple[Path, Path]]:
    if reference.is_file() and candidate.is_file():
        if routes or themes:
            route, theme = split_name(reference.name)
            if routes and route not in routes:
                return []
            if themes and theme not in themes:
                return []
        return [(reference, candidate)]
    if not reference.is_dir() or not candidate.is_dir():
        raise SystemExit(f"REF and OUT must both be files or both be directories: {reference} / {candidate}")

    available: dict[str, list[str]] = {}
    for path in sorted(candidate.glob("*.png")):
        route, theme = split_name(path.name)
        available.setdefault(route, []).append(theme)

    if routes:
        unknown = [route for route in routes if route not in available]
        if unknown:
            known = ", ".join(sorted(available)) or "(none)"
            raise SystemExit(f"unknown route(s) {unknown}; available: {known}")

    selected: list[tuple[Path, Path]] = []
    for path in sorted(reference.glob("*.png")):
        route, theme = split_name(path.name)
        if routes and route not in routes:
            continue
        if themes and theme not in themes:
            continue
        partner = candidate / path.name
        if partner.exists():
            selected.append((path, partner))
    return selected


def evaluate(result: dict) -> dict:
    """Apply the three tiers to a `metrics.measure` result."""
    raw = result["raw"]
    blurred = result["blurred"]
    structure = result["structure"]

    ref_cover = structure.get("ref_covered_within_1px")
    out_cover = structure.get("out_covered_within_1px")
    coverages = [value for value in (ref_cover, out_cover) if value is not None]
    edge_coverage = min(coverages) if coverages else 0.0
    best_shift = structure.get("best_exact_shift") or {}
    rule_delta = float((structure.get("rules") or {}).get("max_matched_delta_px", float("inf")))

    structure_reasons: list[str] = []
    if rule_delta > MAX_RULE_DELTA_PX:
        structure_reasons.append(f"rule delta {rule_delta:.1f}px > {MAX_RULE_DELTA_PX:g}px")
    if best_shift.get("dx") != 0 or best_shift.get("dy") != 0:
        structure_reasons.append(f"best shift ({best_shift.get('dx')},{best_shift.get('dy')}) != (0,0)")
    if edge_coverage < MIN_EDGE_COVERAGE:
        structure_reasons.append(f"edge coverage {100 * edge_coverage:.2f}% < {100 * MIN_EDGE_COVERAGE:.0f}%")
    structure_passed = not structure_reasons

    visual_passed = blurred["ssim"] >= MIN_BLUR_SSIM
    visual_reasons = [] if visual_passed else [f"blur SSIM {blurred['ssim']:.4f} < {MIN_BLUR_SSIM:.2f}"]

    raw_passed = raw["within_tolerance_ratio"] >= MIN_RAW_WITHIN
    raw_reasons = (
        []
        if raw_passed
        else [
            f"ΔRGB<={MAX_DELTA_RGB} coverage {100 * raw['within_tolerance_ratio']:.2f}% < {100 * MIN_RAW_WITHIN:.0f}%"
        ]
    )

    tiers = {
        "structure": {
            "passed": structure_passed,
            "max_rule_delta_px": rule_delta,
            "best_exact_shift": best_shift,
            "edge_coverage_min": edge_coverage,
            "reasons": structure_reasons,
        },
        "visual": {"passed": visual_passed, "blur_ssim": blurred["ssim"], "reasons": visual_reasons},
        "raw": {
            "passed": raw_passed,
            "within_tolerance_ratio": raw["within_tolerance_ratio"],
            "reasons": raw_reasons,
        },
    }
    failed_tiers = [name for name, tier in tiers.items() if not tier["passed"]]
    return {
        "name": result["name"],
        "reference": result["reference"],
        "candidate": result["candidate"],
        "raw": raw,
        "blurred": blurred,
        "structure": structure,
        "worst_blocks": result["worst_blocks"],
        "gate": {
            "tiers": tiers,
            "passed": not failed_tiers,
            "failed_tiers": failed_tiers,
            "reasons": [reason for tier in tiers.values() for reason in tier["reasons"]],
        },
        "passed": not failed_tiers,
    }


def format_table(rows: list[dict]) -> str:
    header = (
        f"{'pair':<17}{'diff%':>8}{'meanΔ':>7}{'raw≤32%':>9}{'blurSSIM':>10}"
        f"{'edge ref%':>11}{'edge out%':>11}{'ruleΔpx':>9}{'shift':>8}  verdict"
    )
    lines = [header, "-" * len(header)]
    for row in rows:
        raw = row["raw"]
        blurred = row["blurred"]
        structure = row["structure"]
        shift = structure.get("best_exact_shift") or {}
        edge = row["gate"]["tiers"]["structure"]
        lines.append(
            f"{row['name']:<17}"
            f"{100 * raw['different_ratio']:8.2f}"
            f"{raw['mean_delta_rgb']:7.2f}"
            f"{100 * raw['within_tolerance_ratio']:9.2f}"
            f"{blurred['ssim']:10.4f}"
            f"{100 * structure.get('ref_covered_within_1px', 0.0):11.2f}"
            f"{100 * structure.get('out_covered_within_1px', 0.0):11.2f}"
            f"{edge['max_rule_delta_px']:9.1f}"
            f"{'(' + str(shift.get('dx')) + ',' + str(shift.get('dy')) + ')':>8}"
            f"  {'PASS' if row['passed'] else 'FAIL'}"
        )
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Three-tier Cangjie parity gate (structure + blurred SSIM + raw ΔRGB)",
        epilog="Exit: 0 = all selected pairs pass, 1 = tier violation, 2 = usage/input error.",
    )
    parser.add_argument(
        "reference_pos", nargs="?", type=Path, default=None, help="reference PNG or directory (default: ref/)"
    )
    parser.add_argument(
        "candidate_pos", nargs="?", type=Path, default=None, help="candidate PNG or directory (default: out/)"
    )
    parser.add_argument("--ref", type=Path, default=None, help="reference PNG or directory")
    parser.add_argument("--out", type=Path, default=None, help="candidate PNG or directory")
    parser.add_argument("--theme", choices=("light", "dark", "both"), default="both", help="theme filter")
    parser.add_argument(
        "--route",
        action="append",
        metavar="NAME",
        help=f"route filter, repeatable or comma-separated ({'|'.join(ROUTES)})",
    )
    parser.add_argument("--max-delta", type=int, default=MAX_DELTA_RGB, help="raw per-pixel ΔRGB tolerance")
    parser.add_argument("--json", type=Path, default=None, help="write the full report as JSON")
    args = parser.parse_args()

    here = Path(__file__).resolve().parent
    reference = args.ref or args.reference_pos or (here / "ref")
    candidate = args.out or args.candidate_pos or (here / "out")
    if not reference.exists():
        print(f"gate: missing reference {reference}", file=sys.stderr)
        return EXIT_USAGE
    if not candidate.exists():
        print(f"gate: missing candidate {candidate} (run scripts/parity.sh first)", file=sys.stderr)
        return EXIT_USAGE

    routes = parse_routes(args.route)
    themes = [] if args.theme == "both" else [args.theme]
    try:
        pairs = resolve_pairs(reference, candidate, themes, routes)
    except SystemExit as exc:
        print(f"gate: {exc}", file=sys.stderr)
        return EXIT_USAGE
    if not pairs:
        print(
            f"gate: no PNG pairs selected (ref={reference}, out={candidate}, "
            f"theme={args.theme}, routes={routes or 'all'})",
            file=sys.stderr,
        )
        return EXIT_USAGE

    rows = []
    for ref_path, out_path in pairs:
        try:
            measured = metrics.measure(ref_path, out_path, args.max_delta)
        except SystemExit as exc:
            print(f"gate: {exc}", file=sys.stderr)
            return EXIT_USAGE
        row = evaluate(measured)
        row["route"], row["theme"] = split_name(ref_path.name)
        rows.append(row)

    print(format_table(rows))
    failed = [row for row in rows if not row["passed"]]
    for row in failed:
        print(f"FAIL {row['name']}: {'; '.join(row['gate']['reasons'])}")
    scope = f"theme={args.theme}, routes={','.join(routes) if routes else 'all'}"
    print(
        f"\ngate: {len(rows) - len(failed)}/{len(rows)} PASS ({scope}) "
        f"[structure: ruleΔ≤{MAX_RULE_DELTA_PX:g}px, shift=(0,0), edge≥{100 * MIN_EDGE_COVERAGE:.0f}%"
        f" | visual: blur SSIM≥{MIN_BLUR_SSIM:.2f}"
        f" | raw: ΔRGB≤{args.max_delta} ≥{100 * MIN_RAW_WITHIN:.0f}%]"
    )
    print(f"gate: verdict {'PASS' if not failed else 'FAIL'} (exit {EXIT_PASS if not failed else EXIT_FAIL})")

    if args.json:
        report = {
            "tool": "cangjie/tools/parity/gate.py",
            "protocol": "cangjie/docs/PARITY.md §2.1",
            "reference": str(reference),
            "candidate": str(candidate),
            "selectors": {"theme": args.theme, "routes": routes},
            "thresholds": {
                "structure": {
                    "max_rule_delta_px": MAX_RULE_DELTA_PX,
                    "required_best_shift": [0, 0],
                    "min_edge_coverage": MIN_EDGE_COVERAGE,
                },
                "visual": {"min_blur_ssim": MIN_BLUR_SSIM, "blur_sigma": 1.0},
                "raw": {"max_delta_rgb": args.max_delta, "min_within_tolerance_ratio": MIN_RAW_WITHIN},
            },
            "results": rows,
            "summary": {
                "total": len(rows),
                "passed": len(rows) - len(failed),
                "failed": [row["name"] for row in failed],
                "verdict": "PASS" if not failed else "FAIL",
            },
        }
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
        print(f"gate: json report -> {args.json}")

    return EXIT_PASS if not failed else EXIT_FAIL


if __name__ == "__main__":
    sys.exit(main())
