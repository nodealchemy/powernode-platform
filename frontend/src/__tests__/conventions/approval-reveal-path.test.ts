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
 *   - no other source file (core or public extension) posts to
 *     /ai/autonomy/approvals, and
 *   - in approvalsApi.ts, every such post is followed by takeRevealedResult on
 *     its response before the function returns (reject is posted by a separate
 *     function and carries no reveal, so it is exempt by path).
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

// A post whose first argument starts with the approvals path, verb resolved or
// interpolated (`/${decision}`).
// eslint-disable-next-line security/detect-unsafe-regex -- runs over repo source in a test, never user input
const APPROVALS_POST = /\bpost\s*(?:<[\s\S]*?>)?\s*\(\s*[`'"]\/ai\/autonomy\/approvals\/\$\{[^}]+\}\/(approve|\$\{[^}]+\})/g;

describe('approve posts go through the revealable-result path (offer 01a0d711)', () => {
  const files = [FRONTEND_SRC, ...publicExtensionSrcDirs()].flatMap((dir) => walk(dir));
  const rel = (f: string) => relative(REPO_ROOT, f).split(sep).join('/');

  it('only approvalsApi.ts posts to the approvals endpoint', () => {
    const posters = files.filter((f) => [...readFileSync(f, 'utf8').matchAll(APPROVALS_POST)].length > 0).map(rel);
    expect(posters).toEqual([APPROVALS_API]);
  });

  it('every approve-capable post in approvalsApi.ts hands its response to takeRevealedResult', () => {
    const text = readFileSync(join(REPO_ROOT, APPROVALS_API), 'utf8');
    const posts = [...text.matchAll(APPROVALS_POST)];
    expect(posts.length).toBe(2); // decideApprovalRequest (/${decision}) and useApproveAction (/approve)

    for (const post of posts) {
      const after = text.slice(post.index ?? 0);
      const nextReturn = after.indexOf('return ');
      expect(nextReturn).toBeGreaterThan(-1);
      expect(after.slice(0, nextReturn + 80)).toMatch(/takeRevealedResult\(\s*response\.data/);
    }
  });
});
