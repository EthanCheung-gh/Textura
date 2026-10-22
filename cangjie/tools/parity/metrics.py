#!/usr/bin/env python3
"""Two-tier parity metrics: raw pixels + 1px-Gaussian-blurred (visual) metrics.

`diff.py` answers "how far apart are the raw pixels". This script adds the
*visual* tier used by the acceptance protocol in `docs/PARITY.md` §2 and the
worst-residual-block localization used in `docs/PARITY-RESULTS.md`.

For every `<name>.png` pair in REF/OUT it reports:

  raw       different-pixel %, mean/max ΔRGB, ΔRGB<=32 share, block SSIM  (= diff.py)
  blurred   same numbers after a sigma=1.0 (radius 3) Gaussian blur on both
            images. This removes the LCD subpixel-antialiasing colour fringes
            that Chromium emits and FreeType grayscale AA does not.
  blocks    the 3 worst 90x90 tiles by mean ΔRGB, with coordinates and the
            share of pixels in that tile that exceed ΔRGB=32.
  structure whether every luminance edge in one image has a counterpart within
            1px in the other (both directions), plus the best global shift.
            This is the objective form of the protocol's "element boundaries,
            row heights, column widths and 1px rules agree within 1px".

Metrics are computed here rather than imported from `diff.py` so that a change
to the frozen CLI of `diff.py` cannot silently alter the numbers quoted in
`docs/PARITY-RESULTS.md`.

Exit status: 0 when every pair clears the protocol thresholds
(blurred SSIM >= 0.95 and raw ΔRGB<=32 share >= 0.95), else 1.

Requires only Pillow + numpy.
"""
from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image

# SSIM stabilisers for 8-bit dynamic range (C1 = (0.01*L)^2, C2 = (0.03*L)^2).
C1 = (0.01 * 255) ** 2
C2 = (0.03 * 255) ** 2

RAW_MIN_WITHIN = 0.95  # protocol: ΔRGB<=32 for >= 95% of pixels
BLUR_MIN_SSIM = 0.95  # protocol: blurred SSIM >= 0.95
BLOCK = 90  # tile size for worst-region localization


def load_rgb(path: Path) -> np.ndarray:
    with Image.open(path) as image:
        return np.asarray(image.convert("RGB"), dtype=np.uint8)


def gaussian_kernel(sigma: float = 1.0) -> np.ndarray:
    radius = max(1, int(math.ceil(3.0 * sigma)))
    taps = np.arange(-radius, radius + 1, dtype=np.float64)
    kernel = np.exp(-(taps**2) / (2.0 * sigma * sigma))
    return kernel / kernel.sum()


def blur(image: np.ndarray, sigma: float = 1.0) -> np.ndarray:
    """Separable Gaussian blur, edge-replicated, float64 in / uint8 out."""
    kernel = gaussian_kernel(sigma)
    radius = len(kernel) // 2
    work = image.astype(np.float64)
    padded = np.pad(work, ((radius, radius), (0, 0), (0, 0)), mode="edge")
    work = sum(kernel[i] * padded[i : i + work.shape[0], :, :] for i in range(len(kernel)))
    padded = np.pad(work, ((0, 0), (radius, radius), (0, 0)), mode="edge")
    work = sum(kernel[i] * padded[:, i : i + work.shape[1], :] for i in range(len(kernel)))
    return np.clip(np.rint(work), 0, 255).astype(np.uint8)


def block_ssim(reference: np.ndarray, candidate: np.ndarray, size: int = 8) -> float:
    """Mean 8x8 block SSIM over grayscale (identical maths to diff.py)."""
    ref = reference.astype(np.float64).mean(axis=2)
    out = candidate.astype(np.float64).mean(axis=2)
    height, width = ref.shape
    h = (height // size) * size
    w = (width // size) * size
    if h == 0 or w == 0:
        return 0.0
    ref = ref[:h, :w].reshape(h // size, size, w // size, size)
    out = out[:h, :w].reshape(h // size, size, w // size, size)
    ref_mean = ref.mean(axis=(1, 3))
    out_mean = out.mean(axis=(1, 3))
    ref_var = ref.var(axis=(1, 3))
    out_var = out.var(axis=(1, 3))
    covariance = ((ref - ref_mean[:, None, :, None]) * (out - out_mean[:, None, :, None])).mean(axis=(1, 3))
    numerator = (2 * ref_mean * out_mean + C1) * (2 * covariance + C2)
    denominator = (ref_mean**2 + out_mean**2 + C1) * (ref_var + out_var + C2)
    return float((numerator / denominator).mean())


def pixel_stats(reference: np.ndarray, candidate: np.ndarray, max_delta: int) -> dict:
    delta = np.abs(reference.astype(np.int16) - candidate.astype(np.int16)).max(axis=2)
    total = int(delta.size)
    return {
        "different_ratio": int(np.count_nonzero(delta > 0)) / total,
        "mean_delta_rgb": float(delta.mean()),
        "max_delta_rgb": int(delta.max()),
        "within_tolerance_ratio": int(np.count_nonzero(delta <= max_delta)) / total,
        "ssim": block_ssim(reference, candidate),
        "delta": delta,
    }


def worst_blocks(delta: np.ndarray, max_delta: int, count: int = 3) -> list[dict]:
    """Rank --tile-- blocks by mean ΔRGB (not by SSIM) to localise residuals."""
    height, width = delta.shape
    rows = (height + BLOCK - 1) // BLOCK
    cols = (width + BLOCK - 1) // BLOCK
    ranked = []
    for row in range(rows):
        for col in range(cols):
            tile = delta[row * BLOCK : (row + 1) * BLOCK, col * BLOCK : (col + 1) * BLOCK]
            if tile.size == 0:
                continue
            ranked.append(
                {
                    "x": col * BLOCK,
                    "y": row * BLOCK,
                    "w": int(tile.shape[1]),
                    "h": int(tile.shape[0]),
                    "mean_delta_rgb": float(tile.mean()),
                    "over_tolerance_ratio": float(np.count_nonzero(tile > max_delta)) / tile.size,
                }
            )
    ranked.sort(key=lambda entry: entry["mean_delta_rgb"], reverse=True)
    return ranked[:count]


def edge_mask(image: np.ndarray, threshold: int = 12) -> np.ndarray:
    """Binary luminance-gradient mask; tolerates ±1 LSB noise via `threshold`."""
    gray = image.astype(np.int16).mean(axis=2)
    dx = np.zeros_like(gray)
    dy = np.zeros_like(gray)
    dx[:, 1:] = np.abs(gray[:, 1:] - gray[:, :-1])
    dx[:, 1:] += np.abs(gray[:, 1:] - gray[:, :-1])  # both sides of the step
    dy[1:, :] = np.abs(gray[1:, :] - gray[:-1, :])
    dy[1:, :] += np.abs(gray[1:, :] - gray[:-1, :])
    return (dx > threshold) | (dy > threshold)


def dilate(mask: np.ndarray, radius: int = 1) -> np.ndarray:
    """Chebyshev dilation by `radius` pixels (8-connectivity for radius 1)."""
    out = mask.copy()
    padded = np.pad(mask, radius, mode="constant", constant_values=False)
    height, width = mask.shape
    for dy in range(-radius, radius + 1):
        for dx in range(-radius, radius + 1):
            out |= padded[radius + dy : radius + dy + height, radius + dx : radius + dx + width]
    return out


def shift(mask: np.ndarray, dx: int, dy: int) -> np.ndarray:
    """Translate `mask` by (dx, dy); vacated border stays False."""
    out = np.zeros_like(mask)
    height, width = mask.shape
    dst_y = slice(max(dy, 0), height + min(dy, 0))
    dst_x = slice(max(dx, 0), width + min(dx, 0))
    src_y = slice(max(-dy, 0), height + min(-dy, 0))
    src_x = slice(max(-dx, 0), width + min(-dx, 0))
    out[dst_y, dst_x] = mask[src_y, src_x]
    return out


def structural_stats(reference: np.ndarray, candidate: np.ndarray) -> dict:
    ref_edges = edge_mask(reference)
    out_edges = edge_mask(candidate)
    if ref_edges.sum() == 0 or out_edges.sum() == 0:
        return {"ref_edges": int(ref_edges.sum()), "out_edges": int(out_edges.sum()), "coverage_1px": 0.0}
    # "within 1px": each edge pixel needs a counterpart in the 3x3 neighbourhood.
    ref_cover = float((ref_edges & dilate(out_edges)).sum()) / float(ref_edges.sum())
    out_cover = float((out_edges & dilate(ref_edges)).sum()) / float(out_edges.sum())
    # Exact-match coverage per global shift; the best shift must be (0, 0) for
    # there to be no systematic 1px layout offset.
    shifts = []
    for dy in range(-2, 3):
        for dx in range(-2, 3):
            shifted = shift(out_edges, dx, dy)
            exact = float((ref_edges & shifted).sum()) / float(ref_edges.sum())
            shifts.append((exact, dx, dy))
    shifts.sort(reverse=True)
    return {
        "ref_edges": int(ref_edges.sum()),
        "out_edges": int(out_edges.sum()),
        "ref_covered_within_1px": ref_cover,
        "out_covered_within_1px": out_cover,
        "best_exact_shift": {"dx": shifts[0][1], "dy": shifts[0][2], "exact_ratio": shifts[0][0]},
        "zero_shift_exact_ratio": next(entry[0] for entry in shifts if entry[1] == 0 and entry[2] == 0),
    }


def gradient_masks(image: np.ndarray, threshold: int = 18) -> tuple[np.ndarray, np.ndarray]:
    """(vertical_step_mask, horizontal_step_mask): rows vs columns of a luminance step."""
    gray = image.astype(np.int16).mean(axis=2)
    horizontal = np.zeros_like(gray)  # step along y -> a horizontal rule
    vertical = np.zeros_like(gray)  # step along x -> a vertical rule
    horizontal[1:, :] = np.abs(gray[1:, :] - gray[:-1, :])
    vertical[:, 1:] = np.abs(gray[:, 1:] - gray[:, :-1])
    return vertical > threshold, horizontal > threshold


def long_lines(mask: np.ndarray, min_run: int = 300) -> list[float]:
    """Centres of rows/columns that contain a straight run of >= `min_run` steps.

    A 1px rule or panel border produces one such run; a glyph stroke does not.
    Runs are grouped within 1px so an antialiased 1px line counts once.
    """
    hits = []
    for index in range(mask.shape[0]):
        line = mask[index, :]
        if not line.any():
            continue
        edges = np.flatnonzero(np.diff(np.concatenate(([0], line.astype(np.int8), [0]))))
        if edges.size and int((edges[1::2] - edges[0::2]).max()) >= min_run:
            hits.append(float(index))
    grouped: list[float] = []
    for value in hits:
        if grouped and value - grouped[-1] <= 1.0:
            grouped[-1] = (grouped[-1] + value) / 2.0
        else:
            grouped.append(value)
    return grouped


def match_lines(reference: list[float], candidate: list[float], tolerance: float = 2.0) -> dict:
    deltas = []
    only_ref = []
    for value in reference:
        near = [other for other in candidate if abs(other - value) <= tolerance]
        if near:
            deltas.append(min(abs(other - value) for other in near))
        else:
            only_ref.append(value)
    only_candidate = [other for other in candidate if not any(abs(other - value) <= tolerance for value in reference)]
    return {
        "matched": len(deltas),
        "max_delta": max(deltas) if deltas else 0.0,
        "ref_only": only_ref,
        "candidate_only": only_candidate,
    }


def rule_stats(reference: np.ndarray, candidate: np.ndarray) -> dict:
    """Registration of long straight rules (borders, 1px lines, gridlines)."""
    ref_v, ref_h = gradient_masks(reference)
    out_v, out_h = gradient_masks(candidate)
    rows = match_lines(long_lines(ref_h), long_lines(out_h))
    cols = match_lines(long_lines(ref_v.T), long_lines(out_v.T))
    return {
        "horizontal_rules": rows,
        "vertical_rules": cols,
        "max_matched_delta_px": max(rows["max_delta"], cols["max_delta"]),
        "rules_on_one_side_only": len(rows["ref_only"]) + len(rows["candidate_only"]) + len(cols["ref_only"]) + len(cols["candidate_only"]),
    }


def measure(reference_path: Path, candidate_path: Path, max_delta: int) -> dict:
    reference = load_rgb(reference_path)
    candidate = load_rgb(candidate_path)
    if reference.shape != candidate.shape:
        raise SystemExit(
            f"size mismatch for {reference_path.name}: {reference.shape[1]}x{reference.shape[0]} "
            f"vs {candidate.shape[1]}x{candidate.shape[0]}"
        )
    raw = pixel_stats(reference, candidate, max_delta)
    smoothed = pixel_stats(blur(reference), blur(candidate), max_delta)
    blocks = worst_blocks(raw.pop("delta"), max_delta)
    smoothed.pop("delta")
    structure = structural_stats(reference, candidate)
    structure["rules"] = rule_stats(reference, candidate)
    passed = (
        smoothed["ssim"] >= BLUR_MIN_SSIM
        and raw["within_tolerance_ratio"] >= RAW_MIN_WITHIN
    )
    return {
        "name": reference_path.stem,
        "reference": str(reference_path),
        "candidate": str(candidate_path),
        "raw": raw,
        "blurred": smoothed,
        "structure": structure,
        "worst_blocks": blocks,
        "passed": passed,
    }


def resolve_pairs(reference: Path, candidate: Path, theme: str | None) -> list[tuple[Path, Path]]:
    if reference.is_dir() and candidate.is_dir():
        names = sorted(
            path.name
            for path in reference.glob("*.png")
            if (candidate / path.name).exists() and (theme is None or path.name.endswith(f"-{theme}.png"))
        )
        if not names:
            raise SystemExit(f"no matching PNG filenames in {reference} and {candidate}")
        return [(reference / name, candidate / name) for name in names]
    if reference.is_file() and candidate.is_file():
        return [(reference, candidate)]
    raise SystemExit("REF and OUT must both be files or both be directories")


def main() -> int:
    parser = argparse.ArgumentParser(description="Two-tier Cangjie parity metrics (raw + 1px blur)")
    parser.add_argument("reference", type=Path, help="reference PNG or directory")
    parser.add_argument("candidate", type=Path, help="candidate PNG or directory")
    parser.add_argument("--theme", choices=("light", "dark"), default=None)
    parser.add_argument("--max-delta", type=int, default=32)
    parser.add_argument("--json", type=Path, default=None, help="write the full report as JSON")
    args = parser.parse_args()

    results = [measure(ref, out, args.max_delta) for ref, out in resolve_pairs(args.reference, args.candidate, args.theme)]
    header = (
        f"{'pair':<18}{'diff%':>7}{'mean':>7}{'max':>5}{'<=32%':>8}{'SSIM':>8}"
        f"{'  |  blur SSIM':>14}{'blur <=32%':>12}{'edge 1px':>10}{'rule d:':>9}  verdict"
    )
    print(header)
    for result in results:
        raw = result["raw"]
        smoothed = result["blurred"]
        structure = result["structure"]
        print(
            f"{result['name']:<18}"
            f"{100 * raw['different_ratio']:7.2f}{raw['mean_delta_rgb']:7.2f}{raw['max_delta_rgb']:5d}"
            f"{100 * raw['within_tolerance_ratio']:8.2f}{raw['ssim']:8.4f}"
            f"{smoothed['ssim']:14.4f}{100 * smoothed['within_tolerance_ratio']:12.2f}"
            f"{100 * structure['ref_covered_within_1px']:10.2f}"
            f"{structure['rules']['max_matched_delta_px']:9.1f}"
            f"  {'PASS' if result['passed'] else 'FAIL'}"
        )
    failed = [result for result in results if not result["passed"]]
    print(
        f"summary: {len(results) - len(failed)}/{len(results)} pairs pass "
        f"(blurred SSIM>={BLUR_MIN_SSIM}, raw ΔRGB<={args.max_delta} >={100 * RAW_MIN_WITHIN:.0f}%)"
    )
    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(json.dumps({"results": results}, indent=2) + "\n", encoding="utf-8")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
