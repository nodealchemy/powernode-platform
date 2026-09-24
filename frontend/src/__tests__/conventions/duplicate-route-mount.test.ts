import { readFileSync, readdirSync } from 'fs';
import { join, sep } from 'path';

/**
 * Duplicate/alias-route mount guard (fc-25).
 *
 * fc-25 removed several routes that mounted the exact same page component at
 * two different top-level paths for no reason other than history — e.g.
 * `/app/content/kb/admin` and `/app/content/kb/manage` both rendered
 * `KnowledgeBaseAdminPage`, and `/system/overview` duplicated `/system`
 * (both `SystemOverviewPage`). This guard is the regression check: it scans
 * the two places top-level route tables are declared as static config —
 * `pages/app/DashboardPage.tsx`'s `<Routes>` and every checked-out
 * extension's `frontend/src/register.ts` `registerRoutes(...)` call — and
 * flags any component mounted at two or more distinct, NON-parameterised
 * paths within the same route list.
 *
 * Scope, deliberately narrow (matches what fc-25 actually touched):
 *  - Only DashboardPage.tsx's own <Routes> and each register.ts's
 *    registerRoutes array. A duplicate rendered by a nested <Routes> INSIDE
 *    a page component (e.g. the Cost hub's own "Overview" tab duplicating a
 *    FinOps sub-tab, or a tab list duplicating another tab) is invisible to
 *    a scan of these two files by construction — those were fixed by hand in
 *    fc-25 (CostPage/FinOpsPage, KnowledgeMemoryPage), not by this guard.
 *  - A path containing a `:param` segment is excluded from comparison
 *    entirely: a component legitimately reached via more than one
 *    parameterised path (or a mix of a parameterised and a static path) is
 *    not the "two identical static bookmarks" shape this guard targets.
 *  - A path ending in `/*` counts as ONE mount, like any other literal path
 *    — it is not expanded or treated specially, just compared as a string.
 *  - Comparisons are PER FILE (per route list), not across files: two
 *    different extensions coincidentally importing/registering a
 *    same-named component is not what this guard is for.
 *
 * EQUALITY RATCHET (mirrors nav-link-reachability.test.ts): the assertion is
 * `toEqual(ALLOWLIST)` against the full, unfiltered computed finding set
 * (sorted), not a count and not a filter-then-assert-empty. A new duplicate
 * mount not yet in ALLOWLIST fails; an ALLOWLIST entry that stops
 * reproducing (fixed, or the component/route renamed away) ALSO fails,
 * so nothing here can go stale silently.
 *
 * PRIVATE EXTENSIONS ARE SCANNED BUT NOT RATCHETED — same reasoning as
 * nav-link-reachability.test.ts: a private extension is remote-only and
 * absent from most checkouts, so a finding there can't live in a portable
 * allowlist. Findings are only reported via console.warn.
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
// brace-depth matching, then pulls `path:` and `component:` off each. The
// component may be a bare identifier (`ComputePage`) or a call expression
// (`redirectTo('/app/...')`, `withFooProviders(BarPage)`) — either way the
// leading identifier is what stands in for "what actually renders here",
// which is exactly the granularity this guard needs (two paths calling the
// same wrapper/factory are still "the same thing mounted twice").
function extractRouteEntries(body: string): RouteEntry[] {
  const entries: RouteEntry[] = [];
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
        const entry = body.slice(start, i + 1);
        const pathMatch = /path:\s*['"]([^'"]+)['"]/.exec(entry);
        const componentMatch = /component:\s*([A-Za-z_$][A-Za-z0-9_$]*)/.exec(entry);
        if (pathMatch && componentMatch) {
          entries.push({ path: pathMatch[1], component: componentMatch[1] });
        }
        start = -1;
      }
    }
  }
  return entries;
}

function extractExtensionRoutes(file: string): RouteEntry[] {
  const src = stripComments(readFileSync(file, 'utf8'));
  return extractRegisterRoutesBodies(src).flatMap(extractRouteEntries);
}

// DashboardPage.tsx declares every <Route> on a single line (established
// house style — every entry in the file already reads this way), so a
// per-line scan is enough: find the path, then take the LAST capitalised
// JSX tag opened on that line as the actually-rendered page (wrappers like
// `ProtectedRoute`/`ClusterProvider`/`HostProvider` always sit OUTSIDE the
// real page component in this codebase, so the innermost/last-opened tag is
// it).
function extractDashboardRoutes(): RouteEntry[] {
  const file = join(FRONTEND_SRC, 'pages/app/DashboardPage.tsx');
  const src = stripComments(readFileSync(file, 'utf8'));
  const routeLineRe = /<Route\s+path=["']([^"']+)["']/;
  const tagRe = /<([A-Z][A-Za-z0-9]*)/g;
  const entries: RouteEntry[] = [];
  for (const line of src.split('\n')) {
    const pathMatch = routeLineRe.exec(line);
    if (!pathMatch) continue;
    tagRe.lastIndex = 0;
    let lastTag: string | null = null;
    let tagMatch: RegExpExecArray | null;
    while ((tagMatch = tagRe.exec(line))) {
      if (tagMatch[1] === 'Route') continue;
      lastTag = tagMatch[1];
    }
    if (lastTag) entries.push({ path: pathMatch[1], component: lastTag });
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

// Named, itemized exceptions — NOT a count-based baseline (see module doc
// comment). Every entry below is the SAME pre-existing pattern: one hub/tab
// component mounted at several static per-tab paths (each independently
// permission-gated, or internally branching on the active path) plus, in
// most cases, a `/*` wildcard fallback for anything else. That is a
// deliberate navigation pattern already used throughout this codebase
// (SwarmHubPage, DockerHubPage, MissionsPageWrapper, AIAgentsPage) — not an
// accidental "two routes, one panel" duplicate like the ones fc-25 fixed.
// Consolidating any of these into a single `/*` route is a design decision
// for its own owning campaign, not fc-25's alias/redirect cleanup.
const ALLOWLIST: readonly string[] = [
  // AI ▸ Agents primary-nav tabs (cards/marketplace/community/autonomy) plus
  // the `/*` fallback — fc-13/fc-10 own this surface's tab consolidation.
  'DashboardPage.tsx: AIAgentsPage -> /ai/agents/*, /ai/agents/autonomy, /ai/agents/cards, /ai/agents/community, /ai/agents/marketplace',
  // Docker hub's static tab paths, each `ProtectedRoute`-gated on
  // devops.docker.read, plus the `/*` fallback.
  'DashboardPage.tsx: DockerHubPage -> /devops/docker/*, /devops/docker/containers, /devops/docker/images, /devops/docker/monitoring, /devops/docker/networks, /devops/docker/volumes',
  // AI ▸ Missions static tabs (all/completed) plus the code-factory and
  // bare-hub wildcards.
  'DashboardPage.tsx: MissionsPageWrapper -> /ai/missions, /ai/missions/all, /ai/missions/code-factory/*, /ai/missions/completed',
  // Swarm hub's static tab paths, each `ProtectedRoute`-gated on
  // devops.swarm.read, plus the `/*` fallback.
  'DashboardPage.tsx: SwarmHubPage -> /devops/swarm/*, /devops/swarm/networks, /devops/swarm/operations, /devops/swarm/secrets, /devops/swarm/services, /devops/swarm/stacks',
];

describe('nav convention: no component is mounted at two non-parameterised paths (fc-25)', () => {
  it('the duplicate-mount set exactly matches the named exception list (equality ratchet)', () => {
    const findings: string[] = [];

    findings.push(...findDuplicateMounts(extractDashboardRoutes(), 'DashboardPage.tsx'));

    const registerFiles = discoverExtensionRegisterFiles();
    const publicRegisterFiles = registerFiles.filter((f) => !isPrivateExtensionFile(f));
    const privateRegisterFiles = registerFiles.filter(isPrivateExtensionFile);

    for (const file of publicRegisterFiles) {
      const label = file.slice(REPO_ROOT.length + 1);
      findings.push(...findDuplicateMounts(extractExtensionRoutes(file), label));
    }

    expect([...ALLOWLIST].sort()).toEqual([...ALLOWLIST]); // sanity: list itself stays sorted
    expect(findings.sort()).toEqual([...ALLOWLIST].sort());

    // Private extensions: scanned, but never ratcheted — a finding here
    // can't live in a portable allowlist (see module doc comment).
    for (const file of privateRegisterFiles) {
      const label = file.slice(REPO_ROOT.length + 1);
      const privateFindings = findDuplicateMounts(extractExtensionRoutes(file), label);
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
});
