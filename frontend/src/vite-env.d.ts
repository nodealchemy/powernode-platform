/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_API_BASE_URL: string
  readonly VITE_WS_BASE_URL: string
  readonly VITE_BEHIND_PROXY: string
  readonly VITE_PROXY_HOST: string
  readonly VITE_PROXY_PROTOCOL: string
  // Add more env variables as needed
  
  // Keep compatibility with REACT_APP_ prefixed variables
  readonly REACT_APP_API_BASE_URL: string
  readonly REACT_APP_WS_BASE_URL: string
  readonly REACT_APP_AUTO_DETECT_BACKEND: string
  readonly REACT_APP_VERSION: string
  readonly REACT_APP_BEHIND_PROXY: string
}

interface ImportMeta {
  readonly env: ImportMetaEnv
}

// Extension build flags injected by Vite define
declare const __EXTENSIONS__: string[];

/** Build identity baked in by vite.config.ts (resolveBuildInfo). */
declare const __BUILD_INFO__: {
  version: string;
  sha: string | null;
  short_sha: string | null;
  branch: string;
  tag: string | null;
  release: boolean;
  built_at: string | null;
  source: string;
};
declare const __DISABLED_EXTENSIONS__: string[];

// Extension module declarations — TS types for extension modules resolved by Vite alias.
// Wildcard declaration covers all @ext/* imports so TypeScript doesn't try to
// resolve into extension source files (which have no node_modules of their own).
// Vite's Rollup build will catch any missing modules at build time.
declare module '@ext/*' {
  const value: any;
  export default value;
  export = value;
}