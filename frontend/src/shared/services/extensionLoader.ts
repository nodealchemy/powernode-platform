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

// Build-time glob discovery of extension register modules and manifests
const registerModules = import.meta.glob<ExtensionModule>(
  '../../../extensions/*/frontend/src/register.ts',
  { eager: false }
);

const manifestModules = import.meta.glob<{ default: ExtensionManifest }>(
  '../../../extensions/*/extension.json',
  { eager: true }
);

const loaded = new Map<string, ExtensionManifest>();

/**
 * Discover and load all extensions found at build time.
 * Each extension must export a `register()` function from `frontend/src/register.ts`.
 */
export async function loadAllExtensions(): Promise<void> {
  for (const [modulePath, loader] of Object.entries(registerModules)) {
    // Extract slug from path: ../../../extensions/{slug}/frontend/src/register.ts
    const parts = modulePath.split('/');
    const slug = parts[4];

    try {
      const mod = await loader();
      mod.register();

      // Load manifest if available
      const manifestPath = `../../../extensions/${slug}/extension.json`;
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

/** Check if a specific extension is loaded */
export function isExtensionLoaded(slug: string): boolean {
  return loaded.has(slug);
}

/** Get all loaded extension slugs */
export function getLoadedExtensions(): string[] {
  return Array.from(loaded.keys());
}

/** Get manifest for a loaded extension */
export function getExtensionManifest(slug: string): ExtensionManifest | undefined {
  return loaded.get(slug);
}
