/**
 * Canonical environment-variable reader for the frontend.
 *
 * Vite exposes build-time config on `import.meta.env`, but Jest/Babel transform
 * this module to CommonJS, where the `import.meta` *syntax* is a hard parse
 * error ("Cannot use import.meta outside a module"). So we read it via dynamic
 * `globalThis`/`window` access (never the literal `import.meta` token), exactly
 * mirroring the pattern the core API client (`@/shared/services/api.ts`) has
 * shipped with. Centralised here so there is ONE tested implementation instead
 * of copies scattered across services.
 */

interface EnvBag {
  [key: string]: string | undefined;
}

interface GlobalWithImportMeta {
  import?: { meta?: { env?: EnvBag } };
}

/**
 * Resolve Vite's `import.meta.env` bag via dynamic access (so this module is
 * parseable under Jest). Returns `undefined` when not running under Vite.
 */
function viteEnv(): EnvBag | undefined {
  const fromGlobal = (globalThis as unknown as GlobalWithImportMeta).import?.meta;
  const fromWindow =
    typeof window !== 'undefined'
      ? (window as unknown as GlobalWithImportMeta).import?.meta
      : undefined;
  return (fromGlobal ?? fromWindow)?.env;
}

/**
 * Read an environment variable with Vite / CRA / Jest compatibility:
 * - In the Jest test environment, from `process.env[craKey]`.
 * - Under Vite, from `import.meta.env[viteKey]`, then `[craKey]`.
 * - Otherwise (CRA/SSR), from `process.env[craKey]`.
 * Falls back to `defaultValue`. Behaviour is identical to the original inline
 * reader in `@/shared/services/api.ts`, which this module supersedes.
 */
export function getEnvVar(viteKey: string, craKey: string, defaultValue = ''): string {
  if (typeof process !== 'undefined' && process.env.NODE_ENV === 'test') {
    return process.env[craKey] || defaultValue;
  }
  const env = viteEnv();
  if (env) {
    return env[viteKey] || env[craKey] || defaultValue;
  }
  return (typeof process !== 'undefined' ? process.env[craKey] : undefined) || defaultValue;
}

/**
 * The frontend application version, injected from the VERSION file at build
 * time: `VITE_APP_VERSION` → `npm_package_version` → a dev default.
 */
export function getAppVersion(): string {
  return getEnvVar('VITE_APP_VERSION', 'npm_package_version', '0.0.1-dev');
}

/** Build identity of this bundle. Mirrors Powernode::Version's BUILD_INFO. */
export interface BuildInfo {
  version: string;
  sha: string | null;
  short_sha: string | null;
  branch: string;
  tag: string | null;
  release: boolean;
  built_at: string | null;
  source: string;
}

/**
 * The bundle's build identity, from the `__BUILD_INFO__` define that
 * vite.config.ts bakes in (the module build feeds it POWERNODE_BUILD_INFO_JSON;
 * a local build uses the checkout's git sha). Under Jest, or in any bundle
 * built without the define, there is no identity: the app version with
 * `release: false` and no sha, which the display contract renders as
 * `<version>-dev`.
 */
export function getBuildInfo(): BuildInfo {
  const fallback: BuildInfo = {
    version: getAppVersion(), sha: null, short_sha: null, branch: 'unknown',
    tag: null, release: false, built_at: null, source: 'local',
  };
  if (typeof __BUILD_INFO__ === 'undefined' || !__BUILD_INFO__) return fallback;
  return { ...fallback, ...__BUILD_INFO__, version: __BUILD_INFO__.version || fallback.version };
}
