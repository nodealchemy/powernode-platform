import { logger } from '@/shared/utils/logger';

interface ExtensionModule {
  register: () => void;
}

interface ExtensionManifest {
  name: string;
  slug: string;
  version: string;
  capabilities: string[];
  components: {
    server?: boolean;
    frontend?: boolean;
    worker?: boolean;
  };
}

// Build-time glob discovery of extension register modules + manifests.
// Path goes up 4 levels: services/ → shared/ → src/ → frontend/ → project root.
//
// `eager: true` for both globs means Vite inlines the modules into the main
// bundle at build time, so they're available synchronously at import time.
// This is critical for routing: the marketing extension's register()
// populates featureRegistry with public routes like /features and /pricing.
// If extensions registered asynchronously (eager: false + dynamic import in
// useEffect), App.tsx's first render would see an empty registry, and the
// catch-all `*` route would redirect /features → / → /welcome before the
// async register finished — breaking every direct/social link to /features.
// Synchronous module-load registration eliminates that race entirely.
// Extensions live flat under extensions/<slug>; private/custom ones under
// extensions/private/<slug> (gitignored). Both locations are globbed here.
const registerModules = import.meta.glob<ExtensionModule>(
  [
    '../../../../extensions/*/frontend/src/register.ts',
    '../../../../extensions/private/*/frontend/src/register.ts',
  ],
  { eager: true }
);

const manifestModules = import.meta.glob<{ default: ExtensionManifest }>(
  [
    '../../../../extensions/*/extension.json',
    '../../../../extensions/private/*/extension.json',
  ],
  { eager: true }
);

const loaded = new Map<string, ExtensionManifest>();
let extensionsRegistered = false;

/**
 * Iterates all discovered extension register modules and invokes register()
 * for each. Runs synchronously at module import time so featureRegistry is
 * populated before App.tsx renders.
 *
 * Slugs listed in `__DISABLED_EXTENSIONS__` (build-time constant from
 * config/extensions_state.json) are skipped. The corresponding register
 * modules are also stubbed at build time by the `disabled-extensions-stub`
 * Vite plugin, so calling them is safe — the skip here is defense in depth
 * and keeps the `loaded` map honest.
 *
 * Idempotent — guarded against re-execution.
 */
function registerAllExtensions(): void {
  if (extensionsRegistered) return;
  extensionsRegistered = true;

  const disabled = typeof __DISABLED_EXTENSIONS__ !== 'undefined' ? __DISABLED_EXTENSIONS__ : [];

  for (const [modulePath, mod] of Object.entries(registerModules)) {
    // Slug is the directory immediately before "frontend" — robust to the extra
    // nesting level for private extensions (extensions/private/<slug>/frontend/…).
    const parts = modulePath.split('/');
    const slug = parts[parts.indexOf('frontend') - 1];

    if (disabled.includes(slug)) {
      logger.info(`Extension "${slug}" is disabled — skipping`);
      continue;
    }

    try {
      mod.register();

      // Load manifest if available (derive from the register path so it works
      // for both flat and extensions/private/<slug> layouts).
      const manifestPath = modulePath.replace('/frontend/src/register.ts', '/extension.json');
      const manifest = manifestModules[manifestPath]?.default;
      if (manifest) {
        loaded.set(slug, manifest);
      } else {
        loaded.set(slug, {
          name: slug,
          slug,
          version: 'unknown',
          capabilities: [],
          components: { frontend: true },
        });
      }

      logger.info(`Extension "${slug}" loaded successfully`);
    } catch (err) {
      logger.error(`Failed to load extension "${slug}":`, err);
    }
  }
}

// Register at module import time — before any consumer (App.tsx) renders.
// This is the line that fixes the catch-all-redirect race.
registerAllExtensions();

/**
 * Backward-compatible no-op kept so existing callers that do
 * `await loadAllExtensions()` continue to compile. The actual registration
 * happens at module load above (see {@link registerAllExtensions}).
 */
export async function loadAllExtensions(): Promise<void> {
  // No-op: extensions are registered synchronously at module import.
}
