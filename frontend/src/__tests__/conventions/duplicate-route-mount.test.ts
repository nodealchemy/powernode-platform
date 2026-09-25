import { readFileSync, readdirSync } from 'fs';
import { join, sep } from 'path';

/**
 * Duplicate/alias/redirect-route mount guard (fc-25).
 *
 * fc-25 removed several routes that mounted the exact same page component at
 * two different top-level paths for no reason other than history — e.g.
 * `/app/content/kb/admin` and `/app/content/kb/manage` both rendered
 * `KnowledgeBaseAdminPage`, and `/system/overview` duplicated `/system`
 * (both `SystemOverviewPage`) — and, separately, a set of `redirectTo(...)`/
 * `redirectBySubpath(...)` routes that forwarded an old path to its new one
 * with `<Navigate replace>` instead of deleting it outright. This guard is
 * the regression check for BOTH shapes: it scans the two places top-level
 * route tables are declared as static config — `pages/app/DashboardPage.tsx`'s
 * `<Routes>` and every checked-out extension's `frontend/src/register.ts`
 * `registerRoutes(...)` call.
 *
 * Two independent checks live here:
 *
 * 1. DUPLICATE MOUNT — flags any component mounted at two or more distinct,
 *    non-parameterised paths within the same route list (equality ratchet
 *    against a named, reasoned allowlist).
 * 2. REINTRODUCED REDIRECT — flags any non-index, non-`*` route/entry whose
 *    own declaration contains the word `Navigate` or `redirectTo` anywhere
 *    (a direct `element={<Navigate .../>}`, a `component: redirectTo(...)`
 *    call, or an inline wrapper reproducing either shape) — asserted empty,
 *    always. fc-25's whole point was deleting these outright, not aliasing;
 *    this half exists so reintroducing the pattern fails loudly instead of
 *    landing quietly as "a route that happens to redirect".
 *
 * Scope, deliberately narrow (matches what fc-25 actually touched):
 *  - Only DashboardPage.tsx's own <Routes> and each register.ts's
 *    registerRoutes array. A duplicate or redirect rendered by a nested
 *    <Routes> INSIDE a page component (e.g. the Cost hub's own "Overview"
 *    tab, or a tab-default `<Route index element={<Navigate .../>} />`) is
 *    invisible to a scan of these two files by construction. Those are a
 *    DIFFERENT, allowed shape (a tab-default redirect within a page's own
 *    tab set, or a generic `*` → default-tab fallback) — fc-25 review item 9
 *    ruled explicitly that in-page tab-default Navigate fallbacks are fine
 *    as long as none of them names a path this campaign deleted; that is a
 *    per-page manual check, not this guard's job.
 *  - A path containing a `:param` segment is excluded from the DUPLICATE
 *    MOUNT comparison only: a component legitimately reached via more than
 *    one parameterised path (or a mix of a parameterised and a static path)
 *    is not the "two identical static bookmarks" shape that check targets.
 *    The REDIRECT check has no such exclusion — a parameterised route that
 *    is ALSO a bare redirect is exactly as wrong as a static one.
 *  - A path ending in `/*` counts as ONE mount for duplicate-mount purposes,
 *    like any other literal path — it is not expanded or treated specially,
 *    just compared as a string.
 *  - Comparisons are PER FILE (per route list), not across files: two
 *    different extensions coincidentally importing/registering a
 *    same-named component is not what the duplicate-mount check is for.
 *
 * EQUALITY RATCHET (mirrors nav-link-reachability.test.ts): the duplicate-
 * mount assertion is `toEqual(ALLOWLIST)` against the full, unfiltered
 * computed finding set (sorted), not a count and not a filter-then-assert-
 * empty. A new duplicate mount not yet in ALLOWLIST fails; an ALLOWLIST
 * entry that stops reproducing (fixed, or the component/route renamed away)
 * ALSO fails, so nothing here can go stale silently. The redirect check's
 * "allowlist" is the empty array — there is no legitimate top-level redirect
 * route in this codebase, by design.
 *
 * PRIVATE EXTENSIONS ARE SCANNED BUT NOT RATCHETED — same reasoning as
 * nav-link-reachability.test.ts: a private extension is remote-only and
 * absent from most checkouts, so a finding there can't live in a portable
 * allowlist. Findings (both kinds) are only reported via console.warn.
 */

const FRONTEND_SRC = join(__dirname, '..', '..');
const REPO_ROOT = join(FRONTEND_SRC, '..', '..');
const EXTENSIONS_ROOT = join(REPO_ROOT, 'extensions');
const PRIVATE_EXTENSIONS_ROOT = join(EXTENSIONS_ROOT, 'private') + sep;

type RouteEntry = { path: string; component: string };

function stripComments(src: string): string {
  let out = '';
  let i = 0;
  const n = src.length;
  let inString: '"' | "'" | '`' | null = null;
  while (i < n) {
    const c = src[i];
    const c2 = src[i + 1];
    if (inString) {
      out += c;
      if (c === '\\') {
        if (i + 1 < n) out += src[i + 1];
        i += 2;
        continue;
      }
      if (c === inString) inString = null;
      i += 1;
      continue;
    }
    if (c === '"' || c === "'" || c === '`') {
      inString = c;
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
      while (i < n && !(src[i] === '*' && src[i + 1] === '/')) i += 1;
      i += 2;
      continue;
    }
    out += c;
    i += 1;
  }
  return out;
}

// Replaces the CONTENTS of every quoted string with spaces (keeping the
// quotes and everything else in place) — used only to make the `index`
// boolean-prop test safe against a path literal that happens to contain the
// substring "index" (e.g. `path="/foo/index"`).
function blankQuotedContents(s: string): string {
  let out = '';
  let i = 0;
  let inString: '"' | "'" | null = null;
  while (i < s.length) {
    const c = s[i];
    if (inString) {
      if (c === inString) {
        inString = null;
        out += c;
      } else {
        out += ' ';
      }
      i += 1;
      continue;
    }
    if (c === '"' || c === "'") {
      inString = c;
      out += c;
      i += 1;
      continue;
    }
    out += c;
    i += 1;
  }
  return out;
}

// Discovered generically, never hardcoded by name (core-purity-check.sh) —
// mirrors nav-link-reachability.test.ts.
function discoverExtensionRegisterFiles(): string[] {
  const files: string[] = [];
  const candidateDirs: string[] = [];
  try {
    for (const e of readdirSync(EXTENSIONS_ROOT, { withFileTypes: true })) {
      if (!e.isDirectory()) continue;
      if (e.name === 'private') {
        try {
          for (const pe of readdirSync(PRIVATE_EXTENSIONS_ROOT, { withFileTypes: true })) {
            if (pe.isDirectory()) candidateDirs.push(join(PRIVATE_EXTENSIONS_ROOT, pe.name));
          }
        } catch {
          // extensions/private/ not present — nothing private installed
        }
      } else {
        candidateDirs.push(join(EXTENSIONS_ROOT, e.name));
      }
    }
  } catch {
    return [];
  }
  for (const dir of candidateDirs) {
    const candidate = join(dir, 'frontend/src/register.ts');
    try {
      readFileSync(candidate);
      files.push(candidate);
    } catch {
      // no frontend/register.ts for this checked-out extension — skip
    }
  }
  return files;
}

function isPrivateExtensionFile(file: string): boolean {
  return file.startsWith(PRIVATE_EXTENSIONS_ROOT);
}

// ─── Route-table extraction (shared by both checks) ──────────────────────

// Finds every `<Route ...>` block in `src`, MULTI-LINE SAFE: scans from each
// `<Route` opening to the matching self-close `/>` (or bare `>`) at BRACE
// DEPTH ZERO, so a nested `{...}` prop (e.g. `element={<Foo bar={{ x: 1 }} />}`)
// or a nested JSX self-closing tag inside `element={...}` never terminates
// the block early, and the block's own text is intact regardless of how many
// lines the JSX is split across.
function extractRouteBlocks(src: string): string[] {
  const blocks: string[] = [];
  const openRe = /<Route\b/g;
  let m: RegExpExecArray | null;
  while ((m = openRe.exec(src))) {
    let depth = 0;
    let j = m.index;
    for (; j < src.length; j++) {
      const c = src[j];
      if (c === '{') depth++;
      else if (c === '}') depth--;
      else if (depth === 0 && c === '/' && src[j + 1] === '>') {
        j += 2;
        break;
      } else if (depth === 0 && c === '>') {
        j += 1;
        break;
      }
    }
    blocks.push(src.slice(m.index, j));
    openRe.lastIndex = j;
  }
  return blocks;
}

function routeBlockPath(block: string): string | null {
  const m = /\bpath=["']([^"']+)["']/.exec(block);
  return m ? m[1] : null;
}

// True only for React Router's boolean `index` prop (`<Route index .../>`),
// never for a path literal that happens to contain "index" as a substring
// (quoted string contents are blanked before the word-boundary test).
function isIndexRoute(block: string): boolean {
  return /\bindex\b(?!\s*=)/.test(blankQuotedContents(block));
}

// Extracts the `[...]` array body of `featureRegistry.registerRoutes('<slug>',
// [ ... ])`, by bracket-depth matching — these arrays are multi-line,
// multi-property object literals (mirrors nav-link-reachability.test.ts).
function extractRegisterRoutesBodies(src: string): string[] {
  const bodies: string[] = [];
  const callRe = /featureRegistry\.registerRoutes\s*\(/g;
  let cm: RegExpExecArray | null;
  while ((cm = callRe.exec(src))) {
    const bracketStart = src.indexOf('[', cm.index);
    if (bracketStart === -1) continue;
    let depth = 0;
    let j = bracketStart;
    for (; j < src.length; j++) {
      if (src[j] === '[') depth++;
      else if (src[j] === ']') {
        depth--;
        if (depth === 0) break;
      }
    }
    bodies.push(src.slice(bracketStart, j + 1));
  }
  return bodies;
}

// Splits an array body into its top-level `{ ... }` object entries by
// brace-depth matching. Returns the RAW entry text — callers pull whatever
// fields they need (path / component identifier / a word-search over the
// whole entry) rather than this function deciding what counts as "enough"
// to keep, so an entry with a non-identifier `component:` value (an inline
// arrow function, say) is never silently dropped before a caller gets a
// chance to look at it.
function splitTopLevelEntries(body: string): string[] {
  const entries: string[] = [];
  let depth = 0;
  let start = -1;
  for (let i = 0; i < body.length; i++) {
    const c = body[i];
    if (c === '{') {
      if (depth === 0) start = i;
      depth++;
    } else if (c === '}') {
      depth--;
      if (depth === 0 && start !== -1) {
        entries.push(body.slice(start, i + 1));
        start = -1;
      }
    }
  }
  return entries;
}

function entryPath(entry: string): string | null {
  const m = /path:\s*['"]([^'"]+)['"]/.exec(entry);
  return m ? m[1] : null;
}

// The component may be a bare identifier (`ComputePage`) or a call
// expression (`redirectTo('/app/...')`, `withFooProviders(BarPage)`) —
// either way the leading identifier is what stands in for "what actually
// renders here", which is exactly the granularity the DUPLICATE MOUNT check
// needs (two paths calling the same wrapper/factory are still "the same
// thing mounted twice").
//
// An INLINE wrapper (`component: () => <ComputePage />`, with no leading
// identifier at all) falls back to the first CAPITALISED identifier found in
// the component field's own value — for JSX/component-returning code that is
// virtually always the actual rendered component, and it is what lets two
// routes wrapping the SAME component in an inline (non-factory, non-redirect)
// wrapper still register as a duplicate mount. This deliberately does NOT
// special-case `redirectTo`/`Navigate` (both lowercase-leading or not
// "the component" in the relevant sense) — a route shaped like that is the
// REDIRECT check's job, not this one's, and correctly resolves to null here.
function entryComponentIdentifier(entry: string): string | null {
  const bareMatch = /component:\s*([A-Za-z_$][A-Za-z0-9_$]*)/.exec(entry);
  if (bareMatch) return bareMatch[1];

  const startMatch = /component:\s*/.exec(entry);
  if (!startMatch) return null;
  const valueStart = startMatch.index + startMatch[0].length;

  // Isolate the component field's own value: scan from just after
  // `component:` to the next top-level `, key:` separator or the entry's
  // own closing bracket — whichever comes first — so a later field (e.g.
  // `, permission: 'AdminPage'`) can never be mistaken for the component.
  let depth = 0;
  let valueEnd = entry.length;
  for (let i = valueStart; i < entry.length; i++) {
    const c = entry[i];
    if (c === '(' || c === '{' || c === '[') {
      depth++;
    } else if (c === ')' || c === '}' || c === ']') {
      if (depth === 0) {
        valueEnd = i;
        break;
      }
      depth--;
    } else if (c === ',' && depth === 0) {
      valueEnd = i;
      break;
    }
  }

  const idMatch = /\b([A-Z][A-Za-z0-9_]*)\b/.exec(entry.slice(valueStart, valueEnd));
  return idMatch ? idMatch[1] : null;
}

// ─── Check 1: duplicate mount ─────────────────────────────────────────────

// DashboardPage.tsx's own <Routes> — one entry per non-index route, keyed by
// the LAST capitalised JSX tag opened in the block (wrappers like
// `ProtectedRoute`/`ClusterProvider`/`HostProvider` always sit OUTSIDE the
// real page component in this codebase, so the innermost/last-opened tag is
// it). Block-based (not line-based), so a route split across lines is still
// captured correctly.
function extractDashboardRouteEntries(src: string): RouteEntry[] {
  const entries: RouteEntry[] = [];
  const tagRe = /<([A-Z][A-Za-z0-9]*)/g;
  for (const block of extractRouteBlocks(src)) {
    if (isIndexRoute(block)) continue;
    const path = routeBlockPath(block);
    if (!path) continue;
    tagRe.lastIndex = 0;
    let lastTag: string | null = null;
    let tagMatch: RegExpExecArray | null;
    while ((tagMatch = tagRe.exec(block))) {
      if (tagMatch[1] === 'Route') continue;
      lastTag = tagMatch[1];
    }
    if (lastTag) entries.push({ path, component: lastTag });
  }
  return entries;
}

function extractExtensionRouteEntries(src: string): RouteEntry[] {
  const entries: RouteEntry[] = [];
  for (const body of extractRegisterRoutesBodies(src)) {
    for (const raw of splitTopLevelEntries(body)) {
      const path = entryPath(raw);
      const component = entryComponentIdentifier(raw);
      if (path && component) entries.push({ path, component });
    }
  }
  return entries;
}

// Groups entries by component, drops any path containing a `:param`
// segment, and reports every component left mounted at 2+ distinct paths.
function findDuplicateMounts(entries: RouteEntry[], label: string): string[] {
  const byComponent = new Map<string, Set<string>>();
  for (const e of entries) {
    if (e.path.includes(':')) continue;
    if (!byComponent.has(e.component)) byComponent.set(e.component, new Set());
    byComponent.get(e.component)!.add(e.path);
  }
  const findings: string[] = [];
  for (const [component, paths] of byComponent) {
    if (paths.size >= 2) {
      findings.push(`${label}: ${component} -> ${[...paths].sort().join(', ')}`);
    }
  }
  return findings.sort();
}

// ─── Check 2: reintroduced redirect ───────────────────────────────────────

// Deliberately coarse (a whole-block/whole-entry word search, not a full
// parser): flags a non-index, non-`*` route/entry whenever the word
// `Navigate` or `redirectTo` appears ANYWHERE in its own declaration. That
// covers a direct `element={<Navigate .../>}`, a `component: redirectTo(...)`
// call, a `component: () => <Navigate .../>` (or `redirectTo(...)`) inline
// wrapper, and any of those spread across multiple lines — all four are the
// same "this route secretly forwards somewhere else" shape fc-25 deleted.
// It will NOT catch a helper defined elsewhere and referenced only by an
// unrelated identifier (an inline wrapper is written IN the entry itself by
// definition) — that dodge only works by giving the helper a name unrelated
// to Navigate/redirectTo, at which point reusing it across 2+ routes is
// exactly what the duplicate-mount check above already catches.
const REDIRECT_WORD_RE = /\b(Navigate|redirectTo)\b/;

function findRedirectRoutesInDashboardSrc(src: string, label: string): string[] {
  const findings: string[] = [];
  for (const block of extractRouteBlocks(src)) {
    if (isIndexRoute(block)) continue;
    const path = routeBlockPath(block);
    if (path === null || path === '*') continue;
    if (REDIRECT_WORD_RE.test(block)) {
      findings.push(`${label}: ${path} -> redirect (Navigate/redirectTo)`);
    }
  }
  return findings.sort();
}

function findRedirectEntriesInExtensionSrc(src: string, label: string): string[] {
  const findings: string[] = [];
  for (const body of extractRegisterRoutesBodies(src)) {
    for (const raw of splitTopLevelEntries(body)) {
      const path = entryPath(raw);
      if (path === null) continue;
      if (REDIRECT_WORD_RE.test(raw)) {
        findings.push(`${label}: ${path} -> redirect (Navigate/redirectTo)`);
      }
    }
  }
  return findings.sort();
}

// ─── Named, itemized duplicate-mount exceptions ───────────────────────────
//
// NOT a count-based baseline (see module doc comment). Every entry below is
// the SAME pre-existing pattern: one hub/tab component mounted at several
// static per-tab paths (each independently permission-gated, or internally
// branching on the active path) plus, in most cases, a `/*` wildcard
// fallback for anything else. That is a deliberate navigation pattern
// already used throughout this codebase (AIAgentsPage,
// IntegrationsWebhooksPage) — not an accidental "two routes, one panel" duplicate like
// the ones fc-25 fixed. Consolidating any of these into a single `/*` route
// is a design decision for its own owning campaign, not fc-25's
// alias/redirect cleanup.
const ALLOWLIST: readonly string[] = [
  // AI ▸ Agents primary-nav tabs (cards/community) plus the `/*` fallback —
  // fc-13/fc-10 own this surface's tab consolidation. (Its autonomy tab
  // moved to AI → Control in fc-41.)
  // fc-25 review item 3 deleted the /ai/agents/marketplace alias (it also
  // collided with a private extension's own /ai/agents/marketplace route).
  // fc-46 review widened /ai/agents/community to /ai/agents/community/* (its
  // Community tab has its own sub-paths).
  'DashboardPage.tsx: AIAgentsPage -> /ai/agents/*, /ai/agents/cards, /ai/agents/community/*',
  // DevOps ▸ Integrations & Webhooks' two genuinely different tabs
  // (Integrations default at the bare path, Webhook endpoints). The
  // webhook-endpoints tab needs its own static route so it outranks the
  // sibling /devops/integrations/:id/* detail route (fc-44). The Docker and
  // Swarm hubs' per-tab routes that used to be listed here are now nested
  // inside ContainersHubPage's own <Routes>, outside this scan.
  'DashboardPage.tsx: IntegrationsWebhooksPage -> /devops/integrations, /devops/integrations/webhook-endpoints',
  // (fc-43: the LearningPage entry left with its routes — Learning is a tab
  // of the /ai/knowledge/* hub now, routed inside KnowledgePage.)
  // AI ▸ Missions' two genuinely different tabs (Missions default, Code
  // Factory) — not an alias pair; fc-25 review item 3 deleted the
  // /ai/missions/all and /ai/missions/completed aliases (both were byte-
  // identical to bare /ai/missions: MissionsContent has no status-tab or
  // query-param filtering of its own), leaving just these two real tabs.
  'DashboardPage.tsx: MissionsPageWrapper -> /ai/missions, /ai/missions/code-factory/*',
];

describe('nav convention: no component is mounted at two non-parameterised paths (fc-25)', () => {
  it('the duplicate-mount set exactly matches the named exception list (equality ratchet)', () => {
    const findings: string[] = [];

    const dashboardSrc = stripComments(
      readFileSync(join(FRONTEND_SRC, 'pages/app/DashboardPage.tsx'), 'utf8')
    );
    findings.push(...findDuplicateMounts(extractDashboardRouteEntries(dashboardSrc), 'DashboardPage.tsx'));

    const registerFiles = discoverExtensionRegisterFiles();
    const publicRegisterFiles = registerFiles.filter((f) => !isPrivateExtensionFile(f));
    const privateRegisterFiles = registerFiles.filter(isPrivateExtensionFile);

    for (const file of publicRegisterFiles) {
      const label = file.slice(REPO_ROOT.length + 1);
      const src = stripComments(readFileSync(file, 'utf8'));
      findings.push(...findDuplicateMounts(extractExtensionRouteEntries(src), label));
    }

    expect([...ALLOWLIST].sort()).toEqual([...ALLOWLIST]); // sanity: list itself stays sorted
    expect(findings.sort()).toEqual([...ALLOWLIST].sort());

    // Private extensions: scanned, but never ratcheted — a finding here
    // can't live in a portable allowlist (see module doc comment).
    for (const file of privateRegisterFiles) {
      const label = file.slice(REPO_ROOT.length + 1);
      const src = stripComments(readFileSync(file, 'utf8'));
      const privateFindings = findDuplicateMounts(extractExtensionRouteEntries(src), label);
      if (privateFindings.length > 0) {
        // eslint-disable-next-line no-console
        console.warn(
          'duplicate-route-mount: a checked-out private extension has duplicate route mount(s) ' +
            '(not enforced here — fix in that extension):',
          privateFindings
        );
      }
    }
  });

  // Mutation test: proves entryComponentIdentifier's inline-wrapper fallback
  // actually fires, independent of what the real register.ts files contain.
  it('resolves an inline (non-redirect) wrapper to its first capitalised identifier, catching a duplicate mount through it', () => {
    const fixture = `
      featureRegistry.registerRoutes('system', [
        { path: '/system/foo', component: () => <ComputePage /> },
        { path: '/system/bar', component: () => <ComputePage /> },
      ]);
    `;
    expect(findDuplicateMounts(extractExtensionRouteEntries(fixture), 'Fixture/register.ts')).toEqual([
      'Fixture/register.ts: ComputePage -> /system/bar, /system/foo',
    ]);
  });
});

describe('nav convention: no reintroduced redirect route (fc-25 review item 2)', () => {
  it('the real route tables (DashboardPage.tsx + every public extension register.ts) contain no redirect routes', () => {
    const findings: string[] = [];

    const dashboardSrc = stripComments(
      readFileSync(join(FRONTEND_SRC, 'pages/app/DashboardPage.tsx'), 'utf8')
    );
    findings.push(...findRedirectRoutesInDashboardSrc(dashboardSrc, 'DashboardPage.tsx'));

    const registerFiles = discoverExtensionRegisterFiles();
    const publicRegisterFiles = registerFiles.filter((f) => !isPrivateExtensionFile(f));
    const privateRegisterFiles = registerFiles.filter(isPrivateExtensionFile);

    for (const file of publicRegisterFiles) {
      const label = file.slice(REPO_ROOT.length + 1);
      const src = stripComments(readFileSync(file, 'utf8'));
      findings.push(...findRedirectEntriesInExtensionSrc(src, label));
    }

    expect(findings.sort()).toEqual([]);

    for (const file of privateRegisterFiles) {
      const label = file.slice(REPO_ROOT.length + 1);
      const src = stripComments(readFileSync(file, 'utf8'));
      const privateFindings = findRedirectEntriesInExtensionSrc(src, label);
      if (privateFindings.length > 0) {
        // eslint-disable-next-line no-console
        console.warn(
          'duplicate-route-mount: a checked-out private extension has a redirect route ' +
            '(not enforced here — fix in that extension):',
          privateFindings
        );
      }
    }
  });

  // ── Mutation tests: fixture strings run through the same matchers ───────
  // Proves the matcher actually FIRES on each named shape, independent of
  // whatever the real tree currently contains.

  it('flags a single top-level <Route> that redirects via <Navigate>', () => {
    const fixture = `
      <Routes>
        <Route path="/" element={<DashboardOverview />} />
        <Route path="/system/overview" element={<Navigate to="/system" replace />} />
      </Routes>
    `;
    expect(findRedirectRoutesInDashboardSrc(fixture, 'Fixture.tsx')).toEqual([
      'Fixture.tsx: /system/overview -> redirect (Navigate/redirectTo)',
    ]);
  });

  it('flags a single register.ts entry whose component is redirectTo(...)', () => {
    const fixture = `
      featureRegistry.registerRoutes('system', [
        { path: '/system/nodes', component: redirectTo('/app/system/compute/nodes') },
        { path: '/system/compute/*', component: ComputePage },
      ]);
    `;
    expect(findRedirectEntriesInExtensionSrc(fixture, 'Fixture/register.ts')).toEqual([
      'Fixture/register.ts: /system/nodes -> redirect (Navigate/redirectTo)',
    ]);
  });

  it('flags a redirect route whose JSX is split across multiple lines', () => {
    const fixture = `
      <Routes>
        <Route
          path="/system/overview"
          element={
            <Navigate to="/system" replace />
          }
        />
      </Routes>
    `;
    expect(findRedirectRoutesInDashboardSrc(fixture, 'Fixture.tsx')).toEqual([
      'Fixture.tsx: /system/overview -> redirect (Navigate/redirectTo)',
    ]);
  });

  it('flags an inline wrapper (arrow function) that returns Navigate instead of calling redirectTo by name', () => {
    const fixture = `
      featureRegistry.registerRoutes('system', [
        { path: '/system/nodes', component: () => <Navigate to="/app/system/compute/nodes" replace /> },
      ]);
    `;
    expect(findRedirectEntriesInExtensionSrc(fixture, 'Fixture/register.ts')).toEqual([
      'Fixture/register.ts: /system/nodes -> redirect (Navigate/redirectTo)',
    ]);
  });

  it('does NOT flag an index-route tab default or a generic `*` fallback (fc-25 review item 8)', () => {
    const fixture = `
      <Routes>
        <Route index element={<Navigate to={fallback} replace />} />
        <Route path="overview" element={<CostOverview />} />
        <Route path="*" element={<Navigate to={fallback} replace />} />
      </Routes>
    `;
    expect(findRedirectRoutesInDashboardSrc(fixture, 'Fixture.tsx')).toEqual([]);
  });
});
