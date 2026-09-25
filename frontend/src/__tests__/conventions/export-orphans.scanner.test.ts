import { mkdtempSync, mkdirSync, writeFileSync, rmSync, symlinkSync } from 'fs';
import { tmpdir } from 'os';
import { join, dirname } from 'path';
import { scanExportOrphans, discoverExtensionRoots, loadAllowlist } from '@/test-utils/exportOrphanScanner';

// The scanner behind export-orphans.test.ts, on fixture trees: each case pins
// one rule of what does and does not make an export reachable.
describe('scanExportOrphans', () => {
  let repo: string;

  const write = (rel: string, body: string) => {
    const full = join(repo, rel);
    mkdirSync(dirname(full), { recursive: true });
    writeFileSync(full, body);
  };
  const scan = () =>
    scanExportOrphans([{ srcDir: join(repo, 'frontend/src'), frontendDir: join(repo, 'frontend') }], repo)
      .map((o) => `${o.path}#${o.name}:${o.kind}`);

  beforeEach(() => {
    repo = mkdtempSync(join(tmpdir(), 'export-orphans-'));
    write('frontend/src/App.tsx', "import { UsedPage } from './features/used';\nexport const App = () => UsedPage;\nApp();\n");
    write('frontend/src/features/used/index.ts', "export { UsedPage } from './UsedPage';\n");
    write('frontend/src/features/used/UsedPage.tsx', 'export const UsedPage = 1;\n');
  });

  afterEach(() => rmSync(repo, { recursive: true, force: true }));

  it('finds nothing in a tree whose every export is used', () => {
    expect(scan()).toEqual([]);
  });

  it('flags a page reachable only through its own barrel re-export', () => {
    write('frontend/src/features/gone/index.ts', "export { GonePage } from './GonePage';\n");
    write('frontend/src/features/gone/GonePage.tsx', 'export const GonePage = 1;\n');

    expect(scan()).toEqual(['frontend/src/features/gone/GonePage.tsx#GonePage:value']);
  });

  it('flags an export only a test uses', () => {
    write('frontend/src/lib/onlyTested.ts', 'export function onlyTested() { return 1; }\n');
    write('frontend/src/lib/onlyTested.test.ts', "import { onlyTested } from './onlyTested';\nonlyTested();\n");

    expect(scan()).toEqual(['frontend/src/lib/onlyTested.ts#onlyTested:value']);
  });

  it('flags an export mentioned only in a comment elsewhere', () => {
    write('frontend/src/lib/mentioned.ts', 'export const mentioned = 1;\n');
    write('frontend/src/lib/other.ts', '// mentioned is documented here\nexport const other = 2;\nother;\n');

    expect(scan()).toEqual(['frontend/src/lib/mentioned.ts#mentioned:value']);
  });

  it('flags an unused exported type as a type orphan', () => {
    write('frontend/src/lib/types.ts', 'export interface Unused { a: number }\n');

    expect(scan()).toEqual(['frontend/src/lib/types.ts#Unused:type']);
  });

  it('counts a default export whose module a lazy dynamic import loads', () => {
    write('frontend/src/pages/LazyPage.tsx', 'export default function LazyPage() { return null; }\n');
    write('frontend/src/routes.tsx', "const L = lazy(() => import('./pages/LazyPage'));\nexport const routes = [L];\nroutes;\n");

    expect(scan()).toEqual([]);
  });

  it('counts a use by a top-level frontend config file', () => {
    write('frontend/src/host/chunks.ts', 'export const chunkName = (id: string) => id;\n');
    write('frontend/vite.config.ts', "import { chunkName } from './src/host/chunks';\nchunkName('x');\n");

    expect(scan()).toEqual([]);
  });

  it('does not flag an export its own module uses', () => {
    write('frontend/src/lib/local.ts', 'export const LIMIT = 3;\nexport const other = () => LIMIT;\nother();\n');

    expect(scan()).toEqual([]);
  });

  it('never treats test-support files as candidates', () => {
    write('frontend/src/test-utils/helpers.ts', 'export const unusedHelper = 1;\n');
    write('frontend/src/features/x/__tests__/fixtures.ts', 'export const unusedFixture = 1;\n');

    expect(scan()).toEqual([]);
  });

  it("is not blinded by a JSX apostrophe opening a phantom string", () => {
    write('frontend/src/lib/target.ts', 'export const target = 1;\n');
    write(
      'frontend/src/Page.tsx',
      "export const Page = () => <p>Don't panic</p>;\nconst url = 'https://x';\nPage(); target;\n"
    );

    expect(scan()).toEqual([]);
  });

  // H1 (fc-48 review): an export statement is not a use. `export default X`
  // and `export { X }` name X a second time in its own file; counting that as
  // self-use hid every `const XPage = ...; export default XPage;` page.
  it('flags an exported const whose only other mention is its own export default', () => {
    write('frontend/src/pages/DeadPage.tsx', 'export const DeadPage = () => null;\nexport default DeadPage;\n');

    expect(scan()).toEqual(['frontend/src/pages/DeadPage.tsx#DeadPage:value']);
  });

  it('flags a non-exported const exported only as the default', () => {
    write('frontend/src/pages/QuietPage.tsx', 'const QuietPage = () => null;\nexport default QuietPage;\n');

    expect(scan()).toEqual(['frontend/src/pages/QuietPage.tsx#QuietPage:value']);
  });

  it('flags a symbol exported through a local export list at the bottom of its file', () => {
    write('frontend/src/lib/listed.ts', 'const listed = 1;\nconst aliased = 2;\nexport { listed, aliased as renamed };\n');

    expect(scan()).toEqual(['frontend/src/lib/listed.ts#listed:value', 'frontend/src/lib/listed.ts#renamed:value']);
  });

  it('flags a default export written without a semicolon', () => {
    write('frontend/src/pages/NoSemiPage.tsx', 'const NoSemiPage = () => null;\nexport default NoSemiPage\n');

    expect(scan()).toEqual(['frontend/src/pages/NoSemiPage.tsx#NoSemiPage:value']);
  });

  it('flags a symbol exported as the default through `export { X as default }`', () => {
    write('frontend/src/pages/AliasDefaultPage.tsx', 'const AliasDefaultPage = () => null;\nexport { AliasDefaultPage as default };\n');

    expect(scan()).toEqual(['frontend/src/pages/AliasDefaultPage.tsx#AliasDefaultPage:value']);
  });

  it('counts an `export { X as default }` page its module path is lazily imported by', () => {
    write('frontend/src/pages/AliasLivePage.tsx', 'const AliasLivePage = () => null;\nexport { AliasLivePage as default };\n');
    write('frontend/src/nav.tsx', "const P = lazy(() => import('./pages/AliasLivePage'));\nexport const nav = [P];\nnav;\n");

    expect(scan()).toEqual([]);
  });

  it('still counts a default-exported page its module path is lazily imported by', () => {
    write('frontend/src/pages/LivePage.tsx', 'const LivePage = () => null;\nexport default LivePage;\n');
    write('frontend/src/router.tsx', "const P = lazy(() => import('./pages/LivePage'));\nexport const router = [P];\nrouter;\n");

    expect(scan()).toEqual([]);
  });

  // H2: public exports are judged against the public tree only, so a checkout
  // without private extensions reaches the same verdict as one with them.
  it('judges a core export by public consumers only, identically with or without a private tree', () => {
    write('frontend/src/lib/forPrivate.ts', 'export const forPrivate = 1;\n');
    write('extensions/private/p1/frontend/src/usesIt.ts', "import { forPrivate } from '@/lib/forPrivate';\nexport const usesIt = forPrivate;\nusesIt;\n");
    const core = { srcDir: join(repo, 'frontend/src'), frontendDir: join(repo, 'frontend') };
    const priv = { srcDir: join(repo, 'extensions/private/p1/frontend/src'), frontendDir: join(repo, 'extensions/private/p1/frontend'), private: true };
    const fmt = (roots: Parameters<typeof scanExportOrphans>[0]) => scanExportOrphans(roots, repo).map((o) => `${o.path}#${o.name}`);

    const withPrivate = fmt([core, priv]);
    const withoutPrivate = fmt([core]);

    expect(withPrivate).toEqual(['frontend/src/lib/forPrivate.ts#forPrivate']);
    expect(withoutPrivate).toEqual(withPrivate);
  });

  it('judges a private export against every tree, public ones included', () => {
    write('extensions/private/p1/frontend/src/shared.ts', 'export const privShared = 1;\n');
    write('frontend/src/usesPriv.ts', 'export const usesPriv = privShared;\nusesPriv;\n');
    const core = { srcDir: join(repo, 'frontend/src'), frontendDir: join(repo, 'frontend') };
    const priv = { srcDir: join(repo, 'extensions/private/p1/frontend/src'), frontendDir: join(repo, 'extensions/private/p1/frontend'), private: true };

    expect(scanExportOrphans([core, priv], repo)).toEqual([]);
  });
});

describe('discoverExtensionRoots', () => {
  let repo: string;
  beforeEach(() => {
    repo = mkdtempSync(join(tmpdir(), 'export-orphans-ext-'));
  });
  afterEach(() => rmSync(repo, { recursive: true, force: true }));

  it('follows symlinked extension directories and marks private ones', () => {
    mkdirSync(join(repo, 'real/pub/frontend/src'), { recursive: true });
    mkdirSync(join(repo, 'real/sec/frontend/src'), { recursive: true });
    mkdirSync(join(repo, 'extensions/private'), { recursive: true });
    symlinkSync(join(repo, 'real/pub'), join(repo, 'extensions/pub'));
    symlinkSync(join(repo, 'real/sec'), join(repo, 'extensions/private/sec'));

    const found = discoverExtensionRoots(join(repo, 'extensions')).map((r) => `${r.repoRelRoot}:${r.private ? 'private' : 'public'}`);

    expect(found.sort()).toEqual(['extensions/private/sec:private', 'extensions/pub:public']);
  });
});

describe('loadAllowlist', () => {
  let dir: string;
  beforeEach(() => {
    dir = mkdtempSync(join(tmpdir(), 'export-orphans-allow-'));
    mkdirSync(join(dir, '__tests__/conventions'), { recursive: true });
  });
  afterEach(() => rmSync(dir, { recursive: true, force: true }));

  const allow = (entries: unknown) =>
    writeFileSync(join(dir, '__tests__/conventions/export-orphans.allowlist.json'), JSON.stringify(entries));

  it('rejects an entry outside its own tree', () => {
    allow([{ path: 'frontend/src/x.ts', name: 'x', reason: 'r' }]);

    expect(() => loadAllowlist(dir, 'extensions/ext', false)).toThrow(/outside its own tree: frontend\/src\/x\.ts/);
  });

  it('rejects an entry without a reason', () => {
    allow([{ path: 'extensions/ext/frontend/src/x.ts', name: 'x', reason: ' ' }]);

    expect(() => loadAllowlist(dir, 'extensions/ext', false)).toThrow(/needs path, name and a reason/);
  });

  it('accepts entries under its own tree', () => {
    allow([{ path: 'extensions/ext/frontend/src/x.ts', name: 'x', reason: 'r' }]);

    expect(loadAllowlist(dir, 'extensions/ext', false)).toHaveLength(1);
  });
});
