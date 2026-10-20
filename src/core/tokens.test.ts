import { describe, expect, it } from 'vitest';
import tokensCss from '../styles/tokens.css?raw';

type Tokens = Record<string, string>;

function parseTheme(selector: RegExp): Tokens {
  const block = tokensCss.match(selector);
  if (!block) throw new Error(`tokens.css 缺少主题块 ${selector}`);
  const tokens: Tokens = {};
  for (const entry of block[1].matchAll(/--([\w-]+)\s*:\s*([^;]+);/g)) {
    tokens[`--${entry[1]}`] = entry[2].trim();
  }
  return tokens;
}

const light = parseTheme(/:root\s*\{([^}]*)\}/);
const dark = parseTheme(/html\[data-theme=['"]dark['"]\]\s*\{([^}]*)\}/);

function rgb(hex: string): number[] {
  const value = hex.replace('#', '');
  if (!/^[0-9a-f]{6}$/i.test(value)) throw new Error(`不是 6 位 hex：${hex}`);
  return [0, 2, 4].map((index) => parseInt(value.slice(index, index + 2), 16));
}

function mix(fg: string, bg: string, alpha: number): string {
  const f = rgb(fg);
  const b = rgb(bg);
  return `#${f
    .map((channel, index) =>
      Math.round(channel * alpha + b[index] * (1 - alpha))
        .toString(16)
        .padStart(2, '0'),
    )
    .join('')}`;
}

function luminance(color: string): number {
  const [r, g, b] = rgb(color).map((channel) => channel / 255);
  const linear = (channel: number) =>
    channel <= 0.03928 ? channel / 12.92 : ((channel + 0.055) / 1.055) ** 2.4;
  return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b);
}

function contrast(fg: string, bg: string): number {
  const [high, low] = [luminance(fg), luminance(bg)].sort((a, b) => b - a);
  return (high + 0.05) / (low + 0.05);
}

interface Check {
  label: string;
  fg: string;
  bg: string;
  min: number;
}

/** 关键组合：与 scripts/contrast-audit.mjs 保持同一份清单。 */
function checks(t: Tokens): Check[] {
  const rows: Check[] = [];
  const pair = (label: string, fg: string, bg: string, min = 4.5) => {
    const fgValue = fg.startsWith('--') ? t[fg] : fg;
    const bgValue = bg.startsWith('--') ? t[bg] : bg;
    rows.push({ label, fg: fgValue, bg: bgValue, min });
  };

  for (const background of ['--surface', '--surface-2', '--bg', '--bg-subtle']) {
    pair(`text-faint / ${background}`, t['--text-faint'], background);
    pair(`text-muted / ${background}`, t['--text-muted'], background);
  }
  pair('text / surface', t['--text'], t['--surface']);
  pair('text / surface-2', t['--text'], t['--surface-2']);
  pair('text / accent-soft', t['--text'], t['--accent-soft']);
  pair('brand mark text / bg-subtle', t['--bg-subtle'], t['--text']);
  pair('neutral badge / surface-2', t['--text-muted'], t['--surface-2']);

  for (const background of [
    '--accent-strong',
    '--accent-strong-hover',
    '--accent-strong-active',
    '--accent-strong-disabled',
  ]) {
    pair(`primary text / ${background}`, t['--text-on-strong'], background);
  }
  for (const background of [
    '--danger-strong',
    '--danger-strong-hover',
    '--danger-strong-active',
    '--danger-strong-disabled',
  ]) {
    pair(`danger text / ${background}`, t['--text-on-strong'], background);
  }

  pair('badge accent ink', t['--accent-ink'], t['--accent-soft']);
  pair('badge ok ink', t['--ok-ink'], mix(t['--ok'], t['--surface'], 0.12));
  pair('badge warn ink', t['--warn-ink'], mix(t['--warn'], t['--surface'], 0.14));
  pair('badge danger ink', t['--danger-ink'], mix(t['--danger'], t['--surface'], 0.12));
  pair('badge info ink', t['--info-ink'], mix(t['--info'], t['--surface'], 0.12));

  pair('accent icon / surface', t['--accent'], t['--surface'], 3);
  pair('accent icon / surface-2', t['--accent'], t['--surface-2'], 3);
  pair('accent icon / accent-soft', t['--accent'], t['--accent-soft'], 3);
  for (const tone of ['ok', 'warn', 'danger', 'info']) {
    pair(`${tone} progress / surface-2`, t[`--${tone}`], t['--surface-2'], 3);
  }
  pair('danger text / surface', t['--danger'], t['--surface']);

  return rows;
}

const REQUIRED_TOKENS = [
  '--bg',
  '--bg-subtle',
  '--surface',
  '--surface-2',
  '--border',
  '--border-strong',
  '--text',
  '--text-muted',
  '--text-faint',
  '--accent',
  '--accent-soft',
  '--accent-strong',
  '--accent-strong-hover',
  '--accent-strong-active',
  '--accent-strong-disabled',
  '--danger-strong',
  '--danger-strong-hover',
  '--danger-strong-active',
  '--danger-strong-disabled',
  '--text-on-strong',
  '--accent-ink',
  '--ok-ink',
  '--warn-ink',
  '--danger-ink',
  '--info-ink',
  '--ok',
  '--warn',
  '--danger',
  '--info',
  '--radius-sm',
  '--radius-md',
  '--radius-lg',
  '--shadow-1',
  '--shadow-2',
  '--font-ui',
  '--font-mono',
];

describe('design tokens', () => {
  it('defines the required tokens across the base and dark themes', () => {
    const merged = { ...light, ...dark };
    for (const token of REQUIRED_TOKENS) {
      expect(merged[token], `missing ${token}`).toBeTruthy();
    }
    for (const token of [
      '--bg',
      '--surface',
      '--surface-2',
      '--text',
      '--text-faint',
      '--accent',
      '--accent-strong',
      '--danger-strong',
      '--text-on-strong',
      '--accent-ink',
      '--ok-ink',
      '--warn-ink',
      '--danger-ink',
      '--info-ink',
    ]) {
      expect(dark[token], `dark theme missing ${token}`).toBeTruthy();
    }
  });

  it('keeps the brand accent unchanged', () => {
    expect(light['--accent']).toBe('#c0663a');
    expect(dark['--accent']).toBe('#d97a4c');
  });

  it.each([
    ['light', light],
    ['dark', dark],
  ])('meets WCAG contrast thresholds in the %s theme', (_name, tokens) => {
    const failures = checks(tokens)
      .map((row) => ({ ...row, ratio: contrast(row.fg, row.bg) }))
      .filter((row) => row.ratio < row.min)
      .map((row) => `${row.label}: ${row.ratio.toFixed(2)} < ${row.min}`);
    expect(failures).toEqual([]);
  });
});
