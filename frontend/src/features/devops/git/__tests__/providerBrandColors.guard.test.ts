import { readFileSync, readdirSync } from 'fs';
import { join } from 'path';

/**
 * Duplication guard for git-provider brand colors.
 *
 * The four git-provider brand background colors (GitHub/GitLab/Gitea/Bitbucket)
 * are fixed vendor hexes — intentionally NOT theme-tokenized. They must have a
 * single source of truth so a hex fix or a new provider lands in exactly one
 * place. This guard fails if any `bg-[#hex]` brand literal appears in more than
 * one source file (i.e. is duplicated rather than imported from the shared
 * constant).
 */

const SRC_ROOT = join(__dirname, '..', '..', '..', '..');
const BRAND_BG_LITERALS = [
  'bg-[#24292f]', // github
  'bg-[#FC6D26]', // gitlab
  'bg-[#609926]', // gitea
  'bg-[#0052CC]', // bitbucket
];

function sourceFiles(dir: string, acc: string[] = []): string[] {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const full = join(dir, entry.name);
    if (entry.isDirectory()) {
      if (entry.name === 'node_modules' || entry.name === '__mocks__') continue;
      sourceFiles(full, acc);
    } else if (/\.(ts|tsx)$/.test(entry.name) && !/\.(test|spec)\.(ts|tsx)$/.test(entry.name)) {
      acc.push(full);
    }
  }
  return acc;
}

describe('git provider brand colors: single source of truth', () => {
  const files = sourceFiles(SRC_ROOT);

  it.each(BRAND_BG_LITERALS)('brand literal %s is defined in at most one file', (literal) => {
    const owners = files
      .filter((f) => readFileSync(f, 'utf8').includes(literal))
      .map((f) => f.slice(f.indexOf('/src/') + 1));
    if (owners.length > 1) {
      throw new Error(`Brand literal ${literal} is duplicated across:\n  ${owners.join('\n  ')}`);
    }
    expect(owners.length).toBeLessThanOrEqual(1);
  });
});
