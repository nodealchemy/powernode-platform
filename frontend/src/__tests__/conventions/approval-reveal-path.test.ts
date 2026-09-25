import { readFileSync, readdirSync, statSync } from 'fs';
import { join, relative, sep } from 'path';

/**
 * Offer 01a0d711 guard: every POST to the autonomy approve endpoint goes
 * through the revealable-result path.
 *
 * The server empties an approval's one-shot `revealed_result` slot with the
 * approve response itself, so a caller that posts the approve and ignores the
 * body destroys minted material nobody saw (the notification panel did this).
 * The only sanctioned door is features/ai/approvals/api/approvalsApi.ts, whose
 * approve posts each hand the body to takeRevealedResult. This test holds that:
 *   - no other source file (core or public extension) both names the
 *     /ai/autonomy/approvals path (in a call, a helper constant or a
 *     concatenation) and makes a post() call, and
 *   - in approvalsApi.ts, every approve-capable post's function RETURNS the
 *     takeRevealedResult result, not the raw body (reject carries no reveal,
 *     so it is exempt by path).
 * Extensions are discovered by walking extensions/, never named.
 */

const FRONTEND_SRC = join(__dirname, '..', '..');
const REPO_ROOT = join(FRONTEND_SRC, '..', '..');
const EXTENSIONS_ROOT = join(REPO_ROOT, 'extensions');
const APPROVALS_API = 'frontend/src/features/ai/approvals/api/approvalsApi.ts';

function publicExtensionSrcDirs(): string[] {
  try {
    return readdirSync(EXTENSIONS_ROOT, { withFileTypes: true })
      .filter((e) => e.isDirectory() && e.name !== 'private')
      .map((e) => join(EXTENSIONS_ROOT, e.name, 'frontend', 'src'))
      .filter((dir) => {
        try {
          return statSync(dir).isDirectory();
        } catch {
          return false;
        }
      });
  } catch {
    return [];
  }
}

function walk(dir: string, acc: string[] = []): string[] {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    if (entry.name === 'node_modules' || entry.name.startsWith('.') || entry.name === '__tests__') continue;
    const full = join(dir, entry.name);
    if (entry.isDirectory()) walk(full, acc);
    else if (/\.(tsx?)$/.test(entry.name) && !/\.(test|spec)\.tsx?$/.test(entry.name) && !/\.d\.ts$/.test(entry.name)) acc.push(full);
  }
  return acc;
}

// Strips line and block comments, string-aware (as in
// api-client-conventions.test.ts), so a path named in a doc comment is not
// read as a use.
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

// The approvals path as the START of any string or template literal: a direct
// argument, a helper constant or arrow (`const ENDPOINT = (id) => \`/ai/...\``)
// or the head of a concatenation (`'/ai/autonomy/approvals/' + id`). The app
// route `/app/ai/agents/autonomy/approvals` does not match.
const APPROVALS_PATH = /['"`]\/ai\/autonomy\/approvals\b/;
// eslint-disable-next-line security/detect-unsafe-regex -- runs over repo source in a test, never user input
const POST_CALL = /\bpost\s*(?:<[^()]*?>)?\s*\(/g;

describe('approve posts go through the revealable-result path (offer 01a0d711)', () => {
  const files = [FRONTEND_SRC, ...publicExtensionSrcDirs()].flatMap((dir) => walk(dir));
  const rel = (f: string) => relative(REPO_ROOT, f).split(sep).join('/');

  it('only approvalsApi.ts both names the approvals path and posts', () => {
    const posters = files
      .filter((f) => {
        const text = stripComments(readFileSync(f, 'utf8'));
        return APPROVALS_PATH.test(text) && [...text.matchAll(POST_CALL)].length > 0;
      })
      .map(rel);
    expect(posters).toEqual([APPROVALS_API]);
  });

  it('every approve-capable post in approvalsApi.ts returns what takeRevealedResult hands back', () => {
    const text = stripComments(readFileSync(join(REPO_ROOT, APPROVALS_API), 'utf8'));
    // Each post, with the text of its first argument (up to the first comma).
    const posts = [...text.matchAll(POST_CALL)].map((m) => {
      const start = (m.index ?? 0) + m[0].length;
      return { start, target: text.slice(start, text.indexOf(',', start)) };
    });
    // Reject carries no reveal; every other post (literal /approve or an
    // interpolated decision) can.
    const approveCapable = posts.filter((p) => !/\/reject[`'"]/.test(p.target));
    expect(approveCapable.map((p) => p.target.trim())).toEqual([
      '`/ai/autonomy/approvals/${id}/${decision}`',
      '`/ai/autonomy/approvals/${id}/approve`',
    ]);

    for (const post of approveCapable) {
      const after = text.slice(post.start);
      const nextReturn = after.search(/\breturn\b/);
      expect(nextReturn).toBeGreaterThan(-1);
      // The function hands back the helper's result, not the raw body: a
      // `takeRevealedResult(...); return response.data?.data` would put the
      // plaintext back into the caller's state.
      expect(after.slice(nextReturn)).toMatch(/^return\s+\(?\s*takeRevealedResult\(\s*response\.data/);
    }
  });
});
