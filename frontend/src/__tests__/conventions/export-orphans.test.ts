import { join } from 'path';
import { discoverExtensionRoots, loadAllowlist, scanExportOrphans, type Orphan, type AllowlistEntry } from '@/test-utils/exportOrphanScanner';

/**
 * Export orphan ratchet (P1/P7, fc-48). Supersedes page-reverse-reachability:
 * a page is one kind of export, and a page reachable only through its own
 * barrel is exactly the orphan that guard could not see. What counts as an
 * orphan is defined in test-utils/exportOrphanScanner.ts.
 *
 * EQUALITY RATCHET, BOTH DIRECTIONS: the scan's full orphan set must equal the
 * merged allowlists exactly. A NEW orphan fails; so does an allowlisted entry
 * that is no longer an orphan (used again, or deleted) — the fix that ends an
 * orphan must remove its entry in the same diff, so the lists only shrink.
 * Target: empty.
 *
 * EXTENSIONS CONTRIBUTE THEIR OWN ALLOWLIST; CORE NAMES NONE OF THEM. Every
 * checked-out extension frontend (extensions/<x>, extensions/private/<x>) is
 * discovered by directory walk and scanned; its orphans are excused only by
 * the allowlist inside its own tree, whose entries may only name paths under
 * that tree.
 *
 * A PUBLIC CLONE AGREES WITH ITSELF: core and public-extension exports are
 * judged against public consumers only, so their verdict does not depend on
 * which private extensions are checked out. A core export that only a private
 * extension consumes is therefore a core orphan everywhere, allowlisted as
 * "consumed only outside the public tree". Private trees are scanned only
 * where present, and judged against everything.
 *
 * Each entry names a path, a symbol and a reason. "pending deletion
 * (operator-confirm)" marks an orphan whose deletion is awaiting the
 * operator's bulk-delete confirmation.
 */

const FRONTEND_SRC = join(__dirname, '..', '..');
const FRONTEND_DIR = join(FRONTEND_SRC, '..');
const REPO_ROOT = join(FRONTEND_DIR, '..');

const key = (e: { path: string; name: string }) => `${e.path}#${e.name}`;

describe('export orphans: every export is used by production code, or allowlisted with a reason (P1/P7)', () => {
  const extensions = discoverExtensionRoots(join(REPO_ROOT, 'extensions'));
  const roots = [{ srcDir: FRONTEND_SRC, frontendDir: FRONTEND_DIR }, ...extensions];

  let orphans: Orphan[];
  let allowed: AllowlistEntry[];

  beforeAll(() => {
    orphans = scanExportOrphans(roots, REPO_ROOT);
    allowed = [
      ...loadAllowlist(FRONTEND_SRC, 'frontend', true),
      ...extensions.flatMap((ext) => loadAllowlist(ext.srcDir, ext.repoRelRoot, false)),
    ];
  });

  it('allowlists no symbol twice', () => {
    const keys = allowed.map(key);
    expect(keys.filter((k, i) => keys.indexOf(k) !== i)).toEqual([]);
  });

  it('the orphan set exactly matches the allowlists (equality ratchet)', () => {
    const found = new Set(orphans.map(key));
    const listed = new Set(allowed.map(key));
    const newOrphans = [...found].filter((k) => !listed.has(k)).sort();
    const staleEntries = [...listed].filter((k) => !found.has(k)).sort();

    expect({ newOrphans, staleEntries }).toEqual({ newOrphans: [], staleEntries: [] });
  });
});
