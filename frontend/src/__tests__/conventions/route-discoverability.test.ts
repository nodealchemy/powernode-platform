import { readFileSync, readdirSync, statSync, mkdtempSync, writeFileSync, rmSync } from 'fs';
import { join, sep } from 'path';
import { tmpdir } from 'os';

/**
 * Route discoverability guard (fc-26).
 *
 * nav-link-reachability.test.ts (C15) checks the FORWARD direction — does
 * every `/app/...` link literal resolve to a registered route? This checks
 * the REVERSE — does every registered LEAF route (not a `:param` route, not
 * a `/*` nested-router mount) get referenced by SOMETHING: a nav config
 * entry, a JSX link, or a `navigate('/app/...')` call literal? A route with
 * no such reference is reachable only by typing the URL — a hidden page
 * (fc-26: /app/privacy, /app/ai/debug, /app/ai/devops/templates, and others
 * were all exactly this shape).
 *
 * REUSES nav-link-reachability's route-table and link-literal extraction
 * almost verbatim (routeToRegex, extractRouteTable, extractLinkLiterals,
 * stripComments, the extension-discovery helpers) — duplicated here rather
 * than imported, matching this suite's existing convention of each guard
 * file being self-contained (see nav-link-reachability.test.ts and
 * page-reverse-reachability.test.ts, which duplicate the same helpers
 * against each other already). A nav config `href: '/app/...'` is a plain
 * quoted string starting with `/app/`, so the SAME link-literal scan that
 * satisfies C15 also satisfies "has a nav entry" here — no separate nav-config
 * parser is needed. Likewise `navigate('/app/...')` is just another quoted
 * `/app/...` literal, caught by the same regex regardless of what function
 * it's an argument to.
 *
 * SCOPE: a route is EXCLUDED from the requirement (not just satisfied
 * vacuously) when:
 *   - it contains a `:param` segment — reached via a runtime-computed id,
 *     not a static literal (per the task's own scoping instruction);
 *   - it ends in `/*` — a mount point for a nested router (e.g.
 *     `/app/ai/governance/*` mounts GovernancePage's own internal
 *     <TabContainer>), not a single navigable destination; its actual
 *     sub-destinations are checked as their own route-table entries where
 *     they register one (tabs, nested <Route>s), not this bare mount marker;
 *   - it is exactly `/app` (the shell root, trivially always reachable).
 *
 * EQUALITY RATCHET (same shape as C15's ALLOWED_UNBUILT / P10's
 * ALLOWED_STUBS): PUBLIC (core + public extensions) is checked against
 * ALLOWED_UNDISCOVERABLE, currently EMPTY — every hidden route found while
 * building this guard was linked or deleted at its source (fc-26), not
 * listed here. PRIVATE extensions FAIL outright on any finding (fc-05's
 * M6 precedent) — no allowlist, no warn; the scan stays generic, naming no
 * extension by identifier.
 */

const FRONTEND_SRC = join(__dirname, '..', '..');
const REPO_ROOT = join(FRONTEND_SRC, '..', '..');
const EXTENSIONS_ROOT = join(REPO_ROOT, 'extensions');

function discoverExtensionDirs(): string[] {
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
  return candidateDirs;
}

function discoverExtensionRegisterFiles(): string[] {
  const files: string[] = [];
  for (const dir of discoverExtensionDirs()) {
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

function discoverExtensionSrcDirs(): string[] {
  const dirs: string[] = [];
  for (const dir of discoverExtensionDirs()) {
    const candidate = join(dir, 'frontend/src');
    try {
      if (statSync(candidate).isDirectory()) dirs.push(candidate);
    } catch {
      // no frontend/src for this checked-out extension — skip
    }
  }
  return dirs;
}

const PRIVATE_EXTENSIONS_ROOT = join(EXTENSIONS_ROOT, 'private') + sep;
function isPrivateExtensionSrcDir(dir: string): boolean {
  return (dir + sep).startsWith(PRIVATE_EXTENSIONS_ROOT);
}

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
      while (i < n && !(src[i] === '*' && src[i + 1] === '/')) {
        if (src[i] === '\n') out += '\n';
        i += 1;
      }
      i += 2;
      continue;
    }
    out += c;
    i += 1;
  }
  return out;
}

const INTERP_PLACEHOLDER = '\u0001';

// Identical to nav-link-reachability.test.ts's extractLinkLiterals — see
// its comments there for why this is a manual char-by-char scan rather than
// a single regex (query strings, hashes, and `${...}` interpolation all
// break a naive approach).
function extractLinkLiterals(files: string[]): string[] {
  const found = new Set<string>();
  const openQuoteRe = /['"`](?=\/app\/)/g;
  for (const file of files) {
    const text = stripComments(readFileSync(file, 'utf8'));
    openQuoteRe.lastIndex = 0;
    let om: RegExpExecArray | null;
    while ((om = openQuoteRe.exec(text))) {
      const quote = text[om.index];
      let i = om.index + 1;
      let out = '';
      while (i < text.length) {
        const c = text[i];
        if (c === quote) break;
        if (c === '$' && text[i + 1] === '{') {
          let depth = 1;
          i += 2;
          while (i < text.length && depth > 0) {
            if (text[i] === '{') depth++;
            else if (text[i] === '}') depth--;
            i++;
          }
          out += INTERP_PLACEHOLDER;
          continue;
        }
        if (/[a-zA-Z0-9\-_./:?#=&]/.test(c)) {
          out += c;
          i += 1;
          continue;
        }
        break;
      }
      let p = out.split('?')[0].split('#')[0];
      if (p.length > 1 && p.endsWith('/')) p = p.slice(0, -1);
      if (p !== '/app') found.add(p);
      openQuoteRe.lastIndex = Math.max(i, om.index + 1);
    }
  }
  return [...found];
}

// TabContainer's basePath+tabs[].path convention (e.g. DockerHubPage.tsx,
// SwarmHubPage.tsx, AIAgentsPage.tsx): clicking a tab calls
// `navigate(\`${basePath}${tab.path}\`)` (shared/components/layout/
// TabContainer.tsx) — a route reached this way has no single `/app/...`
// string literal anywhere in source (it's built by concatenation), so the
// plain quoted-literal scan above can never see it, even though a user CAN
// click straight to it. Scoped per-file: a file's `path: '...'` entries
// only combine with a `basePath` resolved IN THAT SAME FILE, so an
// unrelated file's unrelated `path:` property (most of which are not
// TabContainer tabs at all) can never pair with the wrong base. This can
// only ADD discoverable routes on top of extractLinkLiterals's output —
// never remove one — so it cannot introduce a false pass for a route that
// truly has no path to it.
function extractTabContainerRoutes(files: string[]): string[] {
  const routes: string[] = [];
  const basePathRe = /basePath\s*=\s*(?:"([^"]+)"|'([^']+)'|\{\s*`([^`$]+)`\s*\}|\{\s*([A-Z][A-Z0-9_]*)\s*\})/g;
  const pathRe = /\bpath:\s*(?:"([^"]*)"|'([^']*)')/g;

  for (const file of files) {
    const src = stripComments(readFileSync(file, 'utf8'));
    const bases = new Set<string>();
    let bm: RegExpExecArray | null;
    basePathRe.lastIndex = 0;
    while ((bm = basePathRe.exec(src))) {
      const [, dq, sq, tpl, constName] = bm;
      let value = dq ?? sq ?? tpl;
      if (!value && constName) {
        const cm = src.match(
          new RegExp(`const\\s+${constName}\\s*(?::[^=]+)?=\\s*(?:"([^"]+)"|'([^']+)'|\`([^\`$]+)\`)`)
        );
        if (cm) value = cm[1] ?? cm[2] ?? cm[3];
      }
      if (value && value.startsWith('/app/')) bases.add(value);
    }
    if (bases.size === 0) continue;

    const tabPaths = new Set<string>();
    let pm: RegExpExecArray | null;
    pathRe.lastIndex = 0;
    while ((pm = pathRe.exec(src))) {
      tabPaths.add(pm[1] ?? pm[2] ?? '');
    }
    for (const base of bases) {
      for (const p of tabPaths) {
        routes.push(p === '' || p === '/' ? base : base + p);
      }
    }
  }
  return routes;
}

function extractCallArrayBodies(src: string, callName: string): string[] {
  const bodies: string[] = [];
  const callRe = new RegExp(`featureRegistry\\.${callName}\\s*\\(`, 'g');
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

// Routes contributed by one register.ts (registerRoutes + registerSettingsTabs
// — NOT registerPublicRoutes, same exclusion as nav-link-reachability.test.ts:
// those mount outside the authenticated /app/* tree entirely).
function extractRoutesFromRegisterFile(registerFile: string): string[] {
  const routes: string[] = [];
  const src = stripComments(readFileSync(registerFile, 'utf8'));
  const pathRe = /path:\s*['"]([^'"]+)['"]/g;
  for (const body of extractCallArrayBodies(src, 'registerRoutes')) {
    let em: RegExpExecArray | null;
    pathRe.lastIndex = 0;
    while ((em = pathRe.exec(body))) {
      routes.push(em[1].startsWith('/app/') ? em[1] : '/app' + em[1]);
    }
  }
  for (const body of extractCallArrayBodies(src, 'registerSettingsTabs')) {
    let em: RegExpExecArray | null;
    pathRe.lastIndex = 0;
    while ((em = pathRe.exec(body))) {
      routes.push(em[1]);
    }
  }
  return routes;
}

// Core's own routes (App.tsx's top-level /app/... routes + DashboardPage's
// nested <Routes>), PLUS whichever register files are passed in — kept as a
// PARAMETER (unlike nav-link-reachability.test.ts's single merged table)
// specifically so the public ratchet below can build a table from ONLY
// core + public register files, and the private check can build one from
// ONLY private register files, without either leaking into the other's
// requirement set. Merging all of them into one Set (as C15 does, since it
// only needs a target set for FORWARD matching) would silently fold a
// private extension's routes into "public required" here, which is the
// wrong scope for this guard's separately-ratcheted public/private halves.
function extractRouteTable(registerFiles: string[]): string[] {
  const routes = new Set<string>(['/app']);

  const appTsxSrc = stripComments(readFileSync(join(FRONTEND_SRC, 'App.tsx'), 'utf8'));
  const appRouteRe = /path=["'](\/app\/[^"']+)["']/g;
  let am: RegExpExecArray | null;
  while ((am = appRouteRe.exec(appTsxSrc))) {
    if (am[1] === '/app/*') continue;
    routes.add(am[1]);
  }

  const dashboardSrc = stripComments(readFileSync(join(FRONTEND_SRC, 'pages/app/DashboardPage.tsx'), 'utf8'));
  const routeRe = /<Route\s+path=["']([^"']+)["']/g;
  let rm: RegExpExecArray | null;
  while ((rm = routeRe.exec(dashboardSrc))) {
    const rp = rm[1] === '/' ? '' : rm[1];
    routes.add('/app' + rp);
  }

  for (const registerFile of registerFiles) {
    for (const route of extractRoutesFromRegisterFile(registerFile)) routes.add(route);
  }

  return [...routes];
}

function routeToRegex(routePath: string): RegExp {
  const segments = routePath.split('/');
  if (segments[segments.length - 1] === '*') {
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

// Excludes :param routes, /* nested-router mounts, and the bare shell root —
// see the module doc comment for why each is out of scope here.
function requiresDiscoverability(route: string): boolean {
  if (route === '/app') return false;
  if (route.includes(':')) return false;
  if (route.endsWith('/*')) return false;
  return true;
}

// Named, itemized exceptions — NOT a count-based baseline, and currently
// EMPTY (fc-26: every hidden route found while building this guard was
// linked from somewhere discoverable, or deleted, at its source — none
// listed here). Add an entry only for a new, genuinely-undiscoverable route
// that is a deliberate, reviewed exception — never to make a red run green
// in bulk.
const ALLOWED_UNDISCOVERABLE: readonly string[] = [];

describe('convention: every non-param, non-wildcard route is discoverable (fc-26)', () => {
  it('core + public extensions: every required route has a nav entry or an in-app link literal', () => {
    const extensionSrcDirs = discoverExtensionSrcDirs();
    const publicExtensionSrcDirs = extensionSrcDirs.filter((d) => !isPrivateExtensionSrcDir(d));
    const publicRegisterFiles = discoverExtensionRegisterFiles().filter(
      (f) => !(f + sep).startsWith(PRIVATE_EXTENSIONS_ROOT)
    );

    const files = [FRONTEND_SRC, ...publicExtensionSrcDirs].flatMap((dir) => walkSourceFiles(dir));
    const linkLiterals = [...extractLinkLiterals(files), ...extractTabContainerRoutes(files)];
    const isDiscoverable = (route: string) => linkLiterals.some((lit) => routeToRegex(route).test(lit));

    const routeTable = extractRouteTable(publicRegisterFiles);
    const computedUndiscoverable = routeTable
      .filter(requiresDiscoverability)
      .filter((route) => !isDiscoverable(route))
      .sort();

    expect([...ALLOWED_UNDISCOVERABLE].sort()).toEqual([...ALLOWED_UNDISCOVERABLE]); // sanity: stays sorted
    expect(computedUndiscoverable).toEqual([...ALLOWED_UNDISCOVERABLE].sort());
  });

  it('private extensions: every checked-out extension\'s required route FAILS if undiscoverable (no allowlist)', () => {
    const extensionSrcDirs = discoverExtensionSrcDirs();
    const privateExtensionSrcDirs = extensionSrcDirs.filter(isPrivateExtensionSrcDir);
    if (privateExtensionSrcDirs.length === 0) return; // nothing checked out — vacuously fine

    // Literals can come from ANYWHERE (core, public, or private extensions) —
    // a private extension's route can legitimately be linked from its own
    // register.ts nav entries, which live in the same src tree being walked.
    const allSrcDirs = [FRONTEND_SRC, ...extensionSrcDirs];
    const allFiles = allSrcDirs.flatMap((dir) => walkSourceFiles(dir));
    const linkLiterals = [...extractLinkLiterals(allFiles), ...extractTabContainerRoutes(allFiles)];
    const isDiscoverable = (route: string) => linkLiterals.some((lit) => routeToRegex(route).test(lit));

    const privateRegisterFiles = discoverExtensionRegisterFiles().filter((f) =>
      (f + sep).startsWith(PRIVATE_EXTENSIONS_ROOT)
    );
    const privateRoutes = privateRegisterFiles.flatMap(extractRoutesFromRegisterFile);
    const undiscoverable = [...new Set(privateRoutes)]
      .filter(requiresDiscoverability)
      .filter((route) => !isDiscoverable(route))
      .sort();

    expect(undiscoverable).toEqual([]);
  });
});

describe('route-discoverability matcher (unit)', () => {
  describe('requiresDiscoverability', () => {
    it('excludes a :param route', () => {
      expect(requiresDiscoverability('/app/ai/agents/:agentId')).toBe(false);
    });

    it('excludes a /* nested-router mount', () => {
      expect(requiresDiscoverability('/app/ai/governance/*')).toBe(false);
    });

    it('excludes the bare shell root', () => {
      expect(requiresDiscoverability('/app')).toBe(false);
    });

    it('requires a plain leaf route', () => {
      expect(requiresDiscoverability('/app/ai/debug')).toBe(true);
    });

    it('requires a route with a static multi-segment path', () => {
      expect(requiresDiscoverability('/app/ai/infrastructure/providers/new')).toBe(true);
    });
  });

  describe('isDiscoverable (via routeToRegex, same as C15)', () => {
    const isDiscoverable = (route: string, literals: string[]) =>
      literals.some((lit) => routeToRegex(route).test(lit));

    it('a route is discoverable when a nav href literal matches it exactly', () => {
      expect(isDiscoverable('/app/privacy', ["href: '/app/privacy'"])).toBe(false); // literal must be JUST the path
      expect(isDiscoverable('/app/privacy', ['/app/privacy'])).toBe(true);
    });

    it('extractLinkLiterals captures a navigate() call argument like any other quoted /app/... literal', () => {
      const tmpDir = mkdtempSync(join(tmpdir(), 'route-discoverability-'));
      const tmpFile = join(tmpDir, 'fixture.tsx');
      try {
        writeFileSync(tmpFile, "const goToDebug = () => navigate('/app/ai/debug');\n");
        expect(extractLinkLiterals([tmpFile])).toEqual(['/app/ai/debug']);
      } finally {
        rmSync(tmpDir, { recursive: true, force: true });
      }
    });

    it('a route is NOT discoverable when only an unrelated literal exists', () => {
      expect(isDiscoverable('/app/privacy', ['/app/profile'])).toBe(false);
    });

    // fc-26 mutation: an edit that adds an UNRELATED literal elsewhere must
    // not change whether an already-undiscoverable route stays flagged.
    it('mutation: an unrelated literal added elsewhere does not make an undiscoverable route discoverable', () => {
      const before = isDiscoverable('/app/ai/debug', ['/app/profile']);
      const after = isDiscoverable('/app/ai/debug', ['/app/profile', '/app/devops']);
      expect(after).toBe(before);
      expect(after).toBe(false);
    });

    // fc-26 mutation: adding the ACTUAL matching literal flips the result —
    // proving the check is sensitive to the one edit that matters.
    it('mutation: adding the actual link literal flips an undiscoverable route to discoverable', () => {
      const before = isDiscoverable('/app/ai/debug', ['/app/profile']);
      const after = isDiscoverable('/app/ai/debug', ['/app/profile', '/app/ai/debug']);
      expect(before).toBe(false);
      expect(after).toBe(true);
    });
  });
});
