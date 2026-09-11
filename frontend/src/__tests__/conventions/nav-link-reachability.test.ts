import { readFileSync, readdirSync, statSync } from 'fs';
import { join, sep } from 'path';

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
 * This guard extracts every `/app/...` string literal under `frontend/src`
 * AND every checked-out extension's `frontend/src` (public + private —
 * review-lane4-c15.md F3: extension frontends were previously unscanned,
 * which hid 8 real unreachable literals across marketing, supply-chain,
 * system and a private extension), builds the route table from `App.tsx`'s
 * own top-level routes plus `DashboardPage.tsx`'s nested <Routes> plus every
 * extension's `register.ts` (registerRoutes + registerSettingsTabs; NOT
 * registerPublicRoutes — see extractRouteTable), and asserts every literal
 * matches with real React Router splat/param semantics (`:param` = one
 * segment, a trailing `/*` matches its own bare parent too, e.g.
 * `/admin/settings/*` matches `/admin/settings` with nothing after it — not
 * just paths with a literal trailing slash).
 *
 * Comments are stripped before extraction (review-lane4-c15.md F6/F8): a
 * JSDoc example or an explanatory comment mentioning a historical or
 * deliberately-broken path (e.g. SystemOverview.tsx's note that
 * `/app/system/puppet` "resolved nowhere at all") is not a live link and
 * must not be able to fail — or silently pass — this guard.
 *
 * EQUALITY RATCHET, NOT A CARRIED BASELINE (review-lane4-c15.md F2): the
 * single assertion below is `toEqual(ALLOWED_UNBUILT)` against the FULL,
 * UNFILTERED computed-unreachable set (sorted), not a count and not a
 * filter-then-assert-empty. This is a true equality oracle in both
 * directions: a newly unreachable literal that is not yet in
 * ALLOWED_UNBUILT makes the computed set grow past the list and fails; an
 * ALLOWED_UNBUILT entry that is now reachable (fixed) or has no live caller
 * left anywhere in the tree (stale — the exact gap the old two-test form
 * missed, since "still unreachable" stays true for an orphaned entry with no
 * caller at all) drops out of the computed set and ALSO fails, because the
 * two sorted arrays no longer match. Nothing can be silently added without
 * the run going red, and nothing can go stale without the run going red.
 *
 * EMPTY, and meant to stay that way: every literal discovered while landing
 * this guard and its F3 extension-scan followup was either fixed at its
 * source (a stale/renamed path corrected, a genuinely missing destination
 * built and routed) or was a comment/false-positive removed by stripping
 * comments before extraction. Re-add an entry only for a newly discovered,
 * named, genuinely-unbuilt destination — never to make a red run green.
 *
 * PRIVATE EXTENSIONS ARE SCANNED BUT NOT RATCHETED: a private extension is
 * remote-only and absent from public clones and most contributors' checkouts
 * (CLAUDE.md), so a finding from one is not portable — hardcoding it into
 * ALLOWED_UNBUILT would fail this test on every environment where that
 * extension is not checked out, since the literal would never be found
 * there either (empty computed set vs. a non-empty expected list). Whatever
 * private extensions happen to be present ARE walked, satisfying F3, but
 * their unreachable literals are only surfaced via console.warn, never
 * asserted. Fixing one is the extension's own responsibility; this file
 * never names a private extension, its slug, or any path under
 * extensions/private/.
 */

const FRONTEND_SRC = join(__dirname, '..', '..');
const REPO_ROOT = join(FRONTEND_SRC, '..', '..');
const EXTENSIONS_ROOT = join(REPO_ROOT, 'extensions');

// Discovered generically (whatever is checked out under extensions/* and
// extensions/private/*), never hardcoded by name — core must not reference a
// specific extension (public or private) by name (core-purity-check.sh).
// Mirrors how featureRegistry actually merges in whatever is installed: a
// deployment without a given extension just won't contribute its routes,
// same as this scan won't find its register.ts or its frontend/src.
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

// Path comparison only — never names a private extension (see the module
// doc comment on why private-extension findings can't live in
// ALLOWED_UNBUILT).
const PRIVATE_EXTENSIONS_ROOT = join(EXTENSIONS_ROOT, 'private') + sep;
function isPrivateExtensionSrcDir(dir: string): boolean {
  return (dir + sep).startsWith(PRIVATE_EXTENSIONS_ROOT);
}

// Named, itemized exceptions — NOT a count-based baseline. Each entry is a
// real UI affordance (a button/link) whose destination genuinely does not
// exist yet anywhere in the tree (no route, no in-page tab), discovered
// while building this guard. Building the destination, or removing the
// affordance, is a product decision outside a nav-link lint's scope.
//
// Found at HEAD in a clean worktree (837adf4f3's own green run was taken in
// the shared tree, where these two PUBLIC extensions carried other lanes'
// uncommitted edits that happened to change these literals — see
// lane4-resume-report.md). Public extensions ARE ratcheted (unlike private
// ones, above): they're present in any clone that includes them, so a finding
// here is portable. Each is owned and will get an offer filed to its owner;
// this repo must not commit into either extension's own submodule.
const ALLOWED_UNBUILT: readonly string[] = [
  // marketing extension: ConnectSocialModal.tsx's OAuth redirect_uri. No
  // register.ts entry and no page component handle /marketing/social/callback
  // — the social-connect OAuth flow has no landing page for the provider's
  // redirect to return to.
  '/app/marketing/social/callback',
  // supply-chain extension: ContainerImagesPage.tsx navigates here, and
  // ContainerImageDetailPage.tsx's breadcrumb links back here, but the
  // registered route is /app/supply-chain/containers (ContainerImagesPage /
  // ContainerImageDetailPage) -- "container-images" vs "containers" is a
  // stale rename, not a missing page. The second entry is the same template
  // literal's detail-page form (`.../container-images/${image.id}`); the
  // trailing char is the INTERP_PLACEHOLDER sentinel (U+0001) standing in
  // for ${image.id} -- inlined as \u0001 here rather than referenced, since
  // this array is initialized before INTERP_PLACEHOLDER further down.
  '/app/supply-chain/container-images',
  '/app/supply-chain/container-images/\u0001',
  // supply-chain extension: SupplyChainDashboardPage.tsx links here, but the
  // registered routes are /app/supply-chain/licenses/policies and
  // /app/supply-chain/licenses/violations (LicensePoliciesPage /
  // LicenseViolationsPage) — same stale-rename shape as container-images.
  '/app/supply-chain/license-policies',
  '/app/supply-chain/license-violations',
  // supply-chain extension: SupplyChainDashboardPage.tsx links here, but no
  // route or page anywhere registers a dedicated vulnerabilities destination
  // — vulnerability data today only surfaces inside container/SBOM detail
  // components (ContainerVulnerabilitiesTable, VulnerabilityDetailModal).
  // Genuinely missing, not a rename.
  '/app/supply-chain/vulnerabilities',
];

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

// Strips `//...` line comments and `/*...*/` block comments (JSDoc included)
// before literal extraction — review-lane4-c15.md F6/F8. A crude
// string-vs-comment scanner, not a full tokenizer: it tracks whether it is
// inside a single/double/template-literal string so a `//` or `/*` INSIDE a
// string (e.g. a URL literal containing "http://") is not mistaken for a
// comment start. It does not need to be a full parser — it only needs to
// never eat real code and to reliably drop comment bodies.
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
        // Preserve the escaped character too so quote-counting stays correct.
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

// One-segment placeholder substituted for a `${...}` template interpolation
// that lands INSIDE a path (not a query string) — e.g.
// `` `/app/content/kb/articles/${article.id}/edit` ``. `isReachable` treats
// it exactly like a route's `:param` segment (routeToRegex's `[^/]+`), so a
// literal built around a real dynamic id still resolves against the
// registered `:id`-shaped route instead of being reported unreachable
// merely because its id was not a compile-time constant.
const INTERP_PLACEHOLDER = '\u0001';

function extractLinkLiterals(files: string[]): string[] {
  // Manual scan, not a single regex — this is the review-lane4-c15.md F1
  // fix. The previous form required an immediate closing delimiter right
  // after a run of URL-ish characters, so a literal containing `${...}`
  // (template interpolation), `?` (a query string) or `#` (a hash) failed to
  // match AT ALL — proven by the OAuth mutant that deleted the real
  // `/app/oauth/authorize` route and stayed green, because its only caller
  // is `` `/app/oauth/authorize?${searchParams}` ``.
  //
  // A single character-class regex can recover a STATIC prefix before a
  // `${...}` (by simply not including `$`/`{` in the class), which is
  // enough when the interpolation is a query-string suffix. It is NOT
  // enough when the interpolation is a path SEGMENT — `.../articles/${id}`
  // — because chopping at `$` loses `/edit` if anything follows the
  // interpolation, and the trailing-slash-trimmed prefix no longer has the
  // right segment count to match a `:id`-shaped route at all. So this scans
  // char-by-char from each opening quote/backtick, skips balanced
  // `${...}` blocks by brace-depth counting and substitutes one
  // INTERP_PLACEHOLDER character (a single, non-`/` path segment) for each,
  // and keeps consuming the literal after the interpolation closes.
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
        if (c === quote) break; // clean close
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
        break; // any other character ends the literal's URL-ish run
      }
      let p = out.split('?')[0].split('#')[0];
      if (p.length > 1 && p.endsWith('/')) p = p.slice(0, -1);
      if (p !== '/app') found.add(p);
      // Resume scanning strictly after the consumed span so a `${...}`
      // block's own contents are never mistaken for a second opening quote.
      openQuoteRe.lastIndex = Math.max(i, om.index + 1);
    }
  }
  return [...found];
}

// Extracts the `[...]` array body of a single `featureRegistry.<callName>(
// '<slug>', [ ... ])` call, by brace/bracket-depth matching from the first
// `[` after the call name — not a single regex, because these arrays are
// multi-line, multi-property object literals and a naive `{...path:...}`
// regex only matches when `path` happens to be the FIRST property in the
// object (review-lane4-c15.md F6: this is exactly why registerSettingsTabs
// and registerNavItems entries, which list `id`/`label` first, were
// silently never captured despite a comment claiming they were).
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

function extractRouteTable(): string[] {
  const routes = new Set<string>(['/app']);

  // App.tsx's own top-level absolute /app/... routes, registered before the
  // /app/* catch-all that hands the rest of the tree to DashboardPage (e.g.
  // /app/oauth/authorize, /app/system/provision). Skip the literal "/app/*"
  // mount marker itself — it is not a destination, and treating it as one
  // would trivially match (and hide misses in) every /app/... literal.
  const appTsxSrc = stripComments(readFileSync(join(FRONTEND_SRC, 'App.tsx'), 'utf8'));
  const appRouteRe = /path=["'](\/app\/[^"']+)["']/g;
  let am: RegExpExecArray | null;
  while ((am = appRouteRe.exec(appTsxSrc))) {
    if (am[1] === '/app/*') continue;
    routes.add(am[1]);
  }

  // DashboardPage.tsx's nested <Routes>, relative to the /app/* mount.
  const dashboardSrc = stripComments(readFileSync(join(FRONTEND_SRC, 'pages/app/DashboardPage.tsx'), 'utf8'));
  const routeRe = /<Route\s+path=["']([^"']+)["']/g;
  let rm: RegExpExecArray | null;
  while ((rm = routeRe.exec(dashboardSrc))) {
    const rp = rm[1] === '/' ? '' : rm[1];
    routes.add('/app' + rp);
  }

  // Extension routes. Three distinct calls, three distinct path shapes
  // (review-lane4-c15.md F6/F7):
  //   - registerRoutes: relative paths (e.g. '/marketing/social'), rendered
  //     INSIDE DashboardPage's /app/* tree — prefix with /app.
  //   - registerSettingsTabs: already full /app/... paths (nested inside
  //     the core Admin Settings tabbed shell) — add as-is.
  //   - registerPublicRoutes: DELIBERATELY EXCLUDED. These are rendered by
  //     App.tsx at the root domain outside the authenticated /app/* tree
  //     entirely (e.g. marketing's '/features', '/blog') — they are not
  //     under /app at all, and the previous blanket `{\s*path:` regex
  //     wrongly treated every non-/app/-prefixed entry as if prepending
  //     '/app' made it a real destination, which would have falsely
  //     "resolved" an /app/... literal that only coincidentally shared a
  //     path segment with a public route.
  for (const registerFile of discoverExtensionRegisterFiles()) {
    const src = stripComments(readFileSync(registerFile, 'utf8'));
    const pathRe = /path:\s*['"]([^'"]+)['"]/g;

    for (const body of extractCallArrayBodies(src, 'registerRoutes')) {
      let em: RegExpExecArray | null;
      pathRe.lastIndex = 0;
      while ((em = pathRe.exec(body))) {
        routes.add(em[1].startsWith('/app/') ? em[1] : '/app' + em[1]);
      }
    }
    for (const body of extractCallArrayBodies(src, 'registerSettingsTabs')) {
      let em: RegExpExecArray | null;
      pathRe.lastIndex = 0;
      while ((em = pathRe.exec(body))) {
        routes.add(em[1]);
      }
    }
    // registerPublicRoutes intentionally not scanned — see comment above.
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
  it('the unreachable /app/... literal set exactly matches the named exception list (equality ratchet)', () => {
    // Core frontend + every checked-out PUBLIC extension's frontend —
    // review-lane4-c15.md F3. A deployment without a given extension
    // checked out just contributes nothing, same as
    // discoverExtensionRegisterFiles() above. Private extensions are
    // scanned separately below (see module doc comment).
    const extensionSrcDirs = discoverExtensionSrcDirs();
    const publicExtensionSrcDirs = extensionSrcDirs.filter((d) => !isPrivateExtensionSrcDir(d));
    const privateExtensionSrcDirs = extensionSrcDirs.filter(isPrivateExtensionSrcDir);

    const files = [FRONTEND_SRC, ...publicExtensionSrcDirs].flatMap((dir) => walkSourceFiles(dir));
    const linkLiterals = extractLinkLiterals(files);
    const routeTable = extractRouteTable().map((r) => ({ raw: r, re: routeToRegex(r) }));
    const isReachable = (link: string) => routeTable.some(({ re }) => re.test(link));

    // UNFILTERED: every currently-unreachable literal, not the ones left
    // over after subtracting ALLOWED_UNBUILT. Asserting this equals
    // ALLOWED_UNBUILT (sorted) is a true equality oracle in both directions
    // — see the module doc comment for why this replaces the previous
    // filter-then-assert-empty plus a separate self-consistency check.
    const computedUnreachable = linkLiterals.filter((p) => !isReachable(p)).sort();

    expect([...ALLOWED_UNBUILT].sort()).toEqual([...ALLOWED_UNBUILT]); // sanity: list itself stays sorted
    expect(computedUnreachable).toEqual([...ALLOWED_UNBUILT].sort());

    // Private extensions: walked (F3 requires it), but never ratcheted —
    // see the module doc comment for why a private-extension finding can't
    // live in ALLOWED_UNBUILT without breaking every checkout that doesn't
    // have it installed.
    const privateFiles = privateExtensionSrcDirs.flatMap((dir) => walkSourceFiles(dir));
    if (privateFiles.length > 0) {
      const privateUnreachable = extractLinkLiterals(privateFiles)
        .filter((p) => !isReachable(p))
        .sort();
      if (privateUnreachable.length > 0) {
        // eslint-disable-next-line no-console
        console.warn(
          'nav-link-reachability: a checked-out private extension has unreachable /app/... ' +
            'link literal(s) (not enforced here — fix in that extension):',
          privateUnreachable
        );
      }
    }
  });
});
