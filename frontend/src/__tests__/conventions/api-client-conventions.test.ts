import { existsSync, readFileSync, readdirSync, statSync } from 'fs';
import { join, relative, sep } from 'path';
import coreAllowlist from './api-client-conventions.allowlist.json';

/**
 * fc-39 guard: one client per endpoint family, unique client export names,
 * and no raw HTTP client in extension components.
 *
 * 1. ONE CLIENT FILE PER 2-SEGMENT ENDPOINT FAMILY. An endpoint family is the
 *    first two path segments a client calls (`/ai/learning`, `/system/fleet`,
 *    `/files`). When two files call the same family, each grows its own
 *    unwrapping and its own copy of the types, and they drift (fc-39 folded
 *    evaluationApi + compoundLearningApi + two inline component calls into
 *    one learningApi for exactly this reason). A "client file" is any
 *    non-test source file that imports the HTTP client
 *    (`@/shared/services/api`/`apiClient`) or extends BaseApiService; its
 *    families are read from the first argument of each get/post/put/patch/
 *    delete/getList/request call, with same-file string constants
 *    (`const BASE = '/ai/x'`, `basePath = '/ai/x'`, `const url = \`/x/${id}\``,
 *    `const base = (id) => \`/x/${id}\``) substituted in.
 *
 * 2. UNIQUE `*Api` / `*ApiService` EXPORT NAMES across core and every
 *    public extension (a private extension's clash is only warned about).
 *    Three `providersApi`s meant an import picked whichever one its path
 *    pointed at and a reader could not tell which
 *    (fc-39 renamed them gitProvidersApi / fleetProvidersApi). No allowlist:
 *    the set of duplicates must stay empty.
 *
 * 3. NO RAW HTTP CLIENT IN EXTENSION COMPONENTS. Core's `.tsx` files are held
 *    to this by ESLint (eslint.config.mjs, no-restricted-imports); extension
 *    sources sit outside core's lint base path, so this test holds them to it.
 *
 * EQUALITY RATCHET. The existing duplicates are listed, and the listed set must
 * EQUAL the observed set: a new duplicate fails, and so does a fixed one that
 * is still listed. The lists can only shrink.
 *
 * WHO LISTS WHAT. Core must not name an extension (core-purity-check.sh), so
 * extensions are discovered with a directory walk and each contributes its own
 * `frontend/api-client-conventions.allowlist.json`. Core's list holds
 * core-only families. A family that an extension shares with core is listed by
 * the extension, which names its own files by extension-relative path and
 * core's by `core:<repo path>`. A family shared by two extensions cannot be
 * listed at all (either list would have to name the other extension): fix it.
 *
 * PRIVATE EXTENSIONS are walked but only warned about, as in
 * no-double-api-v1-prefix.test.ts: they are absent from public clones, so
 * nothing about them can be ratcheted from here.
 */

const FRONTEND_SRC = join(__dirname, '..', '..');
const REPO_ROOT = join(FRONTEND_SRC, '..', '..');
const EXTENSIONS_ROOT = join(REPO_ROOT, 'extensions');
const EXTENSION_ALLOWLIST = 'api-client-conventions.allowlist.json';

interface ExtensionRoot {
  /** Repo-relative extension directory, discovered at runtime. */
  rel: string;
  dir: string;
  isPrivate: boolean;
}

interface ExtensionAllowlist {
  families?: Record<string, string[]>;
  tsxDirectImports?: string[];
}

function discoverExtensions(): ExtensionRoot[] {
  const found: ExtensionRoot[] = [];
  const push = (dir: string, isPrivate: boolean) => {
    try {
      if (statSync(join(dir, 'frontend', 'src')).isDirectory()) {
        found.push({ rel: relative(REPO_ROOT, dir).split(sep).join('/'), dir, isPrivate });
      }
    } catch {
      // no frontend/src for this checked-out extension
    }
  };
  let entries: import('fs').Dirent[] = [];
  try {
    entries = readdirSync(EXTENSIONS_ROOT, { withFileTypes: true });
  } catch {
    return found;
  }
  for (const e of entries) {
    if (!e.isDirectory()) continue;
    if (e.name === 'private') {
      try {
        for (const pe of readdirSync(join(EXTENSIONS_ROOT, 'private'), { withFileTypes: true })) {
          if (pe.isDirectory()) push(join(EXTENSIONS_ROOT, 'private', pe.name), true);
        }
      } catch {
        // no private extensions installed
      }
    } else {
      push(join(EXTENSIONS_ROOT, e.name), false);
    }
  }
  return found;
}

function walkSourceFiles(dir: string, acc: string[] = []): string[] {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    if (entry.name === 'node_modules' || entry.name.startsWith('.')) continue;
    if (entry.name === '__tests__' || entry.name === '__mocks__' || entry.name === 'tests') continue;
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

// Strips line and block comments, string-aware (copied from
// no-double-api-v1-prefix.test.ts), so an endpoint named in a JSDoc header is
// not read as a call.
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

const HTTP_CLIENT_IMPORT =
  /from\s+['"](?:@\/shared\/services\/(?:api|apiClient)|(?:\.\.\/)+(?:shared\/)?services\/(?:api|apiClient))['"]|extends\s+BaseApiService\b/;

// `const X = '/a/b'`, `private basePath = '/a'`, `const url = \`/a/${id}\``,
// `const base = (id: string) => \`/a/${id}\`` — the leading literal path.
const PATH_CONSTANT =
  // eslint-disable-next-line security/detect-unsafe-regex -- runs over repo source in a test, never user input
  /(?:const|let|readonly|private|protected|public|static)\s+(?:readonly\s+)?([A-Za-z_$][\w$]*)\s*(?::\s*string\s*)?=\s*(?:\([^()]*\)\s*(?::\s*string\s*)?=>\s*)?(['"`])(\/[^'"`\s$]*)/g;

// First argument of an HTTP verb call: a literal path, or a same-file constant.
const HTTP_CALL =
  // eslint-disable-next-line security/detect-unsafe-regex -- runs over repo source in a test, never user input
  /\b(?:get|post|put|patch|delete|getList|request)\s*(?:<[\s\S]*?>)?\s*\(\s*(?:(['"`])(\/[^'"`]*)|((?:this\.)?[A-Za-z_$][\w$]*)\s*[,)(])/g;

function familyOf(path: string): string | null {
  const segments = path.split('${')[0].split('?')[0].split('/').filter(Boolean);
  if (segments.length === 0 || segments[0] === 'app') return null;
  return '/' + segments.slice(0, 2).join('/');
}

function familiesCalledBy(file: string): Set<string> {
  const raw = readFileSync(file, 'utf8');
  const families = new Set<string>();
  if (!HTTP_CLIENT_IMPORT.test(raw)) return families;

  let text = stripComments(raw);
  const constants: Record<string, string> = {};
  for (const m of text.matchAll(PATH_CONSTANT)) constants[m[1]] = m[3];
  text = text.replace(
    // eslint-disable-next-line security/detect-unsafe-regex -- runs over repo source in a test, never user input
    /\$\{\s*(?:this\.)?([A-Za-z_$][\w$]*)\s*(?:\([^()]*\))?\s*\}/g,
    (whole, name: string) => constants[name] ?? whole
  );

  for (const m of text.matchAll(HTTP_CALL)) {
    const path = m[2] ?? constants[(m[3] ?? '').replace(/^this\./, '')];
    if (!path) continue;
    const family = familyOf(path);
    if (family) families.add(family);
  }
  return families;
}

// ---------------------------------------------------------------------------

const extensions = discoverExtensions();
const publicExtensions = extensions.filter((e) => !e.isPrivate);
const privateExtensions = extensions.filter((e) => e.isPrivate);

const coreFiles = walkSourceFiles(FRONTEND_SRC);
const filesOf = (ext: ExtensionRoot) => walkSourceFiles(join(ext.dir, 'frontend', 'src'));

/** `core:<repo path>` for core files, `<extension rel>:<extension path>` otherwise. */
function fileId(file: string, owner: ExtensionRoot | null): string {
  if (!owner) return `core:${relative(REPO_ROOT, file).split(sep).join('/')}`;
  return `${owner.rel}:${relative(owner.dir, file).split(sep).join('/')}`;
}

function readExtensionAllowlist(ext: ExtensionRoot): ExtensionAllowlist {
  const file = join(ext.dir, 'frontend', EXTENSION_ALLOWLIST);
  if (!existsSync(file)) return {};
  return JSON.parse(readFileSync(file, 'utf8')) as ExtensionAllowlist;
}

function familyIndex(owners: Array<{ owner: ExtensionRoot | null; files: string[] }>): Map<string, string[]> {
  const index = new Map<string, string[]>();
  for (const { owner, files } of owners) {
    for (const file of files) {
      for (const family of familiesCalledBy(file)) {
        const ids = index.get(family) ?? [];
        ids.push(fileId(file, owner));
        index.set(family, ids);
      }
    }
  }
  return index;
}

function duplicates(index: Map<string, string[]>): Record<string, string[]> {
  const out: Record<string, string[]> = {};
  for (const [family, ids] of index) {
    if (ids.length > 1) out[family] = [...ids].sort();
  }
  return out;
}

const EXPORT_DECLARATION = /export\s+(?:const|let|class|function)\s+([A-Za-z_$][\w$]*(?:Api|ApiService))\b/g;

function exportedClientNames(files: string[], owner: ExtensionRoot | null): Array<[string, string]> {
  const names: Array<[string, string]> = [];
  for (const file of files) {
    const text = stripComments(readFileSync(file, 'utf8'));
    for (const m of text.matchAll(EXPORT_DECLARATION)) names.push([m[1], fileId(file, owner)]);
  }
  return names;
}

describe('API client conventions (fc-39)', () => {
  it('discovers core client files (a scan that reads nothing proves nothing)', () => {
    const index = familyIndex([{ owner: null, files: coreFiles }]);
    expect(index.get('/ai/learning')).toEqual(['core:frontend/src/features/ai/learning/api/learningApi.ts']);
    expect(index.get('/ai/skill_graph')).toEqual(['core:frontend/src/shared/services/ai/skillGraphApi.ts']);
    expect(index.size).toBeGreaterThan(50);
  });

  it('each endpoint family has one client file; the listed duplicates equal the observed ones', () => {
    const index = familyIndex([
      { owner: null, files: coreFiles },
      ...publicExtensions.map((ext) => ({ owner: ext, files: filesOf(ext) })),
    ]);
    const observed = duplicates(index);

    const expected: Record<string, string[]> = {};
    for (const [family, files] of Object.entries((coreAllowlist as ExtensionAllowlist).families ?? {})) {
      expected[family] = files.map((f) => `core:${f}`).sort();
    }
    const unlistable: string[] = [];
    for (const ext of publicExtensions) {
      for (const [family, files] of Object.entries(readExtensionAllowlist(ext).families ?? {})) {
        if (expected[family]) unlistable.push(`${family} is listed twice`);
        expected[family] = files.map((f) => (f.startsWith('core:') ? f : `${ext.rel}:${f}`)).sort();
      }
    }
    for (const [family, ids] of Object.entries(observed)) {
      const owners = new Set(ids.map((id) => id.split(':')[0]).filter((o) => o !== 'core'));
      if (owners.size > 1) unlistable.push(`${family} is called by more than one extension: ${ids.join(', ')}`);
    }

    expect(unlistable).toEqual([]);
    expect(observed).toEqual(expected);

    const privateIndex = familyIndex(privateExtensions.map((ext) => ({ owner: ext, files: filesOf(ext) })));
    const privateOnly = duplicates(privateIndex);
    if (Object.keys(privateOnly).length > 0) {
      console.warn('api-client-conventions: a checked-out private extension calls one endpoint family from several files (not enforced here):', privateOnly);
    }
  });

  it('client export names (*Api, *ApiService) are unique across core and every public extension', () => {
    const enforced = [
      ...exportedClientNames(coreFiles, null),
      ...publicExtensions.flatMap((ext) => exportedClientNames(filesOf(ext), ext)),
    ];
    expect(enforced.length).toBeGreaterThan(100);

    const clashesIn = (names: Array<[string, string]>) => {
      const byName = new Map<string, string[]>();
      for (const [name, id] of names) byName.set(name, [...(byName.get(name) ?? []), id]);
      return [...byName].filter(([, ids]) => ids.length > 1).map(([name, ids]) => `${name}: ${ids.sort().join(', ')}`);
    };

    expect(clashesIn(enforced)).toEqual([]);

    // A private extension's name that clashes with core, a public extension or
    // another private one is reported, not enforced (see PRIVATE EXTENSIONS).
    const privateNames = privateExtensions.flatMap((ext) => exportedClientNames(filesOf(ext), ext));
    const privateOwners = new Set(privateExtensions.map((ext) => ext.rel));
    const privateClashes = clashesIn([...enforced, ...privateNames]).filter((clash) =>
      [...privateOwners].some((owner) => clash.includes(`${owner}:`))
    );
    if (privateClashes.length > 0) {
      console.warn('api-client-conventions: a checked-out private extension exports a client name already in use (not enforced here):', privateClashes);
    }
  });

  it('extension components do not import the raw HTTP client; the listed exceptions equal the observed ones', () => {
    const importsClient = (file: string) =>
      /\.tsx$/.test(file) &&
      !file.split(sep).includes('services') &&
      /from\s+['"](?:@\/shared\/services\/(?:api|apiClient)|(?:\.\.\/)+(?:shared\/)?services\/(?:api|apiClient))['"]/.test(
        stripComments(readFileSync(file, 'utf8'))
      );

    for (const ext of publicExtensions) {
      const observed = filesOf(ext).filter(importsClient).map((f) => relative(ext.dir, f).split(sep).join('/')).sort();
      expect({ extension: ext.rel, files: observed }).toEqual({
        extension: ext.rel,
        files: [...(readExtensionAllowlist(ext).tsxDirectImports ?? [])].sort(),
      });
    }

    const privateHits = privateExtensions.flatMap((ext) => filesOf(ext).filter(importsClient).map((f) => fileId(f, ext)));
    if (privateHits.length > 0) {
      console.warn('api-client-conventions: a checked-out private extension imports the raw HTTP client in a component (not enforced here):', privateHits);
    }
  });
});
