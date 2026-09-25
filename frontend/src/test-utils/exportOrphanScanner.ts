import { readFileSync, readdirSync, statSync } from 'fs';
import { join, relative, basename, dirname, sep } from 'path';

/**
 * Export-level orphan scanner behind __tests__/conventions/export-orphans.test.ts
 * (P1/P7, fc-48).
 *
 * An exported symbol is ORPHANED when no production file outside its own
 * module uses it AND its own module does not use it either. Precisely:
 *
 *   - "Use" is the symbol's identifier appearing in comment-stripped source.
 *     A barrel RE-EXPORT (`export { X } from './X'`, `export * from ...`) is
 *     NOT a use — it only forwards the name, so a page reachable solely
 *     through its own index.ts is still an orphan (the "absorbed page left
 *     behind" shape page-reverse-reachability could not see).
 *   - A default export is also used when its module path is imported
 *     (`import X from './Foo'`, `lazy(() => import('./Foo'))`): the importer
 *     picks the local name, so the export's own identifier need not appear.
 *   - A use from a TEST file does not count: code only a test reaches is dead
 *     in production. Test-support files (tests, __tests__, __mocks__,
 *     test-utils/testUtils, setupTests) are consumers only, never candidates.
 *   - Files outside src that import from it — the frontend's own config files
 *     (vite.config.ts and friends) — are production consumers.
 *   - An export its own module also uses is NOT an orphan: that is an
 *     unnecessary `export`, not dead code. An EXPORT STATEMENT is not a use:
 *     `export default X;` and `export { X }` name X again in its own file, and
 *     counting them hid every `const XPage = ...; export default XPage;` page.
 *   - PUBLIC exports (core and public extensions) are judged against public
 *     consumers only; private-extension exports are judged against every
 *     tree. A public checkout (no private extensions) therefore reaches the
 *     same verdict on every public export as a maintainer checkout — a core
 *     export only a private extension consumes is an orphan in both.
 *
 * Matching is by identifier, not a module graph: coarse on purpose, like the
 * other conventions guards. A same-named symbol elsewhere can hide an orphan
 * (a miss, never a false alarm); the allowlist is the reviewed record of
 * every orphan the scan does see.
 */

export interface ScanRoot {
  /** Absolute path of a frontend source tree (core frontend/src, or an extension's frontend/src). */
  srcDir: string;
  /** Absolute path of that frontend's root, whose top-level config files are consumers. */
  frontendDir: string;
  /** A private extension's tree: its uses never make a public export reachable. */
  private?: boolean;
}

export interface Orphan {
  /** Repo-relative path of the declaring file. */
  path: string;
  name: string;
  kind: 'value' | 'type';
}

const SOURCE_RE = /\.(tsx?|jsx?)$/;
const CONFIG_RE = /\.(ts|js|mjs|cjs)$/;

export function isTestSupport(file: string): boolean {
  const parts = file.split(sep);
  const name = basename(file);
  return (
    /\.(test|spec)\.(tsx?|jsx?)$/.test(name) ||
    /^test[-_]?utils\.(tsx?|jsx?)$/i.test(name) ||
    /^setupTests\.(tsx?|jsx?)$/.test(name) ||
    parts.some((p) => p === '__tests__' || p === '__mocks__' || p === 'tests' || p === 'test-utils')
  );
}

function walk(dir: string, acc: string[] = []): string[] {
  let entries: import('fs').Dirent[];
  try {
    entries = readdirSync(dir, { withFileTypes: true });
  } catch {
    return acc;
  }
  for (const entry of entries) {
    if (entry.name === 'node_modules' || entry.name.startsWith('.')) continue;
    const full = join(dir, entry.name);
    if (entry.isDirectory()) walk(full, acc);
    else if (SOURCE_RE.test(entry.name) && !entry.name.endsWith('.d.ts')) acc.push(full);
  }
  return acc;
}

function topLevelConfigFiles(frontendDir: string): string[] {
  try {
    return readdirSync(frontendDir, { withFileTypes: true })
      .filter((e) => e.isFile() && CONFIG_RE.test(e.name) && !e.name.endsWith('.d.ts'))
      .map((e) => join(frontendDir, e.name));
  } catch {
    return [];
  }
}

/**
 * Drops comments, keeping strings. A `'`/`"` between two word characters
 * ("don't" in JSX text) is text, not a string opener, and a quoted string
 * force-closes at a newline (a real one cannot contain one) — without both, a
 * JSX apostrophe opens a phantom string whose end swallows real code
 * (see path-addressable-tabs.test.ts).
 */
export function stripComments(src: string): string {
  let out = '';
  let i = 0;
  const n = src.length;
  let inString: '"' | "'" | '`' | null = null;
  while (i < n) {
    const c = src[i];
    const c2 = src[i + 1];
    if (inString) {
      if (c === '\\') {
        out += c + (src[i + 1] ?? '');
        i += 2;
        continue;
      }
      if (c === '\n' && inString !== '`') inString = null;
      else if (c === inString) inString = null;
      out += c;
      i += 1;
      continue;
    }
    if (c === '"' || c === "'" || c === '`') {
      const prev = src[i - 1] ?? '';
      if (c !== '`' && /\w/.test(prev) && /\w/.test(c2 ?? '')) {
        out += c;
        i += 1;
        continue;
      }
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

const BARREL_RE = /export\s+(?:type\s+)?\{[^}]*\}\s*from\s*['"][^'"]+['"];?|export\s+\*\s+(?:as\s+[\w$]+\s+)?from\s*['"][^'"]+['"];?/g;
const IDENT_RE = /[A-Za-z_$][\w$]*/g;
const SPECIFIER_RE = /(?:from\s*|import\s*\(\s*|require\s*\(\s*)['"`]([^'"`]+)['"`]/g;
const DECL_RE =
  /export\s+(?:declare\s+)?(default\s+)?(?:(async\s+)?function\*?|const|let|var|class|abstract\s+class|interface|type|enum)\s+([A-Za-z_$][\w$]*)/g;
const LOCAL_LIST_RE = /export\s+(type\s+)?\{([^}]*)\}(?!\s*from)/g;
// `export default X` — with or without its semicolon (a line end closes it
// too) — but not `export default function X` / `class X`, which DECL_RE owns.
const DEFAULT_IDENT_RE =
  /export\s+default\s+(?!(?:function|class|async|abstract|interface|enum)\b)([A-Za-z_$][\w$]*)[ \t]*(?:;|$)/gm;

/** The file with its export statements that only NAME local bindings removed: what is left is its own use. */
function withoutExportStatements(src: string): string {
  return src.replace(LOCAL_LIST_RE, ' ').replace(DEFAULT_IDENT_RE, ' ');
}

interface Declared {
  name: string;
  kind: 'value' | 'type';
  isDefault: boolean;
}

function declaredExports(src: string): Declared[] {
  const out = new Map<string, Declared>();
  let m: RegExpExecArray | null;
  DECL_RE.lastIndex = 0;
  while ((m = DECL_RE.exec(src))) {
    const keyword = m[0];
    const kind = /\b(interface|type)\s+[A-Za-z_$]/.test(keyword.replace(/^export\s+(declare\s+)?/, '')) ? 'type' : 'value';
    out.set(m[3], { name: m[3], kind, isDefault: !!m[1] });
  }
  LOCAL_LIST_RE.lastIndex = 0;
  while ((m = LOCAL_LIST_RE.exec(src))) {
    const listIsType = !!m[1];
    for (const raw of m[2].split(',')) {
      const part = raw.trim();
      if (!part) continue;
      const isType = listIsType || /^type\s/.test(part);
      const [local, alias] = part.replace(/^type\s+/, '').split(/\s+as\s+/);
      // `export { X as default }` is X's default export: judge X, by name and by module path.
      if (alias?.trim() === 'default') {
        const x = local.trim();
        if (x) out.set(x, { name: x, kind: out.get(x)?.kind ?? (isType ? 'type' : 'value'), isDefault: true });
        continue;
      }
      const name = (alias ?? local).trim();
      if (!name || name === 'default') continue;
      if (!out.has(name)) out.set(name, { name, kind: isType ? 'type' : 'value', isDefault: false });
    }
  }
  DEFAULT_IDENT_RE.lastIndex = 0;
  while ((m = DEFAULT_IDENT_RE.exec(src))) {
    const existing = out.get(m[1]);
    out.set(m[1], { name: m[1], kind: existing?.kind ?? 'value', isDefault: true });
  }
  return [...out.values()];
}

/** The name an import specifier resolves to: its last segment, or its directory for an index. */
function moduleKey(file: string): string {
  const base = basename(file).replace(SOURCE_RE, '');
  return base === 'index' ? basename(dirname(file)) : base;
}

function specifierKey(spec: string): string {
  const last = spec.split('/').pop() ?? spec;
  return last.replace(SOURCE_RE, '');
}

interface FileInfo {
  path: string;
  candidate: boolean; // may declare orphans (production source file)
  production: boolean; // its uses count
  private: boolean; // lives in a private extension tree
  selfText: string; // stripped source minus its local export statements
  stripped: string;
  tokens: Set<string>;
  specifierKeys: Set<string>;
}

export function scanExportOrphans(roots: ScanRoot[], repoRoot: string): Orphan[] {
  const files: FileInfo[] = [];
  const seen = new Set<string>();
  const add = (path: string, candidate: boolean, isPrivate: boolean) => {
    if (seen.has(path)) return;
    seen.add(path);
    const stripped = stripComments(readFileSync(path, 'utf8'));
    const withoutBarrels = stripped.replace(BARREL_RE, ' ');
    const tokens = new Set(withoutBarrels.match(IDENT_RE) ?? []);
    const specifierKeys = new Set<string>();
    let m: RegExpExecArray | null;
    SPECIFIER_RE.lastIndex = 0;
    while ((m = SPECIFIER_RE.exec(withoutBarrels))) specifierKeys.add(specifierKey(m[1]));
    const testSupport = isTestSupport(path);
    files.push({
      path,
      candidate: candidate && !testSupport,
      production: !testSupport,
      private: isPrivate,
      stripped,
      selfText: withoutExportStatements(stripped),
      tokens,
      specifierKeys,
    });
  };
  for (const root of roots) {
    for (const f of walk(root.srcDir)) add(f, true, !!root.private);
    for (const f of topLevelConfigFiles(root.frontendDir)) add(f, false, !!root.private);
  }

  // token -> number of production files using it; module key -> number of
  // production importers. Kept per audience: `pub` counts public files only
  // (the consumers a public export is judged by), `all` counts every tree.
  const count = (includePrivate: boolean) => {
    const tokenUsers = new Map<string, number>();
    const moduleImporters = new Map<string, number>();
    for (const f of files) {
      if (!f.production || (f.private && !includePrivate)) continue;
      for (const t of f.tokens) tokenUsers.set(t, (tokenUsers.get(t) ?? 0) + 1);
      for (const k of f.specifierKeys) moduleImporters.set(k, (moduleImporters.get(k) ?? 0) + 1);
    }
    return { tokenUsers, moduleImporters };
  };
  const pub = count(false);
  const all = count(true);

  const orphans: Orphan[] = [];
  for (const f of files) {
    if (!f.candidate) continue;
    const exported = declaredExports(f.stripped);
    if (exported.length === 0) continue;
    const { tokenUsers, moduleImporters } = f.private ? all : pub;
    for (const d of exported) {
      const elsewhere = (tokenUsers.get(d.name) ?? 0) - (f.tokens.has(d.name) ? 1 : 0);
      if (elsewhere > 0) continue;
      // Beyond its one declaration, and ignoring export statements.
      const occurrences = f.selfText.match(new RegExp(`(?<![\\w$])${d.name.replace(/\$/g, '\\$')}(?![\\w$])`, 'g'));
      if ((occurrences?.length ?? 0) > 1) continue; // used by its own module
      if (d.isDefault) {
        const key = moduleKey(f.path);
        const importers = (moduleImporters.get(key) ?? 0) - (f.specifierKeys.has(key) ? 1 : 0);
        if (importers > 0) continue;
      }
      orphans.push({ path: relative(repoRoot, f.path).split(sep).join('/'), name: d.name, kind: d.kind });
    }
  }
  return orphans.sort((a, b) => (a.path + '#' + a.name).localeCompare(b.path + '#' + b.name));
}

/** Every checked-out extension frontend (public and private), found by directory walk — never by name. */
export function discoverExtensionRoots(extensionsDir: string): Array<ScanRoot & { repoRelRoot: string }> {
  const out: Array<ScanRoot & { repoRelRoot: string }> = [];
  // stat, not Dirent.isDirectory(): an extension checked out as a symlink is a
  // directory too (the Ruby and shell guards follow symlinks the same way).
  const isDir = (p: string) => {
    try {
      return statSync(p).isDirectory();
    } catch {
      return false;
    }
  };
  const children = (dir: string) => {
    try {
      return readdirSync(dir).sort();
    } catch {
      return [];
    }
  };
  const consider = (dir: string, repoRelRoot: string, isPrivate: boolean) => {
    const srcDir = join(dir, 'frontend', 'src');
    if (isDir(srcDir)) out.push({ srcDir, frontendDir: join(dir, 'frontend'), repoRelRoot, private: isPrivate });
  };
  for (const name of children(extensionsDir)) {
    const full = join(extensionsDir, name);
    if (!isDir(full)) continue;
    if (name === 'private') {
      for (const p of children(full)) {
        if (isDir(join(full, p))) consider(join(full, p), `extensions/private/${p}`, true);
      }
    } else {
      consider(full, `extensions/${name}`, false);
    }
  }
  return out;
}

export interface AllowlistEntry {
  path: string;
  name: string;
  reason: string;
}

export const ALLOWLIST_RELATIVE_PATH = join('__tests__', 'conventions', 'export-orphans.allowlist.json');

/**
 * One tree's allowlist. Malformed JSON, an entry without path/name/reason, or
 * an entry naming a path outside `repoRelRoot` fails loudly — an allowlist may
 * only excuse orphans in its own tree. A missing file is an error only when
 * `required` (core); an extension may contribute none.
 */
export function loadAllowlist(srcDir: string, repoRelRoot: string, required: boolean): AllowlistEntry[] {
  let raw: string;
  try {
    raw = readFileSync(join(srcDir, ALLOWLIST_RELATIVE_PATH), 'utf8');
  } catch {
    if (required) throw new Error(`missing ${ALLOWLIST_RELATIVE_PATH} under ${repoRelRoot}`);
    return [];
  }
  const parsed: unknown = JSON.parse(raw);
  if (!Array.isArray(parsed)) throw new Error(`${repoRelRoot}: ${ALLOWLIST_RELATIVE_PATH} must be an array`);
  for (const e of parsed as AllowlistEntry[]) {
    const valid =
      !!e && typeof e.path === 'string' && typeof e.name === 'string' && typeof e.reason === 'string' && e.reason.trim() !== '';
    if (!valid) throw new Error(`${repoRelRoot}: every allowlist entry needs path, name and a reason: ${JSON.stringify(e)}`);
    if (!e.path.startsWith(`${repoRelRoot}/`)) {
      throw new Error(`${repoRelRoot}: allowlist entry outside its own tree: ${e.path}`);
    }
  }
  return parsed as AllowlistEntry[];
}
