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
