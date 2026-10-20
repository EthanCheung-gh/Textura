#!/usr/bin/env node
/**
 * WCAG 2.1 contrast audit for Textura token combinations.
 *
 * Usage: node scripts/contrast-audit.mjs
 * Exit code 1 when any audited combination falls below its threshold.
 */
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const TOKENS_PATH = resolve(ROOT, 'src/styles/tokens.css');

function parseBlock(css, pattern) {
  const match = css.match(pattern);
  if (!match) throw new Error(`无法在 tokens.css 中找到主题块：${pattern}`);
  const variables = {};
  for (const entry of match[1].matchAll(/--([\w-]+)\s*:\s*([^;]+);/g)) {
    variables[`--${entry[1]}`] = entry[2].trim();
  }
  return variables;
}

function parseTokens(css) {
  return {
    light: parseBlock(css, /:root\s*\{([^}]*)\}/),
    dark: parseBlock(css, /html\[data-theme=['"]dark['"]\]\s*\{([^}]*)\}/),
  };
}

function rgb(hex) {
  const value = hex.replace('#', '').trim();
  if (!/^[0-9a-f]{6}$/i.test(value)) throw new Error(`不是 6 位 hex 颜色：${hex}`);
  return [0, 2, 4].map((index) => parseInt(value.slice(index, index + 2), 16));
}

function hex(values) {
  return `#${values
    .map((value) => Math.round(Math.max(0, Math.min(255, value))).toString(16).padStart(2, '0'))
    .join('')}`;
}

/** alpha 合成：fg 以 alpha 叠在 bg 上（与 CSS color-mix(..., transparent) 的观感一致）。 */
function mix(fg, bg, alpha) {
  const f = rgb(fg);
  const b = rgb(bg);
  return hex(f.map((channel, index) => channel * alpha + b[index] * (1 - alpha)));
}

function luminance(color) {
  const [r, g, b] = rgb(color).map((channel) => channel / 255);
  const linear = (channel) =>
    channel <= 0.03928 ? channel / 12.92 : ((channel + 0.055) / 1.055) ** 2.4;
  return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b);
}

export function contrast(fg, bg) {
  const [high, low] = [luminance(fg), luminance(bg)].sort((a, b) => b - a);
  return (high + 0.05) / (low + 0.05);
}

/** 所有 token 颜色组合清单；阈值：正文 4.5，大字号/图形 3.0。 */
export function auditCombinations(tokens) {
  const t = tokens;
  const rows = [];
  const pair = (label, fg, bg, min = 4.5) => {
    const fgValue = fg.startsWith('--') ? t[fg] : fg;
    const bgValue = bg.startsWith('--') ? t[bg] : bg;
    rows.push({ label, fg: fgValue, bg: bgValue, min, ratio: contrast(fgValue, bgValue) });
  };

  for (const background of ['--surface', '--surface-2', '--bg', '--bg-subtle']) {
    pair(`text-faint on ${background}`, t['--text-faint'], t[background]);
    pair(`text-muted on ${background}`, t['--text-muted'], t[background]);
  }
  pair('text on surface', t['--text'], t['--surface']);
  pair('text on surface-2', t['--text'], t['--surface-2']);
  pair('text on accent-soft', t['--text'], t['--accent-soft']);
  pair('brand mark text on bg-subtle', t['--bg-subtle'], t['--text']);
  pair('neutral badge on surface-2', t['--text-muted'], t['--surface-2']);

  // 实心强调底 + 浅色文字
  for (const background of [
    '--accent-strong',
    '--accent-strong-hover',
    '--accent-strong-active',
    '--accent-strong-disabled',
  ]) {
    pair(`primary text on ${background}`, t['--text-on-strong'], t[background]);
  }
  for (const background of [
    '--danger-strong',
    '--danger-strong-hover',
    '--danger-strong-active',
    '--danger-strong-disabled',
  ]) {
    pair(`danger text on ${background}`, t['--text-on-strong'], t[background]);
  }

  // Badge：语义色 12%~14% 叠在 surface 上
  const badgeSpecs = [
    ['accent', '--accent-soft', '--accent-ink'],
    ['ok', mix(t['--ok'], t['--surface'], 0.12), '--ok-ink'],
    ['warn', mix(t['--warn'], t['--surface'], 0.14), '--warn-ink'],
    ['danger', mix(t['--danger'], t['--surface'], 0.12), '--danger-ink'],
    ['info', mix(t['--info'], t['--surface'], 0.12), '--info-ink'],
  ];
  for (const [name, background, ink] of badgeSpecs) {
    pair(`badge ${name} ink`, t[ink], background);
  }

  // 图标 / 焦点环 / 进度条：非文字图形 3:1
  pair('accent on surface (icon/focus)', t['--accent'], t['--surface'], 3);
  pair('accent on surface-2 (progress)', t['--accent'], t['--surface-2'], 3);
  pair('accent on accent-soft (badge border)', t['--accent'], t['--accent-soft'], 3);
  for (const tone of ['ok', 'warn', 'danger', 'info']) {
    pair(`${tone} on surface-2 (progress)`, t[`--${tone}`], t['--surface-2'], 3);
  }
  pair('danger text on surface', t['--danger'], t['--surface']);

  return rows;
}

const isMain = process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) {
  const css = readFileSync(TOKENS_PATH, 'utf8');
  const themes = parseTokens(css);
  let failures = 0;

  for (const [name, tokens] of Object.entries(themes)) {
    console.log(`\n=== ${name} theme ===`);
    for (const row of auditCombinations(tokens)) {
      const ok = row.ratio >= row.min;
      if (!ok) failures += 1;
      console.log(
        `${ok ? 'PASS' : 'FAIL'}  ${row.label.padEnd(42)} ${row.ratio.toFixed(2)}:1` +
          `  (min ${row.min.toFixed(1)}, fg ${row.fg}, bg ${row.bg})`,
      );
    }
  }

  const total = Object.values(themes).flatMap((tokens) => auditCombinations(tokens)).length;
  console.log(`\n${total - failures}/${total} combinations pass.`);
  if (failures > 0) {
    console.error(`\n${failures} contrast check(s) failed.`);
    process.exitCode = 1;
  }
}
