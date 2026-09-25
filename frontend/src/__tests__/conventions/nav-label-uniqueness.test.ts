import { readFileSync, readdirSync, statSync } from 'fs';
import { join, relative, sep } from 'path';
import { defaultNavigationConfig, adminNavigationOverrides } from '@/shared/utils/navigation';

/**
 * Navigation label uniqueness guard (P13, fc-47).
 *
 * One label should name one place. When the sidebar says "Analytics" twice,
 * or a hub tab and a sidebar item both say "Marketplace" but open different
 * pages, the operator has to click to find out which one they meant, and
 * breadcrumbs and search results stop disambiguating anything.
 *
 * SCOPE (fc-47 decision D4): the sidebar and hub tab strips. Modals, detail
 * panels and filter strips are out of scope; they are not destinations.
 *
 *   - Sidebar: core's defaultNavigationConfig and adminNavigationOverrides,
 *     plus every checked-out extension's register.ts (registerNavItems and
 *     the items of registerNavSections), read as text.
 *   - Hub tab strips: a top-level `const` whose name ends in "tabs" (any
 *     case), assigned an array literal (directly or through one wrapper call
 *     such as useMemo), whose entries carry a `label:`. Files named *Modal*
 *     and arrays whose name mentions "filter" are skipped.
 *
 * A destination is its href. A hub tab's href is its own absolute `path:`,
 * or the strip's base path (a `basePath=` prop, or a `*_BASE*` / `BASE_PATH`
 * string constant in the same file) joined with the tab's `path:`, `key:` or
 * `id:`. A strip whose base path cannot be read is not a hub strip (a status
 * filter's constants, or a panel's in-memory tabs) and is not counted.
 *
 * A CLASH is one label (compared case-insensitively) on two or more distinct
 * destinations. "Overview" is exempt: every hub and several sidebar sections
 * open on one, and the section or hub name beside it says which.
 *
 * EQUALITY RATCHET: the computed clash set must EQUAL KNOWN_CLASHES. A new
 * clash fails; a clash that was fixed but is still listed also fails, so the
 * list can only shrink. Add an entry only with the owner's agreement, never
 * to turn a red run green.
 *
 * PRIVATE EXTENSIONS ARE SCANNED BUT NOT RATCHETED (the same rule as
 * nav-link-reachability.test.ts): they are absent from public clones, so a
 * clash that exists only because of one is not portable. The ratchet is
 * computed over core and public extensions only; clashes that appear only
 * once private extensions are added go to console.warn. This file never
 * names an extension.
 */

const FRONTEND_SRC = join(__dirname, '..', '..');
const REPO_ROOT = join(FRONTEND_SRC, '..', '..');
const EXTENSIONS_ROOT = join(REPO_ROOT, 'extensions');
const PRIVATE_ROOT = join(EXTENSIONS_ROOT, 'private') + sep;

// label (lower case) -> the sorted destinations that share it. Each entry is
// a clash that predates this guard and was outside fc-47's approved renames;
// it is left to the owning hub. Fixing one means deleting its entry here.
const KNOWN_CLASHES: Record<string, string[]> = {
  analytics: ['/app/admin/audit-logs/analytics', '/app/ai/knowledge/rag/analytics', '/app/ai/model-router/analytics'],
  // The same panel is a tab of two hubs (Compute › Platform and Service Delivery).
  children: ['/app/system/compute/platform/children', '/app/system/service-delivery/children'],
  // DevOps › Containers sub-strips: Kubernetes and Swarm each name their clusters.
  clusters: ['/app/devops/containers/kubernetes', '/app/devops/containers/swarm'],
  containers: ['/app/devops/containers', '/app/devops/containers/docker/containers'],
  federation: ['/app/ai/agents/community/federation', '/app/system/sdwan/federation'],
  networks: [
    '/app/devops/containers/docker/networks',
    '/app/devops/containers/swarm/networks',
    '/app/system/sdwan/networks',
  ],
  operations: ['/app/devops/containers/swarm/operations', '/app/system/operations'],
  optimization: ['/app/ai/model-router/optimization', '/app/ai/skills/optimization'],
  providers: ['/app/ai/providers', '/app/devops/source-control/providers', '/app/system/compute/providers'],
  services: ['/app/devops/containers/swarm/services', '/app/system/compute/platform/services'],
  templates: [
    '/app/ai/execution/sandboxes/templates',
    '/app/devops/ci-cd/templates',
    '/app/system/catalog/templates',
  ],
  topology: ['/app/system/sdwan/topology', '/app/system/topology'],
  volumes: ['/app/devops/containers/docker/volumes', '/app/system/compute/volumes'],
};

interface Entry {
  label: string;
  destination: string;
  origin: string;
  isPrivate: boolean;
  isTab: boolean;
}

function discoverExtensionDirs(): string[] {
  const dirs: string[] = [];
  const push = (root: string) => {
    try {
      for (const e of readdirSync(root, { withFileTypes: true })) {
        if (!e.isDirectory() || e.name === 'private') continue;
        dirs.push(join(root, e.name));
      }
    } catch {
      // root absent: nothing installed there
    }
  };
  push(EXTENSIONS_ROOT);
  push(join(EXTENSIONS_ROOT, 'private'));
  return dirs;
}

function isFile(path: string): boolean {
  try {
    return statSync(path).isFile();
  } catch {
    return false;
  }
}

function isDir(path: string): boolean {
  try {
    return statSync(path).isDirectory();
  } catch {
    return false;
  }
}

// Drops // and /* */ comments while leaving string contents intact.
function stripComments(src: string): string {
  let out = '';
  let inString: string | null = null;
  for (let i = 0; i < src.length; i++) {
    const c = src[i];
    if (inString) {
      out += c;
      if (c === '\\' && i + 1 < src.length) {
        out += src[++i];
      } else if (c === inString) {
        inString = null;
      }
      continue;
    }
    if (c === '/' && src[i + 1] === '/') {
      while (i < src.length && src[i] !== '\n') i++;
      out += '\n';
      continue;
    }
    if (c === '/' && src[i + 1] === '*') {
      i += 2;
      while (i < src.length && !(src[i] === '*' && src[i + 1] === '/')) i++;
      i++;
      continue;
    }
    if (c === '"' || c === "'" || c === '`') inString = c;
    out += c;
  }
  return out;
}

// Index of the bracket that closes the one at `start`, skipping strings.
function matchClose(src: string, start: number): number {
  const open = src[start];
  const close = open === '[' ? ']' : open === '{' ? '}' : ')';
  let depth = 0;
  let inString: string | null = null;
  for (let i = start; i < src.length; i++) {
    const c = src[i];
    if (inString) {
      if (c === '\\') i++;
      else if (c === inString) inString = null;
      continue;
    }
    if (c === '"' || c === "'" || c === '`') inString = c;
    else if (c === open) depth++;
    else if (c === close && --depth === 0) return i;
  }
  return -1;
}

// The `{ ... }` objects opened directly inside the array body [start, end].
function topLevelObjects(src: string, start: number, end: number): string[] {
  const objects: string[] = [];
  let i = start + 1;
  while (i < end) {
    const c = src[i];
    if (c === '"' || c === "'" || c === '`') {
      const q = c;
      i++;
      while (i < end && src[i] !== q) i += src[i] === '\\' ? 2 : 1;
      i++;
      continue;
    }
    if (c === '{' || c === '[' || c === '(') {
      const close = matchClose(src, i);
      if (close === -1) break;
      if (c === '{') objects.push(src.slice(i, close + 1));
      i = close + 1;
      continue;
    }
    i++;
  }
  return objects;
}

// A string-valued property that belongs to the object itself, not to an
// object nested inside it.
function ownString(obj: string, prop: string): string | undefined {
  const re = new RegExp(`\\b${prop}\\s*:\\s*(['"])((?:\\\\.|(?!\\1).)*)\\1`, 'g');
  let m: RegExpExecArray | null;
  while ((m = re.exec(obj))) {
    let depth = 0;
    for (let i = 1; i < m.index; i++) {
      if (obj[i] === '{') depth++;
      else if (obj[i] === '}') depth--;
    }
    if (depth === 0) return m[2];
  }
  return undefined;
}

function joinPath(base: string, part: string): string {
  if (part.startsWith('/app/')) return part;
  const tail = part.replace(/^\/+/, '');
  return tail ? `${base.replace(/\/+$/, '')}/${tail}` : base.replace(/\/+$/, '');
}

// ---------------------------------------------------------------------------
// Sidebar
// ---------------------------------------------------------------------------

function coreSidebar(): Entry[] {
  const sections = [...(defaultNavigationConfig.sections ?? []), ...(adminNavigationOverrides.sections ?? [])];
  const items = [...defaultNavigationConfig.items, ...sections.flatMap((s) => s.items)];
  return items.map((i) => ({
    label: i.name,
    destination: i.href,
    origin: 'core sidebar',
    isPrivate: false,
    isTab: false,
  }));
}

function callArrayBodies(src: string, callName: string): Array<[number, number]> {
  const spans: Array<[number, number]> = [];
  const re = new RegExp(`featureRegistry\\.${callName}\\s*\\(`, 'g');
  let m: RegExpExecArray | null;
  while ((m = re.exec(src))) {
    const start = src.indexOf('[', m.index);
    const end = start === -1 ? -1 : matchClose(src, start);
    if (end !== -1) spans.push([start, end]);
  }
  return spans;
}

function extensionSidebar(extDir: string): Entry[] {
  const file = join(extDir, 'frontend', 'src', 'register.ts');
  if (!isFile(file)) return [];
  const src = stripComments(readFileSync(file, 'utf8'));
  const isPrivate = (extDir + sep).startsWith(PRIVATE_ROOT);
  const origin = relative(REPO_ROOT, file);
  const entries: Entry[] = [];
  const add = (obj: string) => {
    const label = ownString(obj, 'label');
    const path = ownString(obj, 'path');
    if (label && path) entries.push({ label, destination: path, origin, isPrivate, isTab: false });
  };
  for (const [start, end] of callArrayBodies(src, 'registerNavItems')) {
    topLevelObjects(src, start, end).forEach(add);
  }
  for (const [start, end] of callArrayBodies(src, 'registerNavSections')) {
    for (const section of topLevelObjects(src, start, end)) {
      const itemsAt = section.search(/\bitems\s*:\s*\[/);
      if (itemsAt === -1) continue;
      const open = section.indexOf('[', itemsAt);
      topLevelObjects(section, open, matchClose(section, open)).forEach(add);
    }
  }
  return entries;
}

// ---------------------------------------------------------------------------
// Hub tab strips
// ---------------------------------------------------------------------------

function walkSources(dir: string, acc: string[] = []): string[] {
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    if (e.name === 'node_modules' || e.name.startsWith('.') || e.name === '__tests__') continue;
    const full = join(dir, e.name);
    if (e.isDirectory()) walkSources(full, acc);
    else if (/\.tsx?$/.test(e.name) && !/\.(test|spec)\.tsx?$/.test(e.name) && !/\.d\.ts$/.test(e.name)) {
      acc.push(full);
    }
  }
  return acc;
}

function basePathOf(src: string): string | undefined {
  const literal = src.match(/basePath\s*=\s*["'](\/app\/[^"']+)["']/);
  if (literal) return literal[1];
  const viaConst = src.match(/basePath\s*=\s*\{\s*([A-Za-z_][A-Za-z0-9_]*)\s*\}/);
  if (viaConst) {
    const decl = src.match(new RegExp(`\\b${viaConst[1]}\\s*=\\s*['"](\\/app\\/[^'"]+)['"]`));
    if (decl) return decl[1];
  }
  const baseConst = src.match(/\bconst\s+[A-Z_]*BASE[A-Z_]*\s*=\s*['"](\/app\/[^'"]+)['"]/);
  return baseConst?.[1];
}

function hubTabs(file: string, isPrivate: boolean): Entry[] {
  if (/Modal/.test(file.split(sep).pop() ?? '')) return [];
  const src = stripComments(readFileSync(file, 'utf8'));
  const base = basePathOf(src);
  const origin = relative(REPO_ROOT, file);
  const entries: Entry[] = [];
  const declRe = /^\s*(?:export\s+)?const\s+([A-Za-z0-9_]*tabs)\b[^=\n]*=\s*/gim;
  let m: RegExpExecArray | null;
  while ((m = declRe.exec(src))) {
    if (/filter/i.test(m[1])) continue;
    let open = m.index + m[0].length;
    if (src[open] !== '[') {
      const bracket = src.indexOf('[', open);
      const semicolon = src.indexOf(';', open);
      if (bracket === -1 || (semicolon !== -1 && semicolon < bracket)) continue;
      open = bracket;
    }
    const close = matchClose(src, open);
    if (close === -1) continue;
    for (const obj of topLevelObjects(src, open, close)) {
      const label = ownString(obj, 'label');
      const segment = ownString(obj, 'path') ?? ownString(obj, 'key') ?? ownString(obj, 'id');
      if (!label || segment === undefined) continue;
      const destination = segment.startsWith('/app/') ? segment : base ? joinPath(base, segment) : undefined;
      if (destination) entries.push({ label, destination, origin, isPrivate, isTab: true });
    }
  }
  return entries;
}

// ---------------------------------------------------------------------------
// Clash computation
// ---------------------------------------------------------------------------

function collectEntries(): Entry[] {
  const entries: Entry[] = [...coreSidebar()];
  for (const file of walkSources(FRONTEND_SRC)) entries.push(...hubTabs(file, false));
  for (const extDir of discoverExtensionDirs()) {
    const isPrivate = (extDir + sep).startsWith(PRIVATE_ROOT);
    entries.push(...extensionSidebar(extDir));
    const srcDir = join(extDir, 'frontend', 'src');
    if (isDir(srcDir)) for (const file of walkSources(srcDir)) entries.push(...hubTabs(file, isPrivate));
  }
  return entries;
}

function clashes(entries: Entry[]): Record<string, string[]> {
  const byLabel = new Map<string, Set<string>>();
  for (const e of entries) {
    const label = e.label.trim().toLowerCase();
    if (label === 'overview') continue;
    if (!byLabel.has(label)) byLabel.set(label, new Set());
    byLabel.get(label)!.add(e.destination);
  }
  const result: Record<string, string[]> = {};
  for (const label of [...byLabel.keys()].sort()) {
    const destinations = [...byLabel.get(label)!].sort();
    if (destinations.length > 1) result[label] = destinations;
  }
  return result;
}

describe('navigation label uniqueness (P13, fc-47)', () => {
  const entries = collectEntries();

  it('finds the sidebar and hub tab strips it is meant to read', () => {
    // A scanner that silently finds nothing would make every run green.
    expect(entries.filter((e) => !e.isTab).length).toBeGreaterThan(40);
    expect(entries.filter((e) => e.isTab).length).toBeGreaterThan(40);
  });

  it('gives one label to one destination, except the known clashes', () => {
    expect(clashes(entries.filter((e) => !e.isPrivate))).toEqual(KNOWN_CLASHES);
  });

  it('reports clashes that only private extensions introduce, without failing', () => {
    const publicClashes = clashes(entries.filter((e) => !e.isPrivate));
    const allClashes = clashes(entries);
    const privateOnly = Object.keys(allClashes).filter(
      (label) => JSON.stringify(allClashes[label]) !== JSON.stringify(publicClashes[label])
    );
    if (privateOnly.length > 0) {
      // eslint-disable-next-line no-console
      console.warn(
        'Navigation label clashes involving private extensions:\n' +
          privateOnly.map((l) => `  ${l}: ${allClashes[l].join(', ')}`).join('\n')
      );
    }
    expect(Array.isArray(privateOnly)).toBe(true);
  });
});
