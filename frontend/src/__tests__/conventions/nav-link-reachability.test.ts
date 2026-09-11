import { readFileSync, readdirSync, statSync } from 'fs';
import { join } from 'path';

/**
 * Nav-href-to-route-table reachability guard (C15, review-lane4-c11.md F3).
 *
 * `DashboardPage.tsx`'s <Routes> has NO `path="*"` fallback, so an
 * `/app/...` link that does not match any registered route renders a blank
 * content pane, not a redirect and not a 404 page — the worst failure mode,
 * since nothing in the UI signals that anything went wrong. Nothing else in
 * the suite catches this: no test asserts that a breadcrumb, quick action,
 * or `navigate()` call target actually resolves.
 *
 * This guard extracts every `/app/...` string literal under `frontend/src`,
 * builds the route table from `App.tsx`'s own top-level routes plus
 * `DashboardPage.tsx`'s nested <Routes> plus every extension's
 * `register.ts`, and asserts every literal matches with real React Router
 * splat/param semantics (`:param` = one segment, a trailing `/*` matches its
 * own bare parent too, e.g. `/admin/settings/*` matches `/admin/settings`
 * with nothing after it — not just paths with a literal trailing slash).
 *
 * EQUALITY RATCHET, NOT A CARRIED BASELINE: the assertion is `toEqual([])`
 * against the full sorted list, not a count. A newly unreachable link fails
 * immediately by name; there is no threshold to creep past. ALLOWED_UNBUILT
 * below is not a baseline — it names live, itemized product gaps, each with
 * the reason it is not yet a route, discovered while landing this guard.
 * Shrink it as entries are resolved; never grow it silently.
 *
 * EMPTY, and meant to stay that way: its original four entries (three
 * KnowledgeBaseAdminPage actions plus KnowledgeBasePage's Analytics
 * shortcut) are resolved — Create Article now points at the real route
 * (/app/content/kb/articles/new, missing an "admin" segment was the actual
 * bug), and Manage Categories / Moderate Comments / Analytics were removed:
 * each had a backend endpoint in knowledgeBaseApi.ts but no frontend surface
 * anywhere consumed it, so there was nothing built to point the button at.
 * Re-add an entry only for a newly discovered, named, genuinely-unbuilt
 * destination — never to make a red run green.
 */

const FRONTEND_SRC = join(__dirname, '..', '..');
const REPO_ROOT = join(FRONTEND_SRC, '..', '..');
const EXTENSIONS_ROOT = join(REPO_ROOT, 'extensions');

// Discovered generically (whatever is checked out under extensions/* and
// extensions/private/*), never hardcoded by name — core must not reference a
// specific extension (public or private) by name (core-purity-check.sh).
// Mirrors how featureRegistry actually merges in whatever is installed: a
// deployment without a given extension just won't contribute its routes,
// same as this scan won't find its register.ts.
function discoverExtensionRegisterFiles(): string[] {
  const candidateDirs: string[] = [];
  try {
    for (const e of readdirSync(EXTENSIONS_ROOT, { withFileTypes: true })) {
      if (!e.isDirectory()) continue;
      if (e.name === 'private') {
        const privateRoot = join(EXTENSIONS_ROOT, 'private');
        try {
          for (const pe of readdirSync(privateRoot, { withFileTypes: true })) {
            if (pe.isDirectory()) candidateDirs.push(join(privateRoot, pe.name));
          }
        } catch {
          // extensions/private/ not present — fine, nothing private installed
        }
      } else {
        candidateDirs.push(join(EXTENSIONS_ROOT, e.name));
      }
    }
  } catch {
    return [];
  }
  const files: string[] = [];
  for (const dir of candidateDirs) {
    const candidate = join(dir, 'frontend/src/register.ts');
    try {
      statSync(candidate);
      files.push(candidate);
    } catch {
      // no frontend/register.ts for this checked-out extension — skip
    }
  }
  return files;
}

// Named, itemized exceptions — NOT a count-based baseline. Each entry is a
// real UI affordance (a button/link) whose destination genuinely does not
// exist yet anywhere in the tree (no route, no in-page tab), discovered
// while building this guard. Building the destination, or removing the
// affordance, is a product decision outside a nav-link lint's scope.
const ALLOWED_UNBUILT: readonly string[] = [];

function walkSourceFiles(dir: string, acc: string[] = []): string[] {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    if (entry.name === 'node_modules' || entry.name.startsWith('.')) continue;
    const full = join(dir, entry.name);
    if (entry.isDirectory()) {
      walkSourceFiles(full, acc);
    } else if (
      /\.(tsx|ts)$/.test(entry.name) &&
      !/\.(test|spec)\.(tsx|ts)$/.test(entry.name) &&
      !/\.d\.ts$/.test(entry.name)
    ) {
      acc.push(full);
    }
  }
  return acc;
}

function extractLinkLiterals(files: string[]): string[] {
  const literalRe = /['"`](\/app\/[a-zA-Z0-9\-_./:]*)['"`]/g;
  const found = new Set<string>();
  for (const file of files) {
    const text = readFileSync(file, 'utf8');
    let m: RegExpExecArray | null;
    while ((m = literalRe.exec(text))) {
      let p = m[1].split('?')[0].split('#')[0];
      if (p.length > 1 && p.endsWith('/')) p = p.slice(0, -1);
      found.add(p);
    }
  }
  return [...found];
}

function extractRouteTable(): string[] {
  const routes = new Set<string>(['/app']);

  // App.tsx's own top-level absolute /app/... routes, registered before the
  // /app/* catch-all that hands the rest of the tree to DashboardPage (e.g.
  // /app/oauth/authorize, /app/system/provision). Skip the literal "/app/*"
  // mount marker itself — it is not a destination, and treating it as one
  // would trivially match (and hide misses in) every /app/... literal.
  const appTsxSrc = readFileSync(join(FRONTEND_SRC, 'App.tsx'), 'utf8');
  const appRouteRe = /path=["'](\/app\/[^"']+)["']/g;
  let am: RegExpExecArray | null;
  while ((am = appRouteRe.exec(appTsxSrc))) {
    if (am[1] === '/app/*') continue;
    routes.add(am[1]);
  }

  // DashboardPage.tsx's nested <Routes>, relative to the /app/* mount.
  const dashboardSrc = readFileSync(join(FRONTEND_SRC, 'pages/app/DashboardPage.tsx'), 'utf8');
  const routeRe = /<Route\s+path=["']([^"']+)["']/g;
  let rm: RegExpExecArray | null;
  while ((rm = routeRe.exec(dashboardSrc))) {
    const rp = rm[1] === '/' ? '' : rm[1];
    routes.add('/app' + rp);
  }

  // Extension routes (register.ts { path: '/xxx', ... } entries — relative,
  // as registerRoutes takes them — AND registerSettingsTabs entries, which
  // are already full /app/... paths).
  for (const registerFile of discoverExtensionRegisterFiles()) {
    const src = readFileSync(registerFile, 'utf8');
    const extRouteRe = /\{\s*path:\s*['"]([^'"]+)['"]/g;
    let em: RegExpExecArray | null;
    while ((em = extRouteRe.exec(src))) {
      routes.add(em[1].startsWith('/app/') ? em[1] : '/app' + em[1]);
    }
  }

  return [...routes];
}

function routeToRegex(routePath: string): RegExp {
  const segments = routePath.split('/');
  if (segments[segments.length - 1] === '*') {
    // React Router splat semantics: a trailing "/*" ALSO matches the bare
    // parent with nothing after it (`/admin/settings/*` matches both
    // `/admin/settings` and `/admin/settings/anything`).
    const base = segments
      .slice(0, -1)
      .map((seg) => (seg.startsWith(':') ? '[^/]+' : seg.replace(/[.+?^${}()|[\]\\]/g, '\\$&')))
      .join('/');
    return new RegExp('^' + base + '(?:/.*)?$');
  }
  const escaped = segments
    .map((seg) => {
      if (seg === '*') return '.*';
      if (seg.startsWith(':')) return '[^/]+';
      return seg.replace(/[.+?^${}()|[\]\\]/g, '\\$&');
    })
    .join('/');
  return new RegExp('^' + escaped + '$');
}

describe('nav convention: every /app/... link literal resolves against the route table (C15)', () => {
  it('has zero unreachable link literals outside the named exception list', () => {
    const files = walkSourceFiles(FRONTEND_SRC);
    const linkLiterals = extractLinkLiterals(files);
    const routeTable = extractRouteTable().map((r) => ({ raw: r, re: routeToRegex(r) }));

    const isReachable = (link: string) => routeTable.some(({ re }) => re.test(link));

    const unreachable = linkLiterals
      .filter((p) => !isReachable(p))
      .filter((p) => !ALLOWED_UNBUILT.includes(p))
      .sort();

    expect(unreachable).toEqual([]);
  });

  it('the exception list itself is still unreachable and still sorted (catches a stale entry)', () => {
    const routeTable = extractRouteTable().map((r) => ({ raw: r, re: routeToRegex(r) }));
    const isReachable = (link: string) => routeTable.some(({ re }) => re.test(link));

    expect([...ALLOWED_UNBUILT].sort()).toEqual([...ALLOWED_UNBUILT]);
    for (const link of ALLOWED_UNBUILT) {
      expect(isReachable(link)).toBe(false);
    }
  });
});
