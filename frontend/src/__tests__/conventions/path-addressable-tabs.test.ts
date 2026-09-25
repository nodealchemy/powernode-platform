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
 * — mirrors the operator's own cutoff, not an arbitrary pick.
 *
 * DETECTION IS A HEURISTIC, NOT A PARSER, and runs on COMMENT- AND
 * STRING-SANITIZED source (see `sanitize`) so nothing textual — a comment,
 * a label containing "path:", a bracket inside a string — can fool either
 * the structural scan or the addressability check. Two independent
 * detection routes, combined:
 *
 *   1. NAME-BASED: a top-level `const`/`let` declaration whose name ends in
 *      "tabs" or "sections" (case-insensitive), assigned an array literal
 *      (directly, or wrapped in one call like `useMemo(() => [...], deps)` —
 *      the wrapper is skipped, not required to look a particular way).
 *   2. USAGE-BASED: a `<TabContainer tabs={NAME} ...>` JSX usage, whichever
 *      array NAME resolves to (regardless of NAME's own spelling — this is
 *      what catches an array like `SIDEBAR_ITEMS` that route (1) can't see
 *      by name alone). Not required to know `<PathTabs>` here: any page
 *      using it is addressable by construction (see below), so it never
 *      needs to reach this route at all.
 *
 * A tab array's entries are counted STRUCTURALLY (every `{` opened directly
 * inside the array, not one property deep in a nested object like
 * `badge: { count }`) — not by requiring an `id:`/`key:` field, so an entry
 * shaped without one still counts.
 *
 * A page is "path-addressable" if:
 *   - EVERY counted entry in the array carries its own `path:` field (not
 *     just the substring `path:` appearing anywhere in the array — an
 *     unrelated nested `path:` on one entry doesn't excuse the other four); OR
 *   - the file renders `<PathTabs` (ObservabilityPage's pattern — its
 *     `basePath` prop is required by that component's own type, so usage
 *     alone is sufficient); OR
 *   - the file both CALLS `useLocation(` and `useNavigate(` (not merely
 *     imports them — an unused import satisfies neither) AND references
 *     `.pathname` somewhere (the manual-sync pattern, e.g.
 *     AutonomyDashboardPage's `sectionFromPath`); OR
 *   - (usage route only) the `<TabContainer` tag itself carries a
 *     `basePath=` attribute.
 *
 * SCOPE IS "PAGE" FILES: only files under a `pages` directory (at any
 * depth) whose filename ends in `Page.tsx` are walked. A modal or detail
 * panel (DevopsTemplateFormModal's 7-tab form, ChannelListPanel's filter
 * strip) is not a navigable destination and isn't in scope.
 *
 * EXTENSIONS CONTRIBUTE THEIR OWN ALLOWLIST, CORE NAMES NONE OF THEM. This
 * file discovers extension frontends generically (every subdirectory of
 * extensions/, and of extensions/private/, that has its own frontend/src —
 * never a specific slug) and, for each one found, looks for a well-known
 * relative file,
 * `ALLOWLIST_RELATIVE_PATH` below, inside that extension's own tree. If
 * present, its entries are merged in — each one validated to fall under
 * THAT extension's own path, so one extension's file can't excuse a path
 * outside itself. core-purity-check.sh forbids core from naming a specific
 * extension; this design makes that structurally impossible rather than a
 * discipline to remember, and doubles as the fix for a not-checked-out
 * extension's entries never being loaded in the first place — no separate
 * "skip if absent" logic needed anywhere below.
 *
 * EQUALITY RATCHET, NOT A CARRIED BASELINE (mirrors no-stub-affordances.test.ts):
 * the merged allowlist is checked for an EXACT match against what the scan
 * finds — an entry can only be REMOVED (once its page converts or a
 * resolved count drops to ≤4), never silently added to as a way to make a
 * new violation pass.
 *
 * NOT LISTED IN CORE'S OWN allowlist, DELIBERATELY (fc-46 brief named these
 * as "leave alone" — verified against the actual code rather than assumed
 * still-useState):
 *   - AutonomyDashboardPage (fc-41) — already path-addressable
 *     (`sectionFromPath` + `useLocation`/`useNavigate` + `.pathname`).
 *   - AuditDashboardPage and SecurityDashboardPage (fc-41/fc-47) — deleted
 *     by fc-41 per the fc-46 scope note; excluded from fc-46 conversion, and
 *     at 4 and 3 tabs respectively neither exceeds the threshold anyway.
 * A page that already satisfies the rule needs no exception; adding one
 * "just in case" would violate the "can only shrink" property this test
 * enforces on itself.
 */

const FRONTEND_SRC = join(__dirname, '..', '..');
const REPO_ROOT = join(FRONTEND_SRC, '..', '..');
const EXTENSIONS_ROOT = join(REPO_ROOT, 'extensions');

// The relative file, INSIDE an extension's own frontend/src, that this guard
// will load as that extension's allowlist contribution if present. A purely
// structural convention — naming this path is not naming an extension.
const ALLOWLIST_RELATIVE_PATH = join('__tests__', 'conventions', 'path-addressable-tabs.allowlist.json');

interface AllowlistEntry {
  path: string;
  note: string;
}

interface ExtensionDir {
  srcDir: string;
  /** Repo-relative root, "extensions/<dir>" or "extensions/private/<dir>" —
   * derived from the directory name on disk at discovery time, never a
   * literal in source. */
  repoRelRoot: string;
}

// Discovered generically — core must not reference a specific extension
// (public or private) by name (core-purity-check.sh).
function discoverExtensionDirs(): ExtensionDir[] {
  const dirs: ExtensionDir[] = [];
  try {
    for (const e of readdirSync(EXTENSIONS_ROOT, { withFileTypes: true })) {
      if (!e.isDirectory()) continue;
      if (e.name === 'private') {
        const privateRoot = join(EXTENSIONS_ROOT, 'private');
        try {
          for (const pe of readdirSync(privateRoot, { withFileTypes: true })) {
            if (!pe.isDirectory()) continue;
            const srcDir = join(privateRoot, pe.name, 'frontend', 'src');
            try {
              if (statSync(srcDir).isDirectory()) {
                dirs.push({ srcDir, repoRelRoot: `extensions/private/${pe.name}` });
              }
            } catch {
              // this private extension has no frontend/src — skip
            }
          }
        } catch {
          // extensions/private/ not present — fine, nothing private installed
        }
      } else {
        const srcDir = join(EXTENSIONS_ROOT, e.name, 'frontend', 'src');
        try {
          if (statSync(srcDir).isDirectory()) {
            dirs.push({ srcDir, repoRelRoot: `extensions/${e.name}` });
          }
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

function loadExtensionAllowlist(ext: ExtensionDir): AllowlistEntry[] {
  let raw: string;
  try {
    raw = readFileSync(join(ext.srcDir, ALLOWLIST_RELATIVE_PATH), 'utf8');
  } catch {
    return []; // no allowlist file contributed by this extension — fine
  }
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return [];
  }
  if (!Array.isArray(parsed)) return [];
  return parsed.filter(
    (e): e is AllowlistEntry =>
      !!e &&
      typeof e.path === 'string' &&
      typeof e.note === 'string' &&
      // An extension's allowlist may only excuse paths inside its OWN tree —
      // a differently-scoped entry is dropped rather than trusted.
      e.path.startsWith(`${ext.repoRelRoot}/`)
  );
}

// Core's own exceptions — plain core paths, no extension named anywhere.
const CORE_ALLOWED: readonly AllowlistEntry[] = [
  { path: 'frontend/src/pages/app/ai/SandboxPage.tsx', note: 'fc-32' },
  { path: 'frontend/src/pages/app/ai/DevOpsTemplatesPage.tsx', note: 'fc-34, fc-44' },
];

function allAllowedEntries(): AllowlistEntry[] {
  const extensionEntries = discoverExtensionDirs().flatMap(loadExtensionAllowlist);
  return [...CORE_ALLOWED, ...extensionEntries];
}

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

// --- Sanitization: strip comments, and blank out string/template-literal
// CONTENTS (delimiters and length preserved so line numbers and bracket
// positions stay stable) — a comment or a label can never satisfy a
// structural or addressability check once this has run. Mirrors
// no-stub-affordances.test.ts's stripComments, extended for strings.
//
// JSX-TEXT APOSTROPHE HAZARD: a `'`/`"` is a real string delimiter in JS,
// but "You don't have permission" as JSX TEXT (not a JS string) also
// contains a bare `'` this scanner has no JSX grammar to tell apart from a
// real one. Left untreated, that apostrophe opens a phantom string that
// doesn't close until the NEXT quote anywhere later in the file — which can
// swallow real code (a `<PathTabs` usage, a whole other function) between
// them (caught empirically: one extension page's "don't" ate ~1200
// characters including its own `<PathTabs>` usage). The fix: a real
// single/double-quoted JS string can never contain a literal newline
// (unescaped) — that's a syntax error — so hitting one while "inString" for
// `'`/`"` can only mean a JSX-text apostrophe/quote, and force-closing the
// string there is always safe for well-formed source. Backtick template
// literals legitimately span lines and are exempted.
//
// Two more fail-open cases, closed here (fc-46 review):
//   - A `'`/`"` BETWEEN TWO WORD CHARACTERS ("Don't") is never a JS string
//     opener — an identifier immediately followed by a string literal is a
//     syntax error — so it is left as text. Without this, an apostrophe on
//     the line that opens a multi-line template swallowed the template's
//     opening backtick, and its closing backtick then opened a phantom one.
//   - A backtick only opens a template literal where an expression can
//     start (see `canStartTemplate`), so a lone backtick in JSX text after a
//     word ("Press the ` key") stays text. One that still opens a template
//     and never closes before end of file is re-scanned as plain text, so
//     an unpaired backtick can't blank everything after it.
const WORD_CHAR = /[A-Za-z0-9_]/;
const TEMPLATE_KEYWORDS = /\b(?:return|typeof|case|await|yield|void|delete|throw|in|of|new|else|do)$/;

// `out` is the sanitized text so far (comments already stripped).
function canStartTemplate(src: string, i: number, out: string): boolean {
  const prevRaw = src[i - 1];
  // Tagged template or call-like position: `css\`...\``, `fn()\`...\``.
  if (prevRaw !== undefined && /[\w$)\]]/.test(prevRaw)) return true;
  const before = out.replace(/\s+$/, '');
  if (before === '') return true;
  const last = before[before.length - 1];
  if ('([{,:?!&|+-*%;=~^'.includes(last)) return true;
  if (last === '>' && before[before.length - 2] === '=') return true; // `=>`
  return TEMPLATE_KEYWORDS.test(before);
}

function sanitize(src: string): string {
  const literalBackticks = new Set<number>();
  for (;;) {
    const { out, unclosedTemplateAt } = sanitizeOnce(src, literalBackticks);
    if (unclosedTemplateAt === null) return out;
    literalBackticks.add(unclosedTemplateAt);
  }
}

function sanitizeOnce(
  src: string,
  literalBackticks: Set<number>
): { out: string; unclosedTemplateAt: number | null } {
  let out = '';
  let i = 0;
  const n = src.length;
  let inString: '"' | "'" | '`' | null = null;
  let openedAt = -1;
  while (i < n) {
    const c = src[i];
    const c2 = src[i + 1];
    if (inString) {
      if (c === '\n' && inString !== '`') {
        // Not a real string (see header): a JSX-text apostrophe/quote.
        // Force-close rather than let it swallow the rest of the file.
        inString = null;
        out += '\n';
        i += 1;
        continue;
      }
      if (c === '\\') {
        out += '  ';
        i += 2;
        continue;
      }
      if (c === inString) {
        out += c;
        inString = null;
        i += 1;
        continue;
      }
      out += c === '\n' ? '\n' : ' ';
      i += 1;
      continue;
    }
    const isQuote = c === '"' || c === "'";
    const betweenWords = isQuote && WORD_CHAR.test(src[i - 1] ?? '') && WORD_CHAR.test(c2 ?? '');
    const opensTemplate = c === '`' && !literalBackticks.has(i) && canStartTemplate(src, i, out);
    if ((isQuote && !betweenWords) || opensTemplate) {
      inString = c as '"' | "'" | '`';
      openedAt = i;
      out += c;
      i += 1;
      continue;
    }
    if (c === '/' && c2 === '/') {
      while (i < n && src[i] !== '\n') i += 1;
      continue;
    }
    if (c === '/' && c2 === '*') {
      i += 2;
      while (i < n && !(src[i] === '*' && src[i + 1] === '/')) {
        out += src[i] === '\n' ? '\n' : ' ';
        i += 1;
      }
      i += 2;
      continue;
    }
    out += c;
    i += 1;
  }
  return { out, unclosedTemplateAt: inString === '`' ? openedAt : null };
}

// Bracket-balances a `[...]` starting at `start` (index of the opening `[`
// in `text`), returning the end index (one past the matching `]`).
function matchArrayEnd(text: string, start: number): number {
  let depth = 0;
  let i = start;
  for (; i < text.length; i++) {
    if (text[i] === '[') depth++;
    else if (text[i] === ']') {
      depth--;
      if (depth === 0) return i + 1;
    }
  }
  return text.length;
}

// Finds `const`/`let NAME = [...]`, optionally wrapped in ONE call like
// `useMemo(() => [...], deps)` or `useCallback(() => [...], deps)` — the
// wrapper is skipped, not required to be any particular helper, so this
// isn't defeated by wrapping the array in a differently-named memoizer.
function findArrayByName(sanitizedText: string, name: string): string | null {
  const escaped = name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const re = new RegExp(
    `\\b(?:const|let)\\s+${escaped}\\s*(?::[^=\\n]+)?=\\s*(?:[\\w.]+\\(\\s*(?:async\\s*)?\\(\\)\\s*=>\\s*)?\\[`
  );
  const m = re.exec(sanitizedText);
  if (!m) return null;
  const start = m.index + m[0].length - 1; // index of the '['
  const end = matchArrayEnd(sanitizedText, start);
  return sanitizedText.slice(start, end);
}

// Every top-level `const`/`let NAME = [...]` (same wrapper-skipping as
// findArrayByName) whose NAME ends in "tabs" or "sections" (case-insensitive).
function findNameBasedTabArrays(sanitizedText: string): { name: string; body: string }[] {
  const declRe = /\b(?:const|let)\s+([A-Za-z_$][\w$]*)\s*(?::[^=\n]+)?=\s*(?:[\w.]+\(\s*(?:async\s*)?\(\)\s*=>\s*)?\[/g;
  const results: { name: string; body: string }[] = [];
  let m: RegExpExecArray | null;
  while ((m = declRe.exec(sanitizedText))) {
    const name = m[1];
    if (!/tabs$/i.test(name) && !/sections$/i.test(name)) continue;
    const start = m.index + m[0].length - 1;
    const end = matchArrayEnd(sanitizedText, start);
    results.push({ name, body: sanitizedText.slice(start, end) });
  }
  return results;
}

// `<TabContainer tabs={NAME} ... basePath=... />` usages — resolves NAME
// via findArrayByName regardless of NAME's own spelling, which is what
// catches a differently-named array (e.g. SIDEBAR_ITEMS) that the
// name-based route above cannot see. Non-greedy to the tag's first `>`;
// a heuristic, like the rest of this file, not a JSX parser.
function findTabContainerUsages(sanitizedText: string): { arrayName: string; hasBasePath: boolean }[] {
  // `(?<!=)>` — not just the first `>`: an inline arrow-function prop like
  // `onTabChange={(id) => setActiveTab(id)}` has a `>` of its own (in `=>`)
  // that a naive non-greedy match stops at, truncating the tag BEFORE a
  // later `basePath=` is ever seen. Excluding an `>` preceded by `=` skips
  // past every `=>` and keeps going to the tag's real closing `>`.
  const tagRe = /<TabContainer\b([\s\S]*?)(?<!=)>/g;
  const results: { arrayName: string; hasBasePath: boolean }[] = [];
  let m: RegExpExecArray | null;
  while ((m = tagRe.exec(sanitizedText))) {
    const tagAttrs = m[1];
    const tabsMatch = /\btabs=\{([A-Za-z_$][\w$]*)\}/.exec(tagAttrs);
    if (!tabsMatch) continue;
    results.push({ arrayName: tabsMatch[1], hasBasePath: /\bbasePath=/.test(tagAttrs) });
  }
  return results;
}

// Counts `{` opened with an ARRAY as the immediately-enclosing bracket —
// i.e. every entry that is a direct element of `arrayBody` (or of a nested
// array reached only through more arrays, e.g. `...(cond ? [{...}] : [])`),
// but NOT an object nested one property deep, like `badge: { count }`
// (whose enclosing bracket when its `{` opens is `{`, not `[`). Operates on
// sanitized text, so a bracket-like character inside a string can't corrupt
// the count. `arrayBody` includes its own outer `[`/`]`.
function countTopLevelEntries(arrayBody: string): number {
  const stack: Array<'[' | '{' | '('> = [];
  let count = 0;
  for (const c of arrayBody) {
    if (c === '[' || c === '{' || c === '(') {
      if (c === '{' && stack[stack.length - 1] === '[') count++;
      stack.push(c);
    } else if (c === ']' || c === '}' || c === ')') {
      stack.pop();
    }
  }
  return count;
}

// The start/end span of every top-level object (same "enclosing bracket is
// `[`" rule as countTopLevelEntries), so addressability can require EVERY
// entry to carry its own `path:` field rather than the substring `path:`
// appearing anywhere in the array.
function topLevelEntrySpans(arrayBody: string): Array<[number, number]> {
  const stack: Array<{ kind: '[' | '{' | '('; start: number }> = [];
  const spans: Array<[number, number]> = [];
  for (let i = 0; i < arrayBody.length; i++) {
    const c = arrayBody[i];
    if (c === '[' || c === '{' || c === '(') {
      const isTopLevelObject = c === '{' && stack.length > 0 && stack[stack.length - 1].kind === '[';
      stack.push({ kind: c, start: i });
      if (isTopLevelObject) {
        // Placeholder end filled in when this frame closes, below.
        spans.push([i, -1]);
      }
    } else if (c === ']' || c === '}' || c === ')') {
      const frame = stack.pop();
      if (frame && frame.kind === '{' && stack.length > 0 && stack[stack.length - 1].kind === '[') {
        const openIdx = spans.findIndex(([s, e]) => s === frame.start && e === -1);
        if (openIdx !== -1) spans[openIdx] = [frame.start, i + 1];
      }
    }
  }
  return spans.filter(([, e]) => e !== -1);
}

function everyEntryHasPath(arrayBody: string): boolean {
  const spans = topLevelEntrySpans(arrayBody);
  if (spans.length === 0) return false;
  return spans.every(([s, e]) => /\bpath\s*:/.test(arrayBody.slice(s, e)));
}

// Manual-sync route: the hook must be CALLED (not merely imported) and its
// result actually consulted (`.pathname`) — an unused `import { useLocation,
// useNavigate } ...` satisfies neither, closing that bypass.
function usesManualLocationSync(sanitizedFileText: string): boolean {
  return (
    /\buseLocation\s*\(/.test(sanitizedFileText) &&
    /\buseNavigate\s*\(/.test(sanitizedFileText) &&
    /\.pathname\b/.test(sanitizedFileText)
  );
}

interface Violation {
  relPath: string;
  name: string;
  count: number;
}

// Pure over (relPath, text) pairs — the real scan reads files into this
// shape, and the fixtures below feed it the same way, so a fixture exercises
// exactly the code path the ratchet does rather than its helpers one by one.
interface SourceFile {
  relPath: string;
  text: string;
}

function findViolations(sources: SourceFile[]): Violation[] {
  const found = new Map<string, Violation>();

  for (const { relPath, text } of sources) {
    const sanitizedText = sanitize(text);
    const manualSync = usesManualLocationSync(sanitizedText);
    const usesPathTabs = /<PathTabs\b/.test(sanitizedText);

    // Route 1: name-based.
    for (const { name, body } of findNameBasedTabArrays(sanitizedText)) {
      const count = countTopLevelEntries(body);
      if (count <= 4) continue;
      const addressable = usesPathTabs || manualSync || everyEntryHasPath(body);
      if (!addressable && !found.has(relPath)) {
        found.set(relPath, { relPath, name, count });
      }
    }

    // Route 2: TabContainer-usage-based — catches an array whose name
    // doesn't end in tabs/sections (e.g. SIDEBAR_ITEMS) but is still wired
    // into a TabContainer directly.
    if (!found.has(relPath)) {
      for (const usage of findTabContainerUsages(sanitizedText)) {
        const body = findArrayByName(sanitizedText, usage.arrayName);
        if (!body) continue;
        const count = countTopLevelEntries(body);
        if (count <= 4) continue;
        const addressable = usesPathTabs || manualSync || usage.hasBasePath || everyEntryHasPath(body);
        if (!addressable) {
          found.set(relPath, { relPath, name: usage.arrayName, count });
          break;
        }
      }
    }
  }

  return [...found.values()];
}

function toRatchetKeys(violations: Violation[]): string[] {
  return [...new Set(violations.map((v) => v.relPath))].sort();
}

describe('convention: tabs/sections arrays with more than 4 entries must be path-addressable (P15)', () => {
  it('core + extensions: the offender set exactly matches the (shrinking) allowlist', () => {
    const repoRelative = (p: string) => relative(REPO_ROOT, p).split(sep).join('/');
    const dirs = [FRONTEND_SRC, ...discoverExtensionDirs().map((e) => e.srcDir)];
    const files = dirs.flatMap((dir) => walkPageFiles(dir));
    const sources = files.map((file) => ({ relPath: repoRelative(file), text: readFileSync(file, 'utf8') }));

    const violations = findViolations(sources);
    const computedKeys = toRatchetKeys(violations);
    const expectedKeys = [...new Set(allAllowedEntries().map((a) => a.path))].sort();

    if (computedKeys.join('\u0000') !== expectedKeys.join('\u0000')) {
      const unexpected = computedKeys.filter((k) => !expectedKeys.includes(k));
      const stale = expectedKeys.filter((k) => !computedKeys.includes(k));
      const detail = violations
        .filter((v) => unexpected.includes(v.relPath))
        .map((v) => `  ${v.relPath} (${v.name}, ${v.count} entries, not path-addressable)`)
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

  // Every allowlist entry actually contributed here (core's own list, plus
  // whatever each PRESENT extension's own allowlist file contributed) must
  // resolve to a real file — no try/catch swallow: an extension that isn't
  // checked out never reaches this array at all (loadExtensionAllowlist
  // returns [] when its file can't be read), so there is no "not checked
  // out" case left to special-case here; every remaining entry SHOULD exist.
  it.each(allAllowedEntries())('allowlist entry "$path" ($note) resolves to a real file', ({ path }) => {
    expect(statSync(join(REPO_ROOT, path)).isFile()).toBe(true);
  });
});

describe('path-addressable-tabs guard: proves it actually fires (not just passes)', () => {
  // The REAL pre-fc-46 RagPage.tsx shape (git show ca9b0e51a, the fc-46
  // parent commit) — not a synthetic fixture: if the guard existed before
  // fc-46, this is exactly the source it would have had to flag.
  const PRE_FC46_RAGPAGE_SNIPPET = `
    import React, { useState } from 'react';

    export const RagContent: React.FC = () => {
      const [activeTab, setActiveTab] = useState<TabType>('knowledge-bases');

      const ragTabs = [
        { id: 'knowledge-bases' as TabType, label: 'Knowledge Bases', icon: Database },
        { id: 'documents' as TabType, label: 'Documents', icon: FileText },
        { id: 'query' as TabType, label: 'Query', icon: Search },
        { id: 'connectors' as TabType, label: 'Connectors', icon: Link },
        { id: 'analytics' as TabType, label: 'Analytics', icon: BarChart3 }
      ];

      return (
        <div>
          {ragTabs.map(tab => (
            <button key={tab.id} onClick={() => setActiveTab(tab.id)}>{tab.label}</button>
          ))}
        </div>
      );
    };
  `;

  it('flags the real pre-fc-46 RagPage shape as a violation', () => {
    const sanitized = sanitize(PRE_FC46_RAGPAGE_SNIPPET);
    const arrays = findNameBasedTabArrays(sanitized);
    expect(arrays).toHaveLength(1);
    const [{ body }] = arrays;
    expect(countTopLevelEntries(body)).toBe(5);
    expect(everyEntryHasPath(body)).toBe(false);
  });

  it('does not flag the same shape once every entry carries a path field', () => {
    const withPaths = PRE_FC46_RAGPAGE_SNIPPET.replace(
      /\{ id: '([\w-]+)' as TabType, label: '([\w ]+)', icon: (\w+) \}/g,
      "{ id: '$1' as TabType, label: '$2', icon: $3, path: '/$1' }"
    );
    const sanitized = sanitize(withPaths);
    const [{ body }] = findNameBasedTabArrays(sanitized);
    expect(countTopLevelEntries(body)).toBe(5);
    expect(everyEntryHasPath(body)).toBe(true);
  });

  it('does not flag a 4-tab (not >4) useState-only page', () => {
    const fourTabs = PRE_FC46_RAGPAGE_SNIPPET.replace(
      /\{ id: 'analytics' as TabType, label: 'Analytics', icon: BarChart3 \}\n\s*/,
      ''
    ).replace(/,(\s*)\];/, '$1];'); // drop the now-trailing comma
    const sanitized = sanitize(fourTabs);
    const [{ body }] = findNameBasedTabArrays(sanitized);
    expect(countTopLevelEntries(body)).toBe(4);
  });

  // --- Bypass-specific fixtures (fc-46 review, item 3) ------------------

  it('is not fooled by a comment mentioning "path:" or PathTabs', () => {
    const withDecoyComment = PRE_FC46_RAGPAGE_SNIPPET.replace(
      'const ragTabs = [',
      '// this page is definitely path-addressable, e.g. path: \'/x\', see PathTabs\n      const ragTabs = ['
    );
    const sanitized = sanitize(withDecoyComment);
    expect(/path\s*:/.test(sanitized)).toBe(false);
    expect(/PathTabs/.test(sanitized)).toBe(false);
    const [{ body }] = findNameBasedTabArrays(sanitized);
    expect(everyEntryHasPath(body)).toBe(false);
  });

  it('is not fooled by ONE entry carrying a path: field while the others do not', () => {
    const onePathField = PRE_FC46_RAGPAGE_SNIPPET.replace(
      "{ id: 'analytics' as TabType, label: 'Analytics', icon: BarChart3 }",
      "{ id: 'analytics' as TabType, label: 'Analytics', icon: BarChart3, path: '/analytics' }"
    );
    const sanitized = sanitize(onePathField);
    const [{ body }] = findNameBasedTabArrays(sanitized);
    expect(everyEntryHasPath(body)).toBe(false);
  });

  it('still counts entries that carry neither an id: nor a key: field', () => {
    const noIdField = `
      const reportsTabs = [
        { label: 'Summary' },
        { label: 'Details' },
        { label: 'Trends' },
        { label: 'Exports' },
        { label: 'Archive' },
      ];
    `;
    const sanitized = sanitize(noIdField);
    const [{ body }] = findNameBasedTabArrays(sanitized);
    // The OLD detector counted `{ id:` / `{ key:` occurrences — zero here,
    // silently passing a 5-entry array. Structural counting (every `{`
    // opened directly inside the array) doesn't care what fields an entry
    // carries.
    expect(countTopLevelEntries(body)).toBe(5);
    expect(everyEntryHasPath(body)).toBe(false);
  });

  it('is not fooled by an unused useLocation/useNavigate import', () => {
    const decoyImport = `import { useLocation, useNavigate } from 'react-router-dom';\n${PRE_FC46_RAGPAGE_SNIPPET}`;
    const sanitized = sanitize(decoyImport);
    expect(usesManualLocationSync(sanitized)).toBe(false);
  });

  it('is not fooled by calling useLocation/useNavigate without ever reading .pathname', () => {
    const decoyCall = PRE_FC46_RAGPAGE_SNIPPET.replace(
      'export const RagContent: React.FC = () => {',
      "export const RagContent: React.FC = () => {\n      const location = useLocation();\n      const navigate = useNavigate();"
    );
    const sanitized = sanitize(decoyCall);
    expect(usesManualLocationSync(sanitized)).toBe(false);
  });

  it('catches a useMemo-wrapped tab array the same as a plain one', () => {
    const memoWrapped = PRE_FC46_RAGPAGE_SNIPPET.replace(
      /const ragTabs = \[([\s\S]*?)\];/,
      'const ragTabs = useMemo(() => [$1], []);'
    );
    const sanitized = sanitize(memoWrapped);
    const arrays = findNameBasedTabArrays(sanitized);
    expect(arrays).toHaveLength(1);
    expect(countTopLevelEntries(arrays[0].body)).toBe(5);
  });

  it('catches a tab array via TabContainer usage even when its name does not end in tabs/sections', () => {
    const differentlyNamed = `
      import React, { useState } from 'react';
      import { TabContainer } from '@/shared/components/layout/TabContainer';

      const SIDEBAR_ITEMS = [
        { id: 'a', label: 'A' },
        { id: 'b', label: 'B' },
        { id: 'c', label: 'C' },
        { id: 'd', label: 'D' },
        { id: 'e', label: 'E' },
      ];

      export const FixturePage: React.FC = () => {
        const [activeTab, setActiveTab] = useState('a');
        return <TabContainer tabs={SIDEBAR_ITEMS} activeTab={activeTab} onTabChange={setActiveTab} />;
      };
    `;
    const sanitized = sanitize(differentlyNamed);
    // Route 1 (name-based) cannot see this array at all.
    expect(findNameBasedTabArrays(sanitized)).toHaveLength(0);
    // Route 2 (usage-based) resolves it via the TabContainer's `tabs=` prop.
    const usages = findTabContainerUsages(sanitized);
    expect(usages).toHaveLength(1);
    expect(usages[0].hasBasePath).toBe(false);
    const body = findArrayByName(sanitized, usages[0].arrayName);
    expect(body).not.toBeNull();
    expect(countTopLevelEntries(body!)).toBe(5);
  });

  // --- End to end through findViolations (fc-46 review) ------------------
  // The fixtures above prove each helper in isolation; these run the same
  // shapes through the real scan, so disabling a route or loosening the
  // every-entry check inside findViolations turns them red.

  const scan = (text: string) => findViolations([{ relPath: 'fixture/FixturePage.tsx', text }]);

  const SIDEBAR_ITEMS_PAGE = `
    import React, { useState } from 'react';
    import { TabContainer } from '@/shared/components/layout/TabContainer';

    const SIDEBAR_ITEMS = [
      { id: 'a', label: 'A' },
      { id: 'b', label: 'B' },
      { id: 'c', label: 'C' },
      { id: 'd', label: 'D' },
      { id: 'e', label: 'E' },
    ];

    export const FixturePage: React.FC = () => {
      const [activeTab, setActiveTab] = useState('a');
      return <TabContainer tabs={SIDEBAR_ITEMS} activeTab={activeTab} onTabChange={setActiveTab} />;
    };
  `;

  it('scan: flags a non-tabs-named array wired into TabContainer (route 2)', () => {
    expect(scan(SIDEBAR_ITEMS_PAGE)).toEqual([
      { relPath: 'fixture/FixturePage.tsx', name: 'SIDEBAR_ITEMS', count: 5 },
    ]);
  });

  it('scan: does not flag the same TabContainer usage once it carries basePath', () => {
    const withBasePath = SIDEBAR_ITEMS_PAGE.replace('onTabChange={setActiveTab} />', 'onTabChange={setActiveTab} basePath="/app/x" />');
    expect(scan(withBasePath)).toEqual([]);
  });

  it('scan: flags a tabs array where only ONE entry carries path: (route 1)', () => {
    const onePathField = PRE_FC46_RAGPAGE_SNIPPET.replace(
      "{ id: 'analytics' as TabType, label: 'Analytics', icon: BarChart3 }",
      "{ id: 'analytics' as TabType, label: 'Analytics', icon: BarChart3, path: '/analytics' }"
    );
    expect(scan(onePathField)).toEqual([{ relPath: 'fixture/FixturePage.tsx', name: 'ragTabs', count: 5 }]);
  });

  it('scan: does not flag the tabs array once every entry carries path:', () => {
    const withPaths = PRE_FC46_RAGPAGE_SNIPPET.replace(
      /\{ id: '([\w-]+)' as TabType, label: '([\w ]+)', icon: (\w+) \}/g,
      "{ id: '$1' as TabType, label: '$2', icon: $3, path: '/$1' }"
    );
    expect(scan(withPaths)).toEqual([]);
  });

  // --- Sanitizer fail-open probes (fc-46 review) -------------------------
  // Each hazard sits EARLY in the file, a real template literal sits AFTER
  // the violating array, and the violation must still be found: if the
  // hazard opened a phantom string/template, it would pair with that later
  // backtick and blank the violating array in between.

  const LATER_VIOLATION = `
    const reportTabs = [
      { id: 'a' }, { id: 'b' }, { id: 'c' }, { id: 'd' }, { id: 'e' },
    ];
    const cls = \`later-\${reportTabs.length}\`;
  `;

  it('sanitizer: a JSX-text apostrophe on the line that opens a multi-line template does not hide a later violation', () => {
    const text = `
      export const Intro = () => <p>Don't</p>{\`a
      b\`};
      ${LATER_VIOLATION}
    `;
    expect(scan(text)).toEqual([{ relPath: 'fixture/FixturePage.tsx', name: 'reportTabs', count: 5 }]);
  });

  it('sanitizer: an unpaired backtick in JSX text does not hide a later violation', () => {
    const text = `
      export const Help = () => <p>Press the \` key to open the console</p>;
      ${LATER_VIOLATION}
    `;
    expect(scan(text)).toEqual([{ relPath: 'fixture/FixturePage.tsx', name: 'reportTabs', count: 5 }]);
  });

  it('sanitizer: an unpaired backtick with no later backtick does not blank the rest of the file', () => {
    // After a comma — a position the opener check accepts as a real template
    // start — so only the unclosed-at-EOF fallback can recover here.
    const text = `
      export const Tail = () => <p>first, \` then the rest</p>;
      ${LATER_VIOLATION.replace(/const cls = .*\n/, '')}
    `;
    expect(scan(text)).toEqual([{ relPath: 'fixture/FixturePage.tsx', name: 'reportTabs', count: 5 }]);
  });

  it('sanitizer: still blanks real template literals and apostrophes inside strings', () => {
    const out = sanitize("const a = `path: x`; const b = 'it\\'s path: y'; const c = tag`PathTabs`;");
    expect(/path\s*:/.test(out)).toBe(false);
    expect(/PathTabs/.test(out)).toBe(false);
  });

  it('does not flag a TabContainer usage that carries basePath', () => {
    const withBasePath = `
      const SIDEBAR_ITEMS = [
        { id: 'a' }, { id: 'b' }, { id: 'c' }, { id: 'd' }, { id: 'e' },
      ];
      export const FixturePage = () => (
        <TabContainer tabs={SIDEBAR_ITEMS} activeTab="a" onTabChange={() => {}} basePath="/app/x" />
      );
    `;
    const sanitized = sanitize(withBasePath);
    const usages = findTabContainerUsages(sanitized);
    expect(usages[0].hasBasePath).toBe(true);
  });
});
