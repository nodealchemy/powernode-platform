import { readFileSync, readdirSync } from 'fs';
import { join } from 'path';

/**
 * Theme convention guard.
 *
 * Dark mode is driven by redefining the `--color-*` CSS variables under the
 * `.dark` class on <html> (ThemeContext applies the class; themes.css `.dark{}`
 * redefines every token). Theme-token utilities (`bg-theme-*`, `text-theme-*`,
 * `border-theme*`, …) therefore already resolve to the correct value in BOTH
 * light and dark with no variant needed.
 *
 * A `dark:` variant whose value is IDENTICAL to the base class it sits next to
 * (e.g. `text-theme-primary dark:text-theme-primary`) is a pure no-op: the
 * `dark:` gate re-applies the exact token the base already applied. This guard
 * fails on those redundant pairs. It intentionally does NOT flag
 * `bg-theme-a dark:bg-theme-b` (differing tokens) or opacity bumps
 * (`bg-theme-x/10 dark:bg-theme-x/20`) — those express a deliberate per-mode
 * difference and are legitimate.
 */

const SRC_ROOT = join(__dirname, '..', '..');
const TOKEN = '(?:bg|text|border|ring|divide|from|to)-theme[A-Za-z0-9/_-]*';
// "<token> dark:<token>" where both tokens are identical → no-op
const PAIR = new RegExp(`(?<![A-Za-z0-9/_:-])(${TOKEN})\\s+dark:(${TOKEN})`, 'g');

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

describe('theme convention: no redundant dark: variants on theme tokens', () => {
  it('has zero identical "X dark:X" theme-token pairs (pure no-ops)', () => {
    const violations: string[] = [];
    for (const file of sourceFiles(SRC_ROOT)) {
      const text = readFileSync(file, 'utf8');
      for (const m of text.matchAll(PAIR)) {
        if (m[1] === m[2]) {
          const rel = file.slice(file.indexOf('/src/') + 1);
          violations.push(`${rel}: "${m[1]} dark:${m[2]}"`);
        }
      }
    }
    expect(violations).toEqual([]);
  });
});
