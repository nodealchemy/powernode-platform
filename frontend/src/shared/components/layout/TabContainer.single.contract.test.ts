import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs';
import path from 'node:path';
import { CORE_UI_API_VERSION, HOST_EXPOSED_IDS } from '@/shared/host-api/modules';

/**
 * One tab container (IMP-efa22f08cb32).
 *
 * `ui/TabContainer` was tagged @deprecated in favour of `layout/TabContainer`
 * while its caller count kept growing: a tag names a preference, it does not
 * stop an import. Under the no-legacy rule the deprecated one is deleted, not
 * kept as a re-export shim, so this guards the path itself:
 *
 *   - the file does not exist;
 *   - nothing in core or in a checked-out extension frontend names it — source,
 *     test, or `jest.mock` target (a mock of a deleted path passes while mocking
 *     nothing);
 *   - the host API exposes the survivor to extension bundles, and not the
 *     deleted id, whose re-export chunk would fail to build.
 */

const frontendRoot = path.resolve(__dirname, '../../../..');
const repoRoot = path.resolve(frontendRoot, '..');

// This file names the deleted path itself; the scan below skips it by filename.
const DELETED_SEGMENT = ['ui', 'TabContainer'].join('/');
const DELETED_ID = `@/shared/components/${DELETED_SEGMENT}`;
const SURVIVOR_ID = '@/shared/components/layout/TabContainer';

function findSources(dir: string, out: string[] = []): string[] {
  for (const entry of readdirSync(dir)) {
    if (entry === 'node_modules') continue;
    const full = path.join(dir, entry);
    if (statSync(full).isDirectory()) {
      findSources(full, out);
    } else if (/\.(ts|tsx)$/.test(entry)) {
      out.push(full);
    }
  }
  return out;
}

/** `extensions/<name>/frontend/src` and one level deeper for grouped extensions. */
function extensionSourceRoots(): string[] {
  const extRoot = path.join(repoRoot, 'extensions');
  if (!existsSync(extRoot)) return [];
  const roots: string[] = [];
  const visit = (dir: string, depth: number) => {
    for (const entry of readdirSync(dir)) {
      const full = path.join(dir, entry);
      if (!statSync(full).isDirectory()) continue;
      const src = path.join(full, 'frontend', 'src');
      if (existsSync(src)) roots.push(src);
      else if (depth < 1) visit(full, depth + 1);
    }
  };
  visit(extRoot, 0);
  return roots;
}

const coreSources = findSources(path.join(frontendRoot, 'src'));
const extensionSources = extensionSourceRoots().flatMap((root) => findSources(root));

describe('single TabContainer contract', () => {
  it('is scanning a real tree', () => {
    // Guards the guard: a path bug that empties the list would make the
    // reference scan below pass vacuously.
    expect(coreSources.length).toBeGreaterThan(1000);
    expect(coreSources).toContain(path.join(frontendRoot, 'src/shared/components/layout/TabContainer.tsx'));
    // A checked-out extension frontend whose tree reads as empty (a broken
    // symlink, a path bug) would hide its callers from the scan.
    if (extensionSourceRoots().length > 0) {
      expect(extensionSources.length).toBeGreaterThan(0);
    }
  });

  it('has deleted the deprecated ui/TabContainer', () => {
    expect(existsSync(path.join(frontendRoot, `src/shared/components/${DELETED_SEGMENT}.tsx`))).toBe(false);
  });

  it('has nothing naming the deleted path', () => {
    const offenders = [...coreSources, ...extensionSources]
      .filter((file) => file !== __filename)
      .filter((file) => readFileSync(file, 'utf8').includes(DELETED_SEGMENT))
      .map((file) => path.relative(repoRoot, file))
      .sort();

    expect(offenders).toEqual([]);
  });

  it('exposes the survivor to extension bundles and not the deleted id', () => {
    const exposed = HOST_EXPOSED_IDS as readonly string[];
    expect(exposed).toContain(SURVIVOR_ID);
    expect(exposed).not.toContain(DELETED_ID);
  });

  it('bumped the host UI API version for the removed id', () => {
    // Removing an exposed id breaks every bundle built against the old list.
    // The version gate makes the loader skip such a bundle instead of letting
    // its import of the removed id fail inside the running app.
    expect(CORE_UI_API_VERSION).toBeGreaterThanOrEqual(2);
  });
});
