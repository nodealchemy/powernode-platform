import { readFileSync, readdirSync, statSync } from 'fs';
import { join, sep, relative } from 'path';

/**
 * No-stub-affordances guard (fc-05, revised per fc-05 review round 2).
 *
 * A button or link that LOOKS actionable but does nothing — an `on[A-Z]...`
 * prop/key bound to an empty/no-op handler — and a "coming soon" label are
 * both the same failure mode from the user's side: a dead affordance with no
 * signal that it is dead. Nothing else in the suite catches either shape
 * generically; page-level tests only notice a SPECIFIC missing behavior they
 * were written to expect.
 *
 * Two violation kinds:
 *   - EMPTY_HANDLER: `on[A-Z]\w*` (a JSX prop `onClick={...}` or an object
 *     key `onClick: ...`, e.g. a PageContainer action) bound to a no-op —
 *     see EMPTY_HANDLER_RE's comment for the exact shapes covered.
 *   - COMING_SOON: the phrase "coming soon" (case-insensitive, hyphen or
 *     any whitespace run as the separator) in source, comments stripped
 *     first so a doc comment describing this guard does not trip it.
 *
 * EQUALITY RATCHET, NOT A CARRIED BASELINE (mirrors nav-link-reachability.test.ts):
 * PUBLIC (core + public extensions) is ratcheted against ALLOWED_STUBS —
 * currently EMPTY (fc-05 review: every one of the 40 offenders found at
 * this guard's introduction has been fixed at its source; nothing is
 * allowlisted). A newly introduced stub fails the run; the mechanism is
 * kept (rather than deleted) only so a genuinely-unbuildable exception can
 * be added later, deliberately, one at a time.
 *
 * RATCHET IDENTITY IS `TYPE:path` — NOT `TYPE:path:line`. Line numbers are
 * surfaced only in the failure's console.error detail, never in the
 * compared identity: an edit that shifts a violation's line number (e.g.
 * adding an unrelated line above it) must not change whether the ratchet
 * passes, and an allowlist entry (were one ever added) must not go stale
 * merely because the file grew a line above it. See the "unrelated edit"
 * mutation test below for the property this protects.
 *
 * PRIVATE EXTENSIONS FAIL, NOT WARN (fc-05 review M6): a checked-out private
 * extension with a stub affordance fails this test outright — no allowlist,
 * no console.warn-and-pass. The scan itself stays generic (whatever is
 * checked out under extensions/private/* is walked; nothing is hardcoded by
 * name — core-purity-check.sh), so a clone with no private extensions simply
 * finds nothing there and this half of the assertion is vacuously true.
 */

const FRONTEND_SRC = join(__dirname, '..', '..');
const REPO_ROOT = join(FRONTEND_SRC, '..', '..');
const EXTENSIONS_ROOT = join(REPO_ROOT, 'extensions');

// Discovered generically — core must not reference a specific extension
// (public or private) by name (core-purity-check.sh).
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

const PRIVATE_EXTENSIONS_ROOT = join(EXTENSIONS_ROOT, 'private') + sep;
function isPrivateExtensionSrcDir(dir: string): boolean {
  return (dir + sep).startsWith(PRIVATE_EXTENSIONS_ROOT);
}

// Named, itemized exceptions — NOT a count-based baseline, and currently
// EMPTY (fc-05 review round 2: the operator's rule is a comprehensive
// cleanup with no allowlisted debt). Every one of the 40 offenders found at
// this guard's introduction was fixed at its source rather than listed
// here. Add an entry only for a new, genuinely-unbuildable exception,
// deliberately, one at a time — never to make a red run green in bulk.
const ALLOWED_STUBS: readonly string[] = [];

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

// Crude string-vs-comment scanner (mirrors nav-link-reachability.test.ts):
// tracks whether it is inside a single/double/template-literal string so a
// `//` or `/*` INSIDE a string is never mistaken for a comment start.
//
// fc-05 review fix: a `/* ... */` block comment used to swallow its own
// internal newlines when stripped, so every line AFTER a multi-line block
// comment was undercounted by however many newlines the comment contained —
// wrong from the very next line onward. Newlines inside a block comment are
// now preserved (the comment TEXT is still dropped, so it can't be matched
// by content regexes) so line numbers reported after it stay accurate.
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
        if (src[i] === '\n') out += '\n'; // preserve line count through the comment
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

// EMPTY_HANDLER: `on[A-Z]\w*` (JSX prop `=` or object key `:`) bound to a
// no-op. Shapes covered (fc-05 review, both rounds — H3/M4/M5 + round-2
// optional extension):
//   - `() => {}`, `(a, b) => {}`, `e => {}`, `_e => {}` — arrow, with or
//     without parens, empty body
//   - `async () => {}`, `async e => {}`                  — same, async
//   - `() => { return; }`                                — an empty RETURN,
//     not just an empty block — same no-op, written the long way
//   - `() => undefined`, `() => null`, `() => void 0`     — arrow, no-op value
//   - `function(){}`, `function name(){}`                — plain/named function
//     expression (also accepts the `{ return; }` body)
//   - `noop`, `NOOP`, `_.noop`                            — a bare/lodash-style
//     reference to a no-op helper
// A body that is "only a comment" (e.g. `() => { /* TODO */ }`) collapses to
// `{}` once stripComments runs first, so it's caught by the plain-`{}` arm
// without a separate rule.
//
// TWO SEPARATE ALTERNATIVES FOR `=` vs `:` — NOT a shared optional brace
// (fc-05 review round 2): a JSX attribute (`onClick={...}`) always has a
// `{` immediately after `=`; an object property (`onClick: ...`) never
// needs one. Requiring the brace specifically after `=` is what keeps this
// from matching a destructuring DEFAULT — `{ onClose = () => {} }` — which
// uses `=` directly on a bare identifier with no `{` following it. Collapsing
// both into one `on[A-Z]\w*\s*[:=]\s*\{?` (the round-1 shape) could not tell
// the two apart; see the "does NOT match a destructuring default" unit test.
//
// Deliberately NOT case-insensitive as a whole (unlike COMING_SOON_RE):
// `on[A-Z]` encodes the camelCase prop convention itself, and folding case
// here would also fold "on" + any letter (e.g. "one", "only"), turning a
// targeted lint into one that fires on ordinary prose. `noop`/`NOOP`/`_.noop`
// are named explicitly rather than case-folded for the same reason.
const EMPTY_BODY = '\\{\\s*(?:return;?\\s*)?\\}';
const ARROW_PARAMS = '(?:\\([^)]*\\)|[A-Za-z_$][\\w$]*)';
const HANDLER_VALUE =
  '(?:async\\s+)?' + ARROW_PARAMS + '\\s*=>\\s*(?:' + EMPTY_BODY + '|undefined\\b|null\\b|void\\s+0\\b)' +
  '|function\\s*\\w*\\s*\\([^)]*\\)\\s*' + EMPTY_BODY +
  '|noop\\b|NOOP\\b|_\\.noop\\b';
const EMPTY_HANDLER_RE = new RegExp(
  '\\bon[A-Z]\\w*\\s*(?:' +
    '=\\s*\\{\\s*(?:' + HANDLER_VALUE + ')' + // JSX attribute: = MUST be followed by {
    '|:\\s*(?:' + HANDLER_VALUE + ')' +        // object property: no brace needed
    ')',
  'g'
);

// "coming soon", case-insensitive, with a hyphen or any run of whitespace
// (space, tab, newline) as the separator — "coming-soon", "Coming  Soon",
// "coming\nsoon" all match; a no-separator "ComingSoon" does not (not asked
// for, and risks false positives against unrelated CamelCase identifiers).
const COMING_SOON_RE = /coming[\s-]+soon/gi;

function lineNumberAt(text: string, index: number): number {
  let line = 1;
  for (let i = 0; i < index; i++) {
    if (text[i] === '\n') line += 1;
  }
  return line;
}

interface Violation {
  type: 'EMPTY_HANDLER' | 'COMING_SOON';
  relPath: string;
  line: number;
  snippet: string;
}

function snippetAt(text: string, index: number, length: number): string {
  return text.slice(index, index + length).replace(/\s+/g, ' ').trim().slice(0, 80);
}

// Scans already-comment-stripped `text` for both violation kinds. Exported
// as a standalone function (not inlined in the `it` block) specifically so
// the unit/mutation tests below can exercise it directly against small
// fixture strings, independent of the filesystem walk.
function scanText(text: string, relPath: string): Violation[] {
  const found: Violation[] = [];

  EMPTY_HANDLER_RE.lastIndex = 0;
  let m: RegExpExecArray | null;
  while ((m = EMPTY_HANDLER_RE.exec(text))) {
    found.push({
      type: 'EMPTY_HANDLER',
      relPath,
      line: lineNumberAt(text, m.index),
      snippet: snippetAt(text, m.index, m[0].length),
    });
  }

  COMING_SOON_RE.lastIndex = 0;
  while ((m = COMING_SOON_RE.exec(text))) {
    found.push({
      type: 'COMING_SOON',
      relPath,
      line: lineNumberAt(text, m.index),
      snippet: snippetAt(text, m.index, m[0].length),
    });
  }

  return found;
}

function findViolations(files: string[], repoRelative: (p: string) => string): Violation[] {
  return files.flatMap((file) => {
    const text = stripComments(readFileSync(file, 'utf8'));
    return scanText(text, repoRelative(file));
  });
}

// Ratchet identity — file + type, deliberately WITHOUT the line number (see
// module doc comment). Deduped: two occurrences of the same kind in the
// same file collapse to one ratchet entry, since an allowlist entry (were
// one ever needed) excuses the FILE, not a specific line.
function toRatchetKeys(violations: Violation[]): string[] {
  return [...new Set(violations.map((v) => `${v.type}:${v.relPath}`))].sort();
}

function formatDetail(violations: Violation[], keys: readonly string[]): string {
  const keySet = new Set(keys);
  return violations
    .filter((v) => keySet.has(`${v.type}:${v.relPath}`))
    .map((v) => `  ${v.type} ${v.relPath}:${v.line} — ${v.snippet}`)
    .join('\n');
}

describe('convention: no dead "on*" handlers or "coming soon" placeholders (P10)', () => {
  it('core + public extensions: the offender set exactly matches the (currently empty) allowlist', () => {
    const extensionSrcDirs = discoverExtensionSrcDirs();
    const publicExtensionSrcDirs = extensionSrcDirs.filter((d) => !isPrivateExtensionSrcDir(d));

    const repoRelative = (p: string) => relative(REPO_ROOT, p).split(sep).join('/');

    const files = [FRONTEND_SRC, ...publicExtensionSrcDirs].flatMap((dir) => walkSourceFiles(dir));
    const violations = findViolations(files, repoRelative);
    const computedKeys = toRatchetKeys(violations);
    const expectedKeys = [...ALLOWED_STUBS].sort();

    expect([...ALLOWED_STUBS].sort()).toEqual([...ALLOWED_STUBS]); // sanity: list itself stays sorted

    if (computedKeys.join('\u0000') !== expectedKeys.join('\u0000')) {
      const unexpected = computedKeys.filter((k) => !expectedKeys.includes(k));
      const missing = expectedKeys.filter((k) => !computedKeys.includes(k));
      // eslint-disable-next-line no-console
      console.error(
        `no-stub-affordances: ratchet mismatch.\n` +
          (unexpected.length ? `Unexpected (${unexpected.length}):\n${formatDetail(violations, unexpected)}\n` : '') +
          (missing.length ? `Fixed/stale allowlist entries to remove (${missing.length}): ${missing.join(', ')}\n` : '')
      );
    }

    expect(computedKeys).toEqual(expectedKeys);
  });

  it('private extensions: any checked-out extension with a stub affordance FAILS this test (no allowlist)', () => {
    const extensionSrcDirs = discoverExtensionSrcDirs();
    const privateExtensionSrcDirs = extensionSrcDirs.filter(isPrivateExtensionSrcDir);
    const repoRelative = (p: string) => relative(REPO_ROOT, p).split(sep).join('/');

    const privateFiles = privateExtensionSrcDirs.flatMap((dir) => walkSourceFiles(dir));
    const violations = findViolations(privateFiles, repoRelative);

    if (violations.length > 0) {
      // eslint-disable-next-line no-console
      console.error(`no-stub-affordances: private extension stub(s) found:\n${formatDetail(violations, toRatchetKeys(violations))}`);
    }

    expect(toRatchetKeys(violations)).toEqual([]);
  });
});

describe('no-stub-affordances matcher (unit)', () => {
  const scan = (src: string) => scanText(stripComments(src), 'fixture.tsx');
  const types = (src: string) => scan(src).map((v) => v.type);

  describe('EMPTY_HANDLER shapes', () => {
    it('matches a no-arg arrow with an empty body: onClick={() => {}}', () => {
      expect(types('<button onClick={() => {}} />')).toEqual(['EMPTY_HANDLER']);
    });

    it('matches an arrow WITH parameters: onChange={(e) => {}}', () => {
      expect(types('<input onChange={(e) => {}} />')).toEqual(['EMPTY_HANDLER']);
    });

    it('matches an arrow with multiple parameters: onDrop={(item, mode) => {}}', () => {
      expect(types('<div onDrop={(item, mode) => {}} />')).toEqual(['EMPTY_HANDLER']);
    });

    it('matches an async arrow: onSave={async () => {}}', () => {
      expect(types('<Form onSave={async () => {}} />')).toEqual(['EMPTY_HANDLER']);
    });

    it('matches an async arrow WITH parameters: onSubmit={async (data) => {}}', () => {
      expect(types('<Form onSubmit={async (data) => {}} />')).toEqual(['EMPTY_HANDLER']);
    });

    it('matches an arrow returning undefined: onClick={() => undefined}', () => {
      expect(types('<button onClick={() => undefined} />')).toEqual(['EMPTY_HANDLER']);
    });

    it('matches an arrow returning null: onClick={() => null}', () => {
      expect(types('<button onClick={() => null} />')).toEqual(['EMPTY_HANDLER']);
    });

    it('matches an arrow returning void 0: onClick={() => void 0}', () => {
      expect(types('<button onClick={() => void 0} />')).toEqual(['EMPTY_HANDLER']);
    });

    it('matches an anonymous function expression: onClick={function() {}}', () => {
      expect(types('<button onClick={function() {}} />')).toEqual(['EMPTY_HANDLER']);
    });

    it('matches a named function expression: onClick={function handleClick() {}}', () => {
      expect(types('<button onClick={function handleClick() {}} />')).toEqual(['EMPTY_HANDLER']);
    });

    it('matches a bare noop reference: onClick={noop}', () => {
      expect(types('<button onClick={noop} />')).toEqual(['EMPTY_HANDLER']);
    });

    it('matches the object-property form (PageContainer action), not just JSX: { onClick: () => {} }', () => {
      expect(types("{ id: 'x', label: 'X', onClick: () => {} }")).toEqual(['EMPTY_HANDLER']);
    });

    it('matches the object-property form with a bare noop: { onClick: noop }', () => {
      expect(types('{ onClick: noop }')).toEqual(['EMPTY_HANDLER']);
    });

    it('matches a body that is ONLY a comment (collapses to {} once stripped)', () => {
      expect(
        types(`onDataUpdate: () => {
          // Trigger data refresh if needed
        }`)
      ).toEqual(['EMPTY_HANDLER']);
    });

    it('does NOT match a handler with a real body', () => {
      expect(types('<button onClick={() => doThing()} />')).toEqual([]);
    });

    it('does NOT match a handler that returns a real value', () => {
      expect(types('<button onClick={() => 1} />')).toEqual([]);
    });

    // fc-05 review round 2 (optional extension): a few more no-op shapes.
    it('matches a paren-less arrow with a single parameter: onChange={e => {}}', () => {
      expect(types('<input onChange={e => {}} />')).toEqual(['EMPTY_HANDLER']);
    });

    it('matches a paren-less, underscore-prefixed parameter: onChange={_e => {}}', () => {
      expect(types('<input onChange={_e => {}} />')).toEqual(['EMPTY_HANDLER']);
    });

    it('matches a paren-less async arrow: onSave={async e => {}}', () => {
      expect(types('<Form onSave={async e => {}} />')).toEqual(['EMPTY_HANDLER']);
    });

    it('matches an arrow whose body is an empty return statement: onClick={() => { return; }}', () => {
      expect(types('<button onClick={() => { return; }} />')).toEqual(['EMPTY_HANDLER']);
    });

    it('matches a lodash-style noop reference: onClick={_.noop}', () => {
      expect(types('<button onClick={_.noop} />')).toEqual(['EMPTY_HANDLER']);
    });

    it('matches an uppercase NOOP reference: onClick={NOOP}', () => {
      expect(types('<button onClick={NOOP} />')).toEqual(['EMPTY_HANDLER']);
    });

    it('does NOT match a destructuring default — { onClose = () => {} }', () => {
      expect(types('function Modal({ onClose = () => {} }) { return onClose; }')).toEqual([]);
    });
  });

  describe('COMING_SOON shapes', () => {
    it('matches a plain space separator, case-insensitive', () => {
      expect(types('<p>Coming Soon</p>')).toEqual(['COMING_SOON']);
    });

    it('matches a hyphen separator', () => {
      expect(types('<p>coming-soon</p>')).toEqual(['COMING_SOON']);
    });

    it('matches a run of whitespace (multiple spaces / newline) as the separator', () => {
      expect(types('<p>coming  \n  soon</p>')).toEqual(['COMING_SOON']);
    });

    it('does NOT match a comment mentioning the phrase (stripped before scanning)', () => {
      expect(types('// this used to say coming soon\nconst x = 1;')).toEqual([]);
    });
  });

  describe('mutation: an edit unrelated to the violation must not change the result', () => {
    it('adding an unrelated line above a violation does not change what is detected', () => {
      const base = '<button onClick={() => {}} />';
      const mutated = '// an unrelated comment line\nconst unrelated = 1;\n' + base;

      const baseResult = scan(base);
      const mutatedResult = scan(mutated);

      expect(mutatedResult.map((v) => v.type)).toEqual(baseResult.map((v) => v.type));
      // The line number DOES shift (proving the mutation is real and the
      // scanner isn't blind to it) — it's the ratchet identity (type+path,
      // asserted above) that must stay stable, not the line.
      expect(mutatedResult[0].line).toBeGreaterThan(baseResult[0].line);
    });

    it('renaming an unrelated identifier elsewhere does not change what is detected', () => {
      const base = 'const foo = 1;\n<button onClick={() => {}} />';
      const mutated = 'const somethingElseEntirely = 1;\n<button onClick={() => {}} />';

      expect(scan(mutated).map((v) => v.type)).toEqual(scan(base).map((v) => v.type));
    });
  });
});
