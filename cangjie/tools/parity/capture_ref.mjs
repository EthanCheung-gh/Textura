#!/usr/bin/env node
/**
 * Capture the Web oracle used by the Cangjie parity gate.
 *
 * It launches the existing Textura Web build through the repo's CDP harness,
 * freezes the browser clock at ANCHOR_DATE (so the "relative to today" demo
 * fixtures stop moving), exports the seeded workspace, then screenshots all
 * seven routes at 1440x900 / DPR=1 with the UI font pinned to Noto Sans CJK SC.
 *
 * Usage:
 *   node cangjie/tools/parity/capture_ref.mjs [--base-url http://localhost:1430]
 *
 * Env:
 *   TEXTURA_BASE_URL   default http://localhost:1430
 *   TEXTURA_PARITY_TODAY  default 2026-03-16 (local +08:00)
 */
import { mkdirSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { BASE_URL, Cdp, Page, launchChrome, sleep } from '../../../scripts/qa/lib.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const REF_DIR = join(HERE, 'ref');
const WORKSPACE_PATH = join(HERE, 'workspace.json');
const REPORT_PATH = join(HERE, 'ref', 'capture-report.json');
const ROUTES = ['dashboard', 'calendar', 'okr', 'gtd', 'gantt', 'sop', 'settings'];
const THEMES = ['light', 'dark'];
const FONT = 'Noto Sans CJK SC';
const ANCHOR_DATE = process.env.TEXTURA_PARITY_TODAY || '2026-03-16';
const ANCHOR_TS = new Date(`${ANCHOR_DATE}T10:00:00+08:00`).getTime();

if (!Number.isFinite(ANCHOR_TS)) throw new Error(`bad TEXTURA_PARITY_TODAY: ${ANCHOR_DATE}`);

function argValue(flag, fallback) {
  const index = process.argv.indexOf(flag);
  return index >= 0 && index + 1 < process.argv.length ? process.argv[index + 1] : fallback;
}

function fixedClockScript() {
  return `(() => {
    const FIXED = ${ANCHOR_TS};
    const NativeDate = Date;
    class FixedDate extends NativeDate {
      constructor(...args) {
        if (args.length === 0) { super(FIXED); } else { super(...args); }
      }
      static now() { return FIXED; }
    }
    FixedDate.parse = NativeDate.parse;
    FixedDate.UTC = NativeDate.UTC;
    Object.setPrototypeOf(FixedDate, NativeDate);
    window.Date = FixedDate;
  })();`;
}

const PIN_STYLE = `
  document.documentElement.style.setProperty('--font-ui', "'${FONT}', sans-serif");
  document.body.style.fontFamily = "'${FONT}', sans-serif";
  const style = document.createElement('style');
  style.id = 'textura-parity-style';
  style.textContent = \`
    * { transition: none !important; animation: none !important; caret-color: transparent !important; }
    html, body { scroll-behavior: auto !important; }
    ::-webkit-scrollbar { display: none !important; }
  \`;
  document.head.appendChild(style);
  await document.fonts.ready;
  await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
`;

async function main() {
  const baseUrl = argValue('--base-url', process.env.TEXTURA_BASE_URL || BASE_URL);
  mkdirSync(REF_DIR, { recursive: true });

  const chrome = await launchChrome({ port: 9333, width: 1440, height: 900 });
  const cdp = await Cdp.connect(chrome.wsUrl);
  const page = await Page.create(cdp);
  await page.setViewport(1440, 900);
  const report = { anchor: ANCHOR_DATE, anchorTimestamp: ANCHOR_TS, font: FONT, baseUrl, shots: [] };

  try {
    await cdp.send('Page.addScriptToEvaluateOnNewDocument', { source: fixedClockScript() });

    // 1. Fresh install with the frozen clock -> the app seeds fixtures relative to ANCHOR_DATE.
    await page.goto(`${baseUrl}/?route=dashboard`, { route: 'dashboard' });
    await page.waitFor(
      `(() => { const raw = localStorage.getItem('textura.workspace.v1'); return !!raw && JSON.parse(raw).items.length > 0; })()`,
      { timeout: 20000, label: 'seeded workspace' },
    );
    const workspaceJson = await page.eval(`return localStorage.getItem('textura.workspace.v1');`);
    const workspace = JSON.parse(workspaceJson);
    const frozen = { ...workspace, updatedAt: new Date(ANCHOR_TS).toISOString() };
    if (!frozen.items.some((item) => item.id === 'obj_activation')) {
      throw new Error('seeded workspace does not contain obj_activation; fixtures changed?');
    }
    writeFileSync(WORKSPACE_PATH, `${JSON.stringify(frozen, null, 2)}\n`);
    const workspaceSha = createHash('sha256').update(JSON.stringify(frozen)).digest('hex');
    console.log(`workspace: items=${frozen.items.length} areas=${frozen.areas.length} updatedAt=${frozen.updatedAt}`);
    console.log(`workspace sha256: ${workspaceSha}`);

    // 2. Screenshot every route/theme from the exact same frozen workspace.
    for (const theme of THEMES) {
      for (const route of ROUTES) {
        await page.eval(`
          localStorage.setItem('textura.workspace.v1', ${JSON.stringify(JSON.stringify(frozen))});
          localStorage.setItem('textura.theme', ${JSON.stringify(theme)});
          localStorage.setItem('textura.route', ${JSON.stringify(route)});
        `);
        await page.goto(`${baseUrl}/?route=${encodeURIComponent(route)}`, { route });
        await page.waitFor(`document.documentElement.dataset.theme === ${JSON.stringify(theme)}`, {
          timeout: 10000,
          label: `theme ${theme}`,
        });
        const fontFamily = await page.eval(`${PIN_STYLE}; return getComputedStyle(document.body).fontFamily;`);
        if (!fontFamily.includes(FONT)) {
          throw new Error(`font override failed: ${fontFamily}`);
        }
        const shot = join(REF_DIR, `${route}-${theme}.png`);
        await page.screenshot(shot);
        const size = await page.eval(`return [document.documentElement.clientWidth, document.documentElement.clientHeight];`);
        report.shots.push({ route, theme, shot: `ref/${route}-${theme}.png`, viewport: size, fontFamily });
        console.log(`ref/${route}-${theme}.png  viewport=${size[0]}x${size[1]}  font=${fontFamily}`);
        await sleep(120);
      }
    }
    report.workspace = { path: 'workspace.json', sha256: workspaceSha, items: frozen.items.length };
    writeFileSync(REPORT_PATH, `${JSON.stringify(report, null, 2)}\n`);
  } finally {
    cdp.close();
    await chrome.close();
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
