import { readFileSync, readdirSync, statSync } from 'fs';
import { join, sep, relative } from 'path';

/**
 * Path-addressable tabs guard (P15, fc-46).
 *
 * "URL-addressable tabs everywhere": a page whose tab/section switcher is
 * driven purely by `useState` loses the tab on refresh, can't be deep-linked,
 * and doesn't update the browser's back button. Below a handful of tabs that
 * is a minor papercut; above it, it's the difference between a page that can
 * be bookmarked and one that can't. The threshold here — more than 4 entries
 * in a `tabs`/`sections` array — mirrors the operator's own cutoff, not an
 * arbitrary pick.
 *
 * DETECTION IS A HEURISTIC, NOT A PARSER. It looks for:
 *   - a top-level `const`/`let` declaration whose name ends in "tabs" or
 *     "sections" (case-insensitive: `tabs`, `ragTabs`, `SIDEBAR_ITEMS` does
 *     NOT match — a page using a differently-named array needs its own
 *     naming to line up with this convention, or the guard can't see it);
 *   - assigned an array literal, bracket-balanced from the `[` so a nested
 *     conditional array (`...(cond ? [...] : [])`) doesn't confuse the scan;
 *   - entries counted by `{ id:` / `{ key: ` at any nesting depth within
 *     that array (not a raw `{` count, which would over-count a per-tab
 *     nested object like `badge: { count: ... }`).
 * A page is "path-addressable" if its tabs array contains a `path:` field
 * (the TabContainer basePath convention — see CiCdPage/ExecutionPage), OR
 * the file uses the route-based `PathTabs` component (ObservabilityPage's
 * pattern), OR the file imports both `useLocation` AND `useNavigate` (the
 * manual-sync pattern used where a per-tab `path:` field isn't natural —
 * e.g. AutonomyDashboardPage's `SIDEBAR_ITEMS` + `sectionFromPath`).
 *
 * SCOPE IS "PAGE" FILES, NOT EVERY COMPONENT: only files under a `pages`
 * directory (at any depth) whose filename ends in `Page.tsx` are walked.
 * A modal or detail panel (e.g. DevopsTemplateFormModal's 7-tab form, or
 * ChannelListPanel's filter strip) is not a navigable destination and isn't
 * in scope — the brief says "page", and grandfathering every internal widget
 * would make the guard noisy without protecting anything a user can bookmark.
 *
 * EQUALITY RATCHET, NOT A CARRIED BASELINE (mirrors no-stub-affordances.test.ts):
 * ALLOWED_TAB_VIOLATIONS is checked for an EXACT match against what the scan
 * finds — an entry can only be REMOVED (once its page converts or a resolved
 * count drops to ≤4), never silently added to as a way to make a new
 * violation pass. Every entry names the tracking task; the two supply-chain
 * entries have none yet because this guard is what discovered them (pre-
 * existing, out of fc-46's scope — converting them is a separate task).
 *
 * NOT LISTED, DELIBERATELY (fc-46 brief named these as "leave alone" —
 * verified against the actual code rather than assumed still-useState):
 *   - AutonomyDashboardPage (fc-41) — already path-addressable
 *     (`sectionFromPath` + `useLocation`/`useNavigate`); nothing to
 *     grandfather.
 *   - AuditDashboardPage (fc-41/fc-47) — exactly 4 tabs, not >4.
 *   - SecurityDashboardPage (fc-41/fc-47) — 3 tabs, not >4.
 *   - AdminMarketplacePage (business extension) — converted by fc-46 itself
 *     (see AdminMarketplacePage.tsx in the business extension); this
 *     worktree's own checked-out extensions/private/business submodule copy
 *     may lag that until the pointer bumps, but its 3-tab array is ≤4
 *     regardless, so it never trips this guard either way.
 * A page that already satisfies the rule needs no exception; adding one
 * "just in case" would violate the "can only shrink" property this test
 * enforces on itself (see the ratchet-shape sanity check below).
 */

const FRONTEND_SRC = join(__dirname, '..', '..');
const REPO_ROOT = join(FRONTEND_SRC, '..', '..');
const EXTENSIONS_ROOT = join(REPO_ROOT, 'extensions');

// Discovered generically — core must not reference a specific extension
// (public or private) by name (core-purity-check.sh).
function discoverExtensionSrcDirs(): string[] {
  const dirs: string[] = [];
  try {
    for (const e of readdirSync(EXTENSIONS_ROOT, { withFileTypes: true })) {
      if (!e.isDirectory()) continue;
      if (e.name === 'private') {
        const privateRoot = join(EXTENSIONS_ROOT, 'private');
        try {
          for (const pe of readdirSync(privateRoot, { withFileTypes: true })) {
            if (!pe.isDirectory()) continue;
            const candidate = join(privateRoot, pe.name, 'frontend/src');
            if (statSync(candidate).isDirectory()) dirs.push(candidate);
          }
        } catch {
          // extensions/private/ not present — fine, nothing private installed
        }
      } else {
        const candidate = join(EXTENSIONS_ROOT, e.name, 'frontend/src');
        try {
          if (statSync(candidate).isDirectory()) dirs.push(candidate);
        } catch {
          // this extension has no frontend/src — skip
        }
      }
    }
  } catch {
    return [];
  }
  return dirs;
}

// Named, itemized exceptions — see the module doc comment for what is and
// is not listed, and why. Sorted for a stable diff.
const ALLOWED: readonly { path: string; note: string }[] = [
  { path: 'frontend/src/pages/app/ai/SandboxPage.tsx', note: 'fc-32' },
  { path: 'frontend/src/pages/app/ai/DevOpsTemplatesPage.tsx', note: 'fc-34, fc-44' },
  {
    path: 'extensions/supply-chain/frontend/src/features/supply-chain/pages/SbomDetailPage.tsx',
    note: 'untracked — discovered by this guard\'s introduction, not in fc-46 scope',
  },
  {
    path: 'extensions/supply-chain/frontend/src/features/supply-chain/pages/VendorDetailPage.tsx',
    note: 'untracked — discovered by this guard\'s introduction, not in fc-46 scope',
  },
];

function walkPageFiles(dir: string, acc: string[] = []): string[] {
  let entries: import('fs').Dirent[];
  try {
    entries = readdirSync(dir, { withFileTypes: true });
  } catch {
    return acc;
  }
  for (const entry of entries) {
    if (entry.name === 'node_modules' || entry.name.startsWith('.')) continue;
    const full = join(dir, entry.name);
    if (entry.isDirectory()) {
      walkPageFiles(full, acc);
    } else if (/Page\.tsx$/.test(entry.name) && (full + sep).includes(sep + 'pages' + sep)) {
      acc.push(full);
    }
  }
  return acc;
}

interface TabArray {
  varName: string;
  body: string;
}

// Finds every `const`/`let NAME = [...]` declaration whose NAME ends in
// "tabs" or "sections" (case-insensitive), bracket-balanced from the `[`.
function findTabArrays(text: string): TabArray[] {
  const declRe = /\b(?:const|let)\s+([A-Za-z_$][\w$]*)\s*(?::[^=\n]+)?=\s*\[/g;
  const results: TabArray[] = [];
  let m: RegExpExecArray | null;
  while ((m = declRe.exec(text))) {
    const varName = m[1];
    if (!/tabs$/i.test(varName) && !/sections$/i.test(varName)) continue;
    const start = m.index + m[0].length - 1; // index of the opening '['
    let depth = 0;
    let i = start;
    for (; i < text.length; i++) {
      if (text[i] === '[') depth++;
      else if (text[i] === ']') {
        depth--;
        if (depth === 0) {
          i++;
          break;
        }
      }
    }
    results.push({ varName, body: text.slice(start, i) });
  }
  return results;
}

// Counts entries by `{ id:` / `{ key:` at ANY nesting depth — a raw `{`
// count would over-count a per-tab nested object (e.g. AuditDashboardPage's
// `badge: { count: ... }`), but every tab/section object in this codebase
// opens with `id:` or (ChannelListPanel-style) `key:` as its first field.
function countEntries(arrayBody: string): number {
  const m = arrayBody.match(/\{\s*\n?\s*(?:id|key)\s*:/g);
  return m ? m.length : 0;
}

function isPathAddressable(fileText: string, arrayBody: string): boolean {
  if (/\bpath\s*:/.test(arrayBody)) return true;
  if (/\bPathTabs\b/.test(fileText)) return true;
  if (/\buseLocation\b/.test(fileText) && /\buseNavigate\b/.test(fileText)) return true;
  return false;
}

interface Violation {
  relPath: string;
  varName: string;
  count: number;
}

function findViolations(files: string[], repoRelative: (p: string) => string): Violation[] {
  const found: Violation[] = [];
  for (const file of files) {
    const text = readFileSync(file, 'utf8');
    for (const { varName, body } of findTabArrays(text)) {
      const count = countEntries(body);
      if (count > 4 && !isPathAddressable(text, body)) {
        found.push({ relPath: repoRelative(file), varName, count });
      }
    }
  }
  return found;
}

function toRatchetKeys(violations: Violation[]): string[] {
  return [...new Set(violations.map((v) => v.relPath))].sort();
}

describe('convention: tabs/sections arrays with more than 4 entries must be path-addressable (P15)', () => {
  it('core + extensions: the offender set exactly matches the (shrinking) allowlist', () => {
    const repoRelative = (p: string) => relative(REPO_ROOT, p).split(sep).join('/');
    const dirs = [FRONTEND_SRC, ...discoverExtensionSrcDirs()];
    const files = dirs.flatMap((dir) => walkPageFiles(dir));

    const violations = findViolations(files, repoRelative);
    const computedKeys = toRatchetKeys(violations);
    const expectedKeys = [...ALLOWED.map((a) => a.path)].sort();

    // Sanity: the allowlist itself declares no duplicate path twice.
    expect(new Set(expectedKeys).size).toBe(expectedKeys.length);

    if (computedKeys.join('\u0000') !== expectedKeys.join('\u0000')) {
      const unexpected = computedKeys.filter((k) => !expectedKeys.includes(k));
      const stale = expectedKeys.filter((k) => !computedKeys.includes(k));
      const detail = violations
        .filter((v) => unexpected.includes(v.relPath))
        .map((v) => `  ${v.relPath} (${v.varName}, ${v.count} entries, not path-addressable)`)
        .join('\n');
      // eslint-disable-next-line no-console
      console.error(
        `path-addressable-tabs: ratchet mismatch.\n` +
          (unexpected.length ? `New violation(s) — convert the page or add a tracked allowlist entry:\n${detail}\n` : '') +
          (stale.length ? `Stale allowlist entries to remove (already fixed): ${stale.join(', ')}\n` : '')
      );
    }

    expect(computedKeys).toEqual(expectedKeys);
  });

  // Every allowlist entry must actually exist and actually be a checked-out
  // page from THIS scan's own perspective — an entry naming a file that has
  // since moved or been deleted would silently stop excusing anything (the
  // ratchet would just show it as "stale" above, easy to miss in a wall of
  // green). Skipped when the checkout doesn't have that extension at all
  // (a public clone with no supply-chain/business extension checked out).
  it.each(ALLOWED)('allowlist entry "$path" ($note) still resolves to a real file', ({ path }) => {
    try {
      expect(statSync(join(REPO_ROOT, path)).isFile()).toBe(true);
    } catch {
      // Not checked out in this clone — not a failure, just untestable here.
    }
  });
});

describe('path-addressable-tabs guard: proves it actually fires (not just passes)', () => {
  // A deliberately-planted violation: 5 tabs, useState-only, no path field,
  // no PathTabs, no useLocation/useNavigate. If this guard's own detector
  // can't catch this, it can't be trusted to catch a real one either.
  const PLANTED_VIOLATION = `
    import React, { useState } from 'react';

    const reportsTabs = [
      { id: 'summary', label: 'Summary' },
      { id: 'details', label: 'Details' },
      { id: 'trends', label: 'Trends' },
      { id: 'exports', label: 'Exports' },
      { id: 'archive', label: 'Archive' },
    ];

    export const PlantedFixturePage: React.FC = () => {
      const [activeTab, setActiveTab] = useState('summary');
      return (
        <div>
          {reportsTabs.map((t) => (
            <button key={t.id} onClick={() => setActiveTab(t.id)}>{t.label}</button>
          ))}
        </div>
      );
    };
  `;

  it('flags a planted 5-tab useState-only page as a violation', () => {
    const arrays = findTabArrays(PLANTED_VIOLATION);
    expect(arrays).toHaveLength(1);
    const [{ body }] = arrays;
    expect(countEntries(body)).toBe(5);
    expect(isPathAddressable(PLANTED_VIOLATION, body)).toBe(false);
  });

  // Negative-space companion: the SAME 5-tab shape, but with a `path:` field
  // per entry, must NOT be flagged — proves the guard doesn't just fire on
  // "more than 4", it specifically requires the absence of addressability.
  const PLANTED_PATH_ADDRESSABLE = PLANTED_VIOLATION.replace(
    /\{ id: '(\w+)', label: '(\w+)' \}/g,
    "{ id: '$1', label: '$2', path: '/$1' }"
  );

  it('does not flag the same shape once it carries path fields', () => {
    const arrays = findTabArrays(PLANTED_PATH_ADDRESSABLE);
    const [{ body }] = arrays;
    expect(countEntries(body)).toBe(5);
    expect(isPathAddressable(PLANTED_PATH_ADDRESSABLE, body)).toBe(true);
  });

  it('does not flag a 4-tab (not >4) useState-only page', () => {
    const fourTabs = PLANTED_VIOLATION.replace(
      /\{ id: 'archive', label: 'Archive' \},\n\s*/,
      ''
    );
    const arrays = findTabArrays(fourTabs);
    const [{ body }] = arrays;
    expect(countEntries(body)).toBe(4);
  });
});
