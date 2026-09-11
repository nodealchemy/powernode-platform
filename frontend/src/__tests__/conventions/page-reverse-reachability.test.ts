import { readFileSync, readdirSync, statSync } from 'fs';
import { join, sep, basename } from 'path';

/**
 * Reverse reachability guard (C15b, campaign-followups.md 05:50 / review-lane4-c15.md
 * follow-up): C15 (nav-link-reachability.test.ts) checks the FORWARD direction — does
 * every `/app/...` link literal resolve to a registered route? This checks the
 * REVERSE — does every `*Page.tsx` (core + extension frontends) get routed,
 * registered, or imported by something that is? `ChatChannelsPage` and
 * `AIConversationsPage` were both exactly the failure mode this guards against:
 * fully built pages with zero route anywhere, caught only by an operator noticing
 * later, not by any test (fixed by `25e42d818`, see review-lane4-c15.md's addendum).
 *
 * DETECTION: a page's component identifier is its filename (`FooPage.tsx` ->
 * `FooPage`), the convention every page in this tree already follows (named export +
 * `export default` of the same identifier). A page is REACHABLE if that identifier
 * appears anywhere else in the scanned source (comments stripped first, same as C15,
 * so a stale doc reference or an example in a JSDoc comment can't satisfy this) —
 * as a JSX tag, an import, or a `component:` field in a featureRegistry call. This is
 * deliberately coarse (a plain identifier match, not a full import-graph trace),
 * matching C15's own literal-scan approach rather than a type-checker: a false
 * negative here is a red test a human triages, not a silent miss.
 *
 * EQUALITY RATCHET, BOTH DIRECTIONS (same shape as C15's ALLOWED_UNBUILT, F2): the
 * assertion is against the FULL, unfiltered computed-orphan set (sorted), not a
 * filtered subtraction. A newly orphaned page not yet in ALLOWED_ORPHANED fails; an
 * ALLOWED_ORPHANED entry that got wired up (or deleted) also fails, forcing pruning.
 *
 * PRIVATE EXTENSIONS ARE SCANNED BUT NOT RATCHETED (same rule as C15): a private
 * extension is remote-only and absent from public clones and most contributors'
 * checkouts, so hardcoding one of its orphan findings into ALLOWED_ORPHANED would
 * fail this test on every checkout that doesn't have it installed. Private-extension
 * pages ARE walked (satisfying the "core + extension frontends" requirement) but
 * their orphans are only surfaced via console.warn. This file never names a private
 * extension, its slug, or any path under extensions/private/.
 */

const FRONTEND_SRC = join(__dirname, '..', '..');
const REPO_ROOT = join(FRONTEND_SRC, '..', '..');
const EXTENSIONS_ROOT = join(REPO_ROOT, 'extensions');
const PRIVATE_EXTENSIONS_ROOT = join(EXTENSIONS_ROOT, 'private') + sep;

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

// Same crude string-vs-comment scanner as nav-link-reachability.test.ts (C15
// F6/F8) — never eats real code, reliably drops comment bodies so a stale doc
// comment or JSDoc example mentioning a page name can't satisfy this guard.
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

function discoverPageFiles(srcDirs: string[]): string[] {
  return srcDirs
    .flatMap((dir) => walkSourceFiles(dir))
    .filter((f) => /Page\.tsx$/.test(basename(f)));
}

// Named, itemized exceptions — NOT a count-based baseline. Each entry is a real,
// complete page component discovered while building this guard with no current
// route, registration, or importer anywhere in the tree. Wiring it in (or deleting
// it) is a product decision outside a reverse-reachability lint's scope; flagged to
// the lead at commit time. Re-add an entry only for a newly discovered orphan —
// never to make a red run green for one already fixed.
const ALLOWED_ORPHANED: readonly string[] = [
  // 611 lines, substantial. DashboardPage.tsx:156 routes /ai/agents/marketplace to
  // AIAgentsPage instead — possibly superseded (same shape as C15's F12: an old
  // page whose functionality moved into a tab of a newer one), possibly a real gap.
  'AgentMarketplacePage',
  // Small wrapper around a real DailySummariesPanel — no /app/content/... route
  // registers it anywhere.
  'DailySummariesPage',
  // A full admin file browser (permission-gated, upload + browse), distinct from
  // the routed content/MyFilesPage — no /app/admin/... route registers it.
  'FilesPage',
];

function findOrphans(pageFiles: string[], allFiles: string[]): string[] {
  // Pre-strip every candidate file once; reused for every page's identifier search.
  const strippedByFile = new Map<string, string>();
  for (const f of allFiles) {
    strippedByFile.set(f, stripComments(readFileSync(f, 'utf8')));
  }

  const orphans: string[] = [];
  for (const pageFile of pageFiles) {
    const identifier = basename(pageFile, '.tsx');
    const idRe = new RegExp(`\\b${identifier}\\b`);
    const reachable = allFiles.some((f) => {
      if (f === pageFile) return false; // the page's own file doesn't count
      return idRe.test(strippedByFile.get(f)!);
    });
    if (!reachable) orphans.push(identifier);
  }
  return orphans.sort();
}

describe('page reverse reachability: every *Page.tsx is routed, registered, or imported by a routed page (C15b)', () => {
  it('the orphaned page set (core + public extensions) exactly matches the named exception list (equality ratchet)', () => {
    const publicSrcDirs = [FRONTEND_SRC, ...discoverExtensionSrcDirs().filter((d) => !isPrivateExtensionSrcDir(d))];
    const publicFiles = publicSrcDirs.flatMap((dir) => walkSourceFiles(dir));
    const publicPageFiles = discoverPageFiles(publicSrcDirs);

    const computedOrphans = findOrphans(publicPageFiles, publicFiles);

    expect([...ALLOWED_ORPHANED].sort()).toEqual([...ALLOWED_ORPHANED]); // sanity: list itself stays sorted
    expect(computedOrphans).toEqual([...ALLOWED_ORPHANED].sort());
  });

  it('private extensions are scanned but not ratcheted (see module doc comment)', () => {
    const privateSrcDirs = discoverExtensionSrcDirs().filter(isPrivateExtensionSrcDir);
    if (privateSrcDirs.length === 0) return; // none checked out here — nothing to scan

    // Reachability for a private page may be satisfied by a PUBLIC file (core or a
    // public extension importing a private one is not a thing core purity allows,
    // but a private page can import/route another private page), so the search
    // space is public + private combined; only the CANDIDATE pages are private.
    const publicSrcDirs = [FRONTEND_SRC, ...discoverExtensionSrcDirs().filter((d) => !isPrivateExtensionSrcDir(d))];
    const allFiles = [...publicSrcDirs, ...privateSrcDirs].flatMap((dir) => walkSourceFiles(dir));
    const privatePageFiles = discoverPageFiles(privateSrcDirs);

    const privateOrphans = findOrphans(privatePageFiles, allFiles);
    if (privateOrphans.length > 0) {
      // eslint-disable-next-line no-console
      console.warn(
        'page-reverse-reachability: a checked-out private extension has orphaned page ' +
          'component(s) (not enforced here — fix in that extension):',
        privateOrphans
      );
    }
  });
});
