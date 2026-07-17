import { logger } from '@/shared/utils/logger';
import apiClient from '@/shared/services/apiClient';
import { CORE_UI_API_VERSION } from '@/shared/host-api/modules';

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

// ---------------------------------------------------------------------------
// Runtime extension loading (dedicated-module frontends)
// ---------------------------------------------------------------------------
// Extensions whose frontend is NOT baked into this build are served as
// standalone ESM bundles (composed onto the host at deploy time) and linked to
// core at runtime via the injected import map (see vite.config.ts + host-api/
// modules.ts). This path fetches the set of enabled extensions, then loads and
// registers each one that the eager glob path above did not already bake in.

/**
 * Per-extension manifest emitted at compose-time and served as a static asset
 * at `/extensions/<slug>/manifest.json`. Describes how to load the extension's
 * dedicated frontend bundle at runtime.
 */
interface RuntimeExtensionManifest {
  slug: string;
  version: string;
  /** Host UI API version the bundle was built against — must match core. */
  coreUiApi: number;
  /** URL of the extension's ESM entry chunk (imported dynamically). */
  entry: string;
  /** URLs of stylesheet(s) to inject before the module renders. */
  css?: string[];
}

/** Shape of one row from GET /api/v1/extensions/ui. */
interface RuntimeExtensionListItem {
  slug: string;
  version?: string;
  enabled: boolean;
}

/** Injected CSS hrefs, so a re-entrant call never double-injects a <link>. */
const injectedCss = new Set<string>();

function injectExtensionCss(base: string, hrefs: string[] | undefined): void {
  if (!hrefs) return;
  for (const href of hrefs) {
    // Manifest hrefs are relative to the extension's dist root; make them
    // absolute (/extensions/<slug>/…) so the <link> never resolves against
    // the current SPA route (which would 404 to index.html).
    const url = base + href;
    if (injectedCss.has(url)) continue;
    injectedCss.add(url);
    const link = document.createElement('link');
    link.rel = 'stylesheet';
    link.href = url;
    document.head.appendChild(link);
  }
}

/**
 * Discover enabled extensions and load any whose frontend was not baked into
 * this build. For each enabled, not-already-loaded extension it fetches
 * `/extensions/<slug>/manifest.json`, verifies the `coreUiApi` contract,
 * injects the module's CSS, dynamically imports its entry, and calls
 * `register()`.
 *
 * Every extension is isolated in its own try/catch: a missing bundle resolves
 * to the SPA history fallback (index.html), so the manifest parse or the entry
 * import throws — that extension is logged and skipped, never blocking the
 * others or the app boot. Deduped against the eager glob path via the shared
 * `loaded` map so a baked-in extension is never registered twice.
 */
export async function loadRuntimeExtensions(): Promise<void> {
  let items: RuntimeExtensionListItem[] = [];
  try {
    // Discovery goes through apiClient so the configured API base is honored.
    // Endpoint is unauthenticated; no token is required.
    const res = await apiClient.get('/extensions/ui');
    const envelope = res.data ?? {};
    items = envelope.data?.extensions ?? envelope.extensions ?? [];
  } catch (err) {
    logger.warn('Runtime extension discovery failed; skipping runtime extensions', {
      error: err instanceof Error ? err.message : String(err),
    });
    return;
  }

  for (const item of items) {
    const slug = item?.slug;
    if (!slug || !item.enabled) continue;
    // Dedupe with the eager glob path: if baked in, register() already ran.
    if (loaded.has(slug)) {
      logger.debug(`Extension "${slug}" already loaded (baked) — skipping runtime load`);
      continue;
    }

    try {
      // Static asset at the site root (NOT under the API base) — raw fetch.
      const manifestRes = await fetch(`/extensions/${slug}/manifest.json`, {
        headers: { Accept: 'application/json' },
      });
      if (!manifestRes.ok) {
        logger.warn(`Extension "${slug}": manifest fetch failed (HTTP ${manifestRes.status}) — skipping`);
        continue;
      }
      // A missing manifest may resolve to index.html (200 text/html); parsing
      // that as JSON throws and is caught below — safe.
      const manifest = (await manifestRes.json()) as RuntimeExtensionManifest;

      if (manifest.coreUiApi !== CORE_UI_API_VERSION) {
        logger.warn(
          `Extension "${slug}": coreUiApi ${manifest.coreUiApi} != host ${CORE_UI_API_VERSION} — skipping`,
        );
        continue;
      }
      if (!manifest.entry) {
        logger.warn(`Extension "${slug}": manifest has no entry — skipping`);
        continue;
      }

      // Manifest asset paths are RELATIVE to the extension's dist root, which
      // is served at /extensions/<slug>/. Resolve them to an ABSOLUTE URL path
      // so the browser loads the entry as a URL — a bare specifier like
      // "assets/register-x.js" would instead be routed through the host import
      // map (which only maps the HOST_EXPOSED_IDS) and throw "failed to resolve
      // module specifier", silently skipping the extension (no menu).
      const base = `/extensions/${slug}/`;
      injectExtensionCss(base, manifest.css);

      // @vite-ignore: entry is a runtime URL, not a build-time-analyzable path.
      const mod = (await import(/* @vite-ignore */ base + manifest.entry)) as ExtensionModule;
      if (typeof mod.register !== 'function') {
        logger.warn(`Extension "${slug}": module exports no register() — skipping`);
        continue;
      }
      mod.register();
      loaded.set(slug, {
        name: slug,
        slug,
        version: manifest.version ?? 'unknown',
        capabilities: [],
        components: { frontend: true },
      });
      logger.info(`Extension "${slug}" loaded at runtime`);
    } catch (err) {
      // One extension's failure must never block the others or app boot.
      logger.error(`Failed to load runtime extension "${slug}":`, err);
    }
  }
}
