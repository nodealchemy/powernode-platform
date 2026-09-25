import { execFileSync } from 'child_process';
import { join } from 'path';

/**
 * Jest face of the core-frontend extension-route guard
 * (scripts/checks/core-extension-route-literals.rb, also run by
 * scripts/pattern-validation.sh). Core names no extension route: extension
 * behaviour is reached through featureRegistry seams. The script owns the
 * matcher and the per-file allowlist; this runs its fixture self-test (so a
 * broken matcher cannot pass as a clean tree) and then the scan.
 */
const REPO_ROOT = join(__dirname, '..', '..', '..', '..');
const SCRIPT = join(REPO_ROOT, 'scripts', 'checks', 'core-extension-route-literals.rb');

const run = (...args: string[]) =>
  execFileSync('ruby', [SCRIPT, ...args], { cwd: REPO_ROOT, encoding: 'utf-8' });

describe('convention: core frontend names no extension route', () => {
  it('the guard catches what its fixtures say it must, and nothing else', () => {
    expect(run('--self-test').trim()).toBe('self-test PASS');
  });

  it('finds no extension-route literal outside the explicit allowlist', () => {
    expect(run('--list').trim()).toBe('');
  });
});
