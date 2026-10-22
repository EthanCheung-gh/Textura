#!/usr/bin/env python3
"""Pixel/structure diff for the Cangjie parity pipeline.

Accepts two PNGs or two directories of PNGs (paired by filename). For every pair
it prints:

  * different-pixel ratio (any channel changed)
  * mean / max ΔRGB (ΔRGB = max channel absolute difference)
  * block SSIM on grayscale (8x8 windows, no scikit-image dependency)
  * pass/fail against the frozen tolerance

and writes `<name>-side.png` (reference | CUI) plus `<name>-diff.png`
(dimmed reference with amplified red differences).

Tolerance (override with flags):
  ΔRGB <= 32 for at least 98% of pixels  AND  SSIM >= 0.95

Exit status: 0 only when every pair passes. Requires Pillow + numpy.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

C1 = (0.01 * 255) ** 2
C2 = (0.03 * 255) ** 2


def load_rgb(path: Path) -> np.ndarray:
    with Image.open(path) as image:
        return np.asarray(image.convert("RGB"), dtype=np.uint8)


def block_ssim(reference: np.ndarray, candidate: np.ndarray, block: int = 8) -> float:
    """Mean 8x8 block SSIM (global statistics per block, grayscale)."""
    ref = reference.astype(np.float64).mean(axis=2)
    out = candidate.astype(np.float64).mean(axis=2)
    height, width = ref.shape
    h = (height // block) * block
    w = (width // block) * block
    if h == 0 or w == 0:
        return 0.0
    ref = ref[:h, :w].reshape(h // block, block, w // block, block)
    out = out[:h, :w].reshape(h // block, block, w // block, block)
    ref_mean = ref.mean(axis=(1, 3))
    out_mean = out.mean(axis=(1, 3))
    ref_var = ref.var(axis=(1, 3))
    out_var = out.var(axis=(1, 3))
    covariance = ((ref - ref_mean[:, None, :, None]) * (out - out_mean[:, None, :, None])).mean(axis=(1, 3))
    numerator = (2 * ref_mean * out_mean + C1) * (2 * covariance + C2)
    denominator = (ref_mean**2 + out_mean**2 + C1) * (ref_var + out_var + C2)
    return float((numerator / denominator).mean())


def diff_pair(reference_path: Path, candidate_path: Path, report_dir: Path, args: argparse.Namespace) -> dict:
    reference = load_rgb(reference_path)
    candidate = load_rgb(candidate_path)
    if reference.shape != candidate.shape:
        raise SystemExit(
            f"size mismatch for {reference_path.name}: {reference.shape[1]}x{reference.shape[0]} "
            f"vs {candidate.shape[1]}x{candidate.shape[0]}"
        )
    delta = np.abs(reference.astype(np.int16) - candidate.astype(np.int16)).max(axis=2)
    total = delta.size
    different = int(np.count_nonzero(delta > 0))
    within = int(np.count_nonzero(delta <= args.max_delta))
    mean_delta = float(delta.mean())
    max_delta = int(delta.max())
    ssim = block_ssim(reference, candidate)
    pass_ratio = within / total
    passed = pass_ratio >= args.min_pass_ratio and ssim >= args.min_ssim

    report_dir.mkdir(parents=True, exist_ok=True)
    stem = reference_path.stem
    side = Image.new("RGB", (reference.shape[1] * 2, reference.shape[0]))
    side.paste(Image.fromarray(reference), (0, 0))
    side.paste(Image.fromarray(candidate), (reference.shape[1], 0))
    side.save(report_dir / f"{stem}-side.png")
    heat = (reference.astype(np.float64) * 0.25).astype(np.uint8)
    heat[..., 0] = np.clip(heat[..., 0].astype(np.int16) + delta * 3, 0, 255).astype(np.uint8)
    heat[..., 1] = np.clip(heat[..., 1].astype(np.int16), 0, 255).astype(np.uint8)
    heat[..., 2] = np.clip(heat[..., 2].astype(np.int16), 0, 255).astype(np.uint8)
    Image.fromarray(heat).save(report_dir / f"{stem}-diff.png")

    result = {
        "reference": str(reference_path),
        "candidate": str(candidate_path),
        "width": int(reference.shape[1]),
        "height": int(reference.shape[0]),
        "pixels": total,
        "different_pixels": different,
        "different_ratio": different / total,
        "mean_delta_rgb": mean_delta,
        "max_delta_rgb": max_delta,
        "within_tolerance_ratio": pass_ratio,
        "ssim": ssim,
        "passed": passed,
        "side_by_side": str(report_dir / f"{stem}-side.png"),
        "diff_heatmap": str(report_dir / f"{stem}-diff.png"),
    }
    print(
        f"{reference_path.name}: {100 * different / total:6.2f}% pixels differ | "
        f"ΔRGB mean={mean_delta:5.2f} max={max_delta:3d} | "
        f"≤{args.max_delta}: {100 * pass_ratio:6.2f}% | SSIM={ssim:.4f} | "
        f"{'PASS' if passed else 'FAIL'}"
    )
    return result


def resolve_pairs(reference: Path, candidate: Path, theme: str | None = None) -> list[tuple[Path, Path]]:
    if reference.is_dir() and candidate.is_dir():
        names = sorted(
            p.name
            for p in reference.glob("*.png")
            if (candidate / p.name).exists() and (theme is None or p.name.endswith(f"-{theme}.png"))
        )
        if not names:
            raise SystemExit(f"no matching PNG filenames in {reference} and {candidate}")
        return [(reference / name, candidate / name) for name in names]
    if reference.is_file() and candidate.is_file():
        return [(reference, candidate)]
    raise SystemExit("REF and OUT must both be files or both be directories")


def main() -> int:
    parser = argparse.ArgumentParser(description="Cangjie parity pixel/structure diff")
    parser.add_argument("reference", type=Path, help="reference PNG or directory")
    parser.add_argument("candidate", type=Path, help="candidate PNG or directory")
    parser.add_argument("--report-dir", type=Path, default=Path(__file__).resolve().parent / "out" / "diffs")
    parser.add_argument("--max-delta", type=int, default=32, help="per-pixel ΔRGB tolerance (0..255)")
    parser.add_argument("--min-pass-ratio", type=float, default=0.98, help="fraction of pixels within tolerance")
    parser.add_argument("--min-ssim", type=float, default=0.95, help="minimum block SSIM")
    parser.add_argument("--theme", choices=("light", "dark"), default=None, help="only pair *-<theme>.png files")
    parser.add_argument("--json", type=Path, default=None, help="optional JSON report path")
    args = parser.parse_args()

    results = [diff_pair(ref, out, args.report_dir, args) for ref, out in resolve_pairs(args.reference, args.candidate, args.theme)]
    failed = [result for result in results if not result["passed"]]
    print(
        f"summary: {len(results) - len(failed)}/{len(results)} pairs pass "
        f"(ΔRGB≤{args.max_delta} ≥{100 * args.min_pass_ratio:.0f}%, SSIM≥{args.min_ssim})"
    )
    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(json.dumps({"tolerance": {
            "max_delta_rgb": args.max_delta,
            "min_within_tolerance_ratio": args.min_pass_ratio,
            "min_ssim": args.min_ssim,
        }, "pairs": results}, indent=2) + "\n", encoding="utf-8")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
