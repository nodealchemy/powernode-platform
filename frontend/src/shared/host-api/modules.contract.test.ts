import { execSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import path from 'node:path';
import { CORE_UI_API_VERSION, HOST_EXPOSED_IDS } from './modules';
import * as apiClientModule from '@/shared/services/apiClient';

/**
 * Guards the core<->extension coupling contract.
 *
 * modules.ts is consumed two ways: the extension build marks every id EXTERNAL
 * (a STRING ARRAY matched against the literal import id — there is deliberately
 * no `@/` alias), and core emits a re-export chunk per id for the runtime import
 * map. So an `@/…` id an extension imports but that is ABSENT here is not a
 * warning — Rollup tries to resolve it, cannot, and the extension build dies.
 *
 * That is exactly what happened: extension commit b1c9c48f (2026-08-06) added
 * `@/shared/components/charts` to two files without adding the id here, and
 * every powernode-extension-system build failed for three days with
 *
 *   [vite] Rollup failed to resolve import "@/shared/components/charts"
 *
 * The file header prescribes catching this with a manual grep. Nobody runs a
 * manual grep. This is that grep, mechanized — and it found a SECOND missing id
 * (`@/shared/utils/workflowLayout`) that would have broken the very next build
 * after charts was fixed.
 */
describe('host UI API contract', () => {
  const repoRoot = path.resolve(__dirname, '../../../..');
  const extRoot = path.join(repoRoot, 'extensions');

  // ONLY extensions with a dedicated-module build (vite.config.build.ts) are
  // bound by this contract — those are the ones whose `@/…` imports are marked
  // external and must resolve through the runtime import map. Extensions
  // without one (marketing, supply-chain) are bundled with core and their `@/`
  // imports resolve through core's ordinary alias, so listing them here would
  // be a false positive that blocks CI for a non-problem.
  //
  // Test files are excluded: the dedicated build's entry is src/register.ts +
  // src/ext.css, so specs are never in the Rollup graph.
  const importedIds = (): string[] => {
    if (!existsSync(extRoot)) return [];
    let out = '';
    try {
      out = execSync(
        `for cfg in ${JSON.stringify(extRoot)}/*/frontend/vite.config.build.ts; do ` +
          `  [ -e "$cfg" ] || continue; ` +
          `  src="$(dirname "$cfg")/src"; [ -d "$src" ] || continue; ` +
          `  grep -rhoE "from '@/[^']+'" "$src" --include=*.ts --include=*.tsx ` +
          `    | grep -vE "\\.(test|spec)\\." || true; ` +
          `done`,
        { encoding: 'utf-8', maxBuffer: 8 * 1024 * 1024, shell: '/bin/bash' },
      );
    } catch {
      return [];
    }
    const ids = out
      .split('\n')
      .map((l) => l.trim())
      .filter(Boolean)
      .map((l) => l.replace(/^from '/, '').replace(/'$/, ''));
    return [...new Set(ids)].sort();
  };

  it('exposes every @/ module the extension frontends actually import', () => {
    const used = importedIds();
    if (used.length === 0) {
      // No extension frontends checked out (public clone / core-only build).
      expect(true).toBe(true);
      return;
    }

    const exposed = new Set<string>(HOST_EXPOSED_IDS as readonly string[]);
    const missing = used.filter((id) => !exposed.has(id));

    // Thrown rather than passed as expect()'s 2nd arg: this project runs vitest
    // via globals (no `import from 'vitest'`, matching every other suite here),
    // and the ambient global `expect` has no message overload.
    if (missing.length > 0) {
      throw new Error(
        `These @/ ids are imported by an extension frontend but are NOT in HOST_APP_IDS.\n` +
          `The extension build will FAIL on each one (Rollup cannot resolve them — there is\n` +
          `no @/ alias by design). Add them to modules.ts, after confirming each resolves to\n` +
          `a real module in core:\n  ${missing.join('\n  ')}\n`,
      );
    }
    expect(missing).toEqual([]);
  });

  it('does not expose ids that no extension imports (keeps the surface minimal)', () => {
    const used = new Set(importedIds());
    if (used.size === 0) {
      expect(true).toBe(true);
      return;
    }

    // Advisory, not fatal: core may intentionally pre-expose a module. Reported
    // so the coupling surface stays a deliberate choice rather than accreting.
    const appIds = (HOST_EXPOSED_IDS as readonly string[]).filter((id) => id.startsWith('@/'));
    const unused = appIds.filter((id) => !used.has(id));
    if (unused.length > 0) {
      // eslint-disable-next-line no-console
      console.warn(
        `[host-api] ${unused.length} exposed @/ id(s) are imported by no extension:\n  ` +
          unused.join('\n  '),
      );
    }
    expect(true).toBe(true);
  });

  it('bumped the host UI API version for the removed apiClient default export', () => {
    // '@/shared/services/apiClient' is an exposed id; a bundle built against 2
    // may still do `import apiClient from ...`, which no longer links. The
    // version gate makes the loader skip it until the extension is rebuilt.
    expect(HOST_EXPOSED_IDS as readonly string[]).toContain('@/shared/services/apiClient');
    expect('default' in apiClientModule).toBe(false);
    expect(CORE_UI_API_VERSION).toBeGreaterThanOrEqual(3);
  });

  it('bumped the host UI API version for the ProviderCredentialForm test seam', () => {
    // '@/features/onboarding/ProviderCredentialForm' no longer accepts
    // testEndpoint (a bundle built against 3 passes it and gets no Test
    // button), and '@/shared/services/featureRegistry' gained
    // registerProviderCategoryHandlers, which such a bundle never calls.
    expect(HOST_EXPOSED_IDS as readonly string[]).toContain('@/features/onboarding/ProviderCredentialForm');
    expect(CORE_UI_API_VERSION).toBeGreaterThanOrEqual(4);
  });

  it('bumped the host UI API version for public route roles', () => {
    // '@/shared/services/featureRegistry' gained FeatureRoute.role and
    // getPublicRoutePath: core's public pages link to the 'pricing' role, so a
    // bundle built against 4 that registers no role leaves those links absent.
    expect(HOST_EXPOSED_IDS as readonly string[]).toContain('@/shared/services/featureRegistry');
    expect(CORE_UI_API_VERSION).toBeGreaterThanOrEqual(5);
  });

  it('bumped the host UI API version for the moved deployment wizard card', () => {
    // '@/features/ai/provisioning/PlatformDeploymentWizardCard' left core (the
    // card now lives with the routes it calls); a bundle built against 5
    // still imports it. featureRegistry also gained mention sources.
    expect(HOST_EXPOSED_IDS as readonly string[]).not.toContain(
      '@/features/ai/provisioning/PlatformDeploymentWizardCard'
    );
    expect(CORE_UI_API_VERSION).toBeGreaterThanOrEqual(6);
  });

  it('bumped the host UI API version for the core intervention-policy panel seam', () => {
    // The System extension's own policy modal (and the extension routes it
    // called) is gone: it now embeds core's panel, exposed here, and
    // presents its domains through featureRegistry.registerPolicyDomains. A
    // bundle built against 6 still renders the deleted modal against routes
    // that no longer exist, so the loader skips it until it is rebuilt.
    expect(HOST_EXPOSED_IDS as readonly string[]).toContain(
      '@/features/ai/autonomy/components/InterventionPoliciesPanel'
    );
    expect(CORE_UI_API_VERSION).toBeGreaterThanOrEqual(7);
  });
});
