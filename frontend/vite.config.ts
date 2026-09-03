import { defineConfig, loadEnv, type Plugin, type InputOptions } from 'vite';
import react from '@vitejs/plugin-react';
import viteTsconfigPaths from 'vite-tsconfig-paths';
import svgr from 'vite-plugin-svgr';
import path from 'path';
import fs from 'fs';
import packageJson from './package.json';
import { createRequire } from 'module';
import { execSync } from 'child_process';
import { HOST_EXPOSED_IDS, hostChunkName } from './src/shared/host-api/modules';

// Require bound to the frontend package root, used to enumerate the real
// runtime named exports of CommonJS packages (React family) when building their
// host re-export facades (see hostReexportPlugin).
const hostRequire = createRequire(path.join(__dirname, 'package.json'));

// ---------------------------------------------------------------------------
// Host re-export + import-map plugin (runtime extension linking — Phase 1)
// ---------------------------------------------------------------------------
// For each id in HOST_EXPOSED_IDS, emit a stable-named ESM re-export chunk at
// `assets/host/<name>.js` and inject a `<script type="importmap">` mapping the
// bare id to that chunk. Extension bundles (P2) import these ids as EXTERNAL
// bare specifiers; the browser resolves them through the import map to core's
// SINGLE module instance.
//
// CORRECTNESS — no duplication: the re-export chunks are added as additional
// inputs to the SAME Rollup build as the main app, so each source module lives
// in exactly one output chunk (Rollup never duplicates a module across chunks in
// one build). Depending on the module, Rollup either (a) makes the host chunk a
// thin facade that re-exports from the shared chunk holding the real module
// (e.g. host `react` re-exports from the `vendor` chunk), or (b) places the real
// module directly INTO the stably-referenced host chunk and points every core
// consumer at it (this is what happens for `featureRegistry` / `WebSocketManager`
// — verified: their implementation appears in exactly one chunk and all ~90 core
// page chunks import it from there). Either way the singleton is one instance
// shared by core AND extensions. `preserveEntrySignatures: 'allow-extension'`
// keeps each host entry's exports without forcing a copy; `manualChunks` (below)
// pins react/redux/axios to single chunks.
//
// The import map is built from the ACTUAL emitted (content-hashed) filenames in
// `transformIndexHtml`, so host chunks keep normal cache-busting while the map
// still targets them exactly.
const HOST_VIRTUAL_PREFIX = 'virtual:powernode-host:';
const HOST_RESOLVED_PREFIX = '\0' + HOST_VIRTUAL_PREFIX;

function hostReexportPlugin(): Plugin {
  // Guard: sanitized chunk names must be unique or two ids would collide onto
  // one file (silently sharing/overwriting a facade).
  const names = HOST_EXPOSED_IDS.map(hostChunkName);
  if (new Set(names).size !== names.length) {
    throw new Error('[host-reexport] hostChunkName collision among HOST_EXPOSED_IDS');
  }

  // Public base, captured at config-resolve time so import-map URLs honor it.
  let base = '/';

  return {
    name: 'powernode-host-reexport',
    apply: 'build', // dev uses the eager glob path; runtime linking is prod-only
    configResolved(config) {
      base = config.base || '/';
    },
    // Append one virtual entry per exposed id to whatever input Vite resolved
    // (the index.html entry), so they join the single main-app build.
    options(opts: InputOptions): InputOptions {
      const input = opts.input;
      let normalized: Record<string, string>;
      if (typeof input === 'string') {
        normalized = { index: input };
      } else if (Array.isArray(input)) {
        normalized = Object.fromEntries(input.map((f, i) => [`input${i}`, f]));
      } else {
        normalized = { ...(input as Record<string, string>) };
      }
      for (const id of HOST_EXPOSED_IDS) {
        normalized[`host/${hostChunkName(id)}`] = HOST_VIRTUAL_PREFIX + id;
      }
      return { ...opts, input: normalized };
    },
    resolveId(id: string) {
      if (id.startsWith(HOST_VIRTUAL_PREFIX)) return '\0' + id;
      return null;
    },
    async load(id: string) {
      if (!id.startsWith(HOST_RESOLVED_PREFIX)) return null;
      const target = id.slice(HOST_RESOLVED_PREFIX.length);
      const t = JSON.stringify(target);

      // Classify the target so we emit the right re-export form. CommonJS
      // packages (the React family) surface their API as PROPERTIES of the
      // default export (React.useState), not as real ESM named exports — the
      // CJS→ESM interop proxy exposes only `default` + `__moduleExports`, so
      // `export * from 'react'` silently drops `useState`/`useEffect`/… and an
      // extension's `import { useState } from 'react'` would resolve to
      // undefined. Detect that proxy shape and, for it, re-export each real
      // runtime name as property access on the default instead.
      let isCjsInterop = false;
      let hasDefault = false;
      try {
        const resolved = await this.resolve(target, undefined, { skipSelf: true });
        if (resolved && !resolved.external) {
          const info = await this.load({ id: resolved.id });
          const names = Array.isArray(info.exports) ? info.exports : [];
          hasDefault = names.includes('default');
          isCjsInterop = names.includes('__moduleExports');
        }
      } catch {
        // Fall through to the ESM star form (correct for pure-ESM modules).
      }

      if (isCjsInterop) {
        // Enumerate the real named exports from the package at build time and
        // bind each to a property of the default. Snapshot bindings are fine
        // here — React's hook/API references are stable for a module's lifetime.
        let names: string[] = [];
        try {
          const mod = hostRequire(target) as Record<string, unknown>;
          const IDENT = /^[A-Za-z_$][A-Za-z0-9_$]*$/;
          names = Object.keys(mod).filter(
            (n) => n !== 'default' && n !== '__esModule' && n !== '__moduleExports' && IDENT.test(n),
          );
        } catch {
          // If the package can't be required, fall back to default-only below.
        }
        const lines = [`import __def from ${t};`, `export default __def;`];
        if (names.length > 0) {
          lines.push(
            `export const ${names
              .map((n) => `${n} = __def[${JSON.stringify(n)}]`)
              .join(', ')};`,
          );
        }
        return lines.join('\n');
      }

      // ESM path: `export *` carries every named binding (including barrel
      // star re-exports and ESM npm packages), plus the default when present.
      const out = [`export * from ${t};`];
      if (hasDefault) out.push(`export { default } from ${t};`);
      return out.join('\n');
    },
    // Inject the import map at the very start of <head> — it must precede the
    // app's module script (only one import map is allowed, and it must appear
    // before the first module load it governs). Built from the ACTUAL emitted
    // (content-hashed) host chunk filenames so the map targets them exactly
    // while normal cache-busting is preserved.
    transformIndexHtml: {
      order: 'post' as const,
      handler(_html: string, ctx: { bundle?: Record<string, { type: string; name?: string; isEntry?: boolean; fileName: string }> }) {
        const imports: Record<string, string> = {};
        const bundle = ctx.bundle || {};
        const byName = new Map<string, string>();
        for (const out of Object.values(bundle)) {
          if (out.type === 'chunk' && out.isEntry && out.name) byName.set(out.name, out.fileName);
        }
        const missing: string[] = [];
        for (const id of HOST_EXPOSED_IDS) {
          const fileName = byName.get(`host/${hostChunkName(id)}`);
          if (fileName) imports[id] = `${base}${fileName}`;
          else missing.push(id);
        }
        if (missing.length > 0) {
          this.warn(`[host-reexport] no emitted chunk for: ${missing.join(', ')}`);
        }
        return [
          {
            tag: 'script',
            attrs: { type: 'importmap' },
            children: JSON.stringify({ imports }, null, 2),
            injectTo: 'head-prepend' as const,
          },
        ];
      },
    },
  };
}

// Get allowed hosts from cache file or environment
// The cache file is populated by `npm run refresh-proxy` or manually
function getAllowedHosts(): string[] {
  const CACHE_FILE = path.join(__dirname, '.proxy-config-cache.json');

  // Default hosts for local development
  const defaultHosts = ['localhost', '127.0.0.1', '::1'];

  try {
    if (fs.existsSync(CACHE_FILE)) {
      const cacheContent = fs.readFileSync(CACHE_FILE, 'utf8');
      const cache = JSON.parse(cacheContent);

      if (cache.allowedHosts && cache.allowedHosts.length > 0) {
        // Combine defaults with cached hosts, removing duplicates
        return [...new Set([...defaultHosts, ...cache.allowedHosts])];
      }
    }
  } catch {
    // Silently fall back to defaults on any error
  }

  return defaultHosts;
}

// https://vitejs.dev/config/

// Build identity baked into the bundle as __BUILD_INFO__ (see
// src/shared/utils/env.ts#getBuildInfo and versionApi.displayVersion). The
// module build (extensions/system/scripts/module-build/stage15.sh) exports the
// JSON it wrote for the server as POWERNODE_BUILD_INFO_JSON; a local dev build
// falls back to the checkout's own git identity, which is never a release.
function resolveBuildInfo(): Record<string, unknown> {
  const fromBuild = process.env.POWERNODE_BUILD_INFO_JSON;
  if (fromBuild) {
    try {
      const parsed = JSON.parse(fromBuild) as Record<string, unknown>;
      return { version: packageJson.version, ...parsed };
    } catch {
      console.warn('[vite] POWERNODE_BUILD_INFO_JSON is not valid JSON; falling back to git identity');
    }
  }
  const git = (args: string): string | null => {
    try {
      return execSync(`git ${args}`, { stdio: ['ignore', 'pipe', 'ignore'] }).toString().trim() || null;
    } catch {
      return null;
    }
  };
  const sha = git('rev-parse HEAD');
  return {
    version: packageJson.version,
    sha,
    short_sha: sha ? sha.slice(0, 7) : null,
    branch: git('rev-parse --abbrev-ref HEAD') ?? 'unknown',
    tag: null,
    release: false,
    built_at: null,
    source: sha ? 'git' : 'local',
  };
}

export default defineConfig(({ mode }: { mode: string }) => {
  const env = loadEnv(mode, process.cwd(), '');

  // Get allowed hosts from cache or environment
  const allowedHosts = getAllowedHosts();
  const additionalHosts = env.VITE_ALLOWED_HOSTS ? env.VITE_ALLOWED_HOSTS.split(',') : [];

  // Dynamic extension discovery
  const extensionsDir = path.resolve(__dirname, '../extensions');
  const extensionAliases: Record<string, string> = {};
  const discoveredSlugs: string[] = [];

  // Extensions live flat under extensions/<slug>; private/custom ones under
  // extensions/private/<slug> (gitignored). "private" is a grouping dir, never
  // a slug — the slug is always the leaf directory name.
  const extensionDirs: { slug: string; dir: string }[] = [];
  if (fs.existsSync(extensionsDir)) {
    for (const name of fs.readdirSync(extensionsDir)) {
      if (name === 'private') continue;
      extensionDirs.push({ slug: name, dir: path.resolve(extensionsDir, name) });
    }
    const privateDir = path.resolve(extensionsDir, 'private');
    if (fs.existsSync(privateDir)) {
      for (const name of fs.readdirSync(privateDir)) {
        extensionDirs.push({ slug: name, dir: path.resolve(privateDir, name) });
      }
    }
  }
  for (const { slug, dir } of extensionDirs) {
    const manifestPath = path.resolve(dir, 'extension.json');
    const frontendSrc = path.resolve(dir, 'frontend/src');
    if (fs.existsSync(manifestPath) && fs.existsSync(frontendSrc)) {
      extensionAliases[`@ext/${slug}`] = frontendSrc;
      extensionAliases[`@${slug}`] = frontendSrc; // intra-extension imports (e.g. @<slug>/)
      discoveredSlugs.push(slug);
    }
  }

  // Read disabled-extension state at build time. Missing/malformed file => empty list.
  // The state file is written by the Rails admin "Toggle Extension" action.
  const disabledSlugs: string[] = (() => {
    const stateFile = path.resolve(__dirname, '../config/extensions_state.json');
    try {
      if (fs.existsSync(stateFile)) {
        const state = JSON.parse(fs.readFileSync(stateFile, 'utf8'));
        return Array.isArray(state.disabled) ? state.disabled.map(String) : [];
      }
    } catch {
      /* fall through to empty list */
    }
    return [];
  })();

  // Slugs effectively active in this build — drives the __EXTENSIONS__ feature gate.
  const enabledSlugs = discoveredSlugs.filter((s) => !disabledSlugs.includes(s));

  return {
    base: '/',

    plugins: [
      react(),
      viteTsconfigPaths(),
      svgr({
        svgrOptions: {
          icon: true,
        },
      }),
      // Runtime extension linking (Phase 1): emit host re-export chunks +
      // inject the import map. Build-only (dev uses the eager glob path).
      hostReexportPlugin(),
      // When extensions are absent, resolve @ext/* imports to a stub module
      // so Rollup doesn't fail on dead-code dynamic imports (e.g. App.tsx conditionals)
      ...(discoveredSlugs.length === 0 ? [{
        name: 'missing-extensions-stub',
        resolveId(id: string) {
          if (id.startsWith('@ext/')) return '\0ext-stub';
        },
        load(id: string) {
          if (id === '\0ext-stub') return 'export default null;';
        },
      }] : []),
      // When an extension is disabled via config/extensions_state.json, stub
      // every module that lives under its directory (including register.ts and
      // anything imported via @ext/<slug>/* or @<slug>/*). The check covers
      // both pre-resolution alias ids and post-resolution absolute paths so
      // the order against viteTsconfigPaths doesn't matter.
      ...(disabledSlugs.length > 0 ? [{
        name: 'disabled-extensions-stub',
        enforce: 'pre' as const,
        resolveId(id: string) {
          for (const slug of disabledSlugs) {
            // Pre-resolution alias forms
            if (id.startsWith(`@${slug}/`) || id === `@${slug}` ||
                id.startsWith(`@ext/${slug}/`) || id === `@ext/${slug}`) {
              return '\0disabled-ext-stub';
            }
            // Post-resolution absolute or relative path inside the disabled dir
            if (id.includes(`/extensions/${slug}/`) || id.includes(`/extensions/private/${slug}/`)) {
              return '\0disabled-ext-stub';
            }
          }
          return null;
        },
        load(id: string) {
          if (id === '\0disabled-ext-stub') {
            return 'export const register = () => {};\nexport default {};\n';
          }
          return null;
        },
      }] : []),
    ],
    
    resolve: {
      // Resolve ALL packages from core node_modules when processing
      // extension source files (extension dirs have no own node_modules).
      // Derived from package.json so it stays in sync automatically.
      dedupe: Object.keys(packageJson.dependencies || {}),
      alias: {
        '@': path.resolve(__dirname, './src'),
        '@/shared': path.resolve(__dirname, './src/shared'),
        '@/features': path.resolve(__dirname, './src/features'),
        '@/pages': path.resolve(__dirname, './src/pages'),
        '@/assets': path.resolve(__dirname, './src/assets'),
        ...extensionAliases,
      },
    },
    
    server: {
      host: '0.0.0.0',
      port: 3001,
      open: false,
      strictPort: true, // Don't try alternative ports
      
      allowedHosts: [
        ...allowedHosts,
        ...additionalHosts,
        '.host.docker.internal',
      ],

      hmr: true,

      cors: true,

      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, PATCH, OPTIONS',
        'Access-Control-Allow-Headers': 'X-Requested-With, content-type, Authorization',
      },
      
      // API proxy - use 127.0.0.1 to force IPv4 (Rails binds to IPv4)
      proxy: {
        '/.well-known': {
          target: 'http://127.0.0.1:3000',
          changeOrigin: true,
          secure: false,
        },
        '/sitemap.xml': {
          target: 'http://127.0.0.1:3000',
          changeOrigin: true,
          secure: false,
        },
        '/api/v1': {
          target: 'http://127.0.0.1:3000/api/v1',
          changeOrigin: true,
          secure: false,
          ws: true,
          rewrite: (path: string) => path.replace(/^\/api\/v1/, ''),
          configure: (proxy: any) => {
            proxy.on('error', (err: Error) => {
              console.error('Vite proxy error:', err.message);
            });
          },
        },
        '/cable': {
          target: env.VITE_WS_BASE_URL || 'ws://127.0.0.1:3000',
          changeOrigin: true,
          ws: true,
          secure: false,
        },
      },
    },
    
    build: {
      outDir: 'build',
      sourcemap: true,
      chunkSizeWarningLimit: 600,
      rollupOptions: {
        // Keep each host re-export entry's exports without forcing Rollup to
        // copy the underlying module. Host entries are named `host/<id>`, so
        // Vite's default `assets/[name]-[hash].js` lands them (hashed) under
        // `assets/host/` automatically; the import map targets the real emitted
        // filenames (see transformIndexHtml).
        preserveEntrySignatures: 'allow-extension',
        output: {
          manualChunks: {
            // Core React
            vendor: ['react', 'react-router-dom', 'react-dom'],
            // State management
            redux: ['@reduxjs/toolkit', 'react-redux'],
            // Data fetching
            query: ['@tanstack/react-query', 'axios'],
            // Workflow/diagram libraries (large)
            workflow: ['@xyflow/react', 'dagre'],
            // Markdown editor (large)
            markdown: ['@uiw/react-md-editor', '@uiw/react-markdown-preview', 'react-markdown'],
            // Charts
            charts: ['recharts'],
            // Drag and drop
            dnd: ['@dnd-kit/core', '@dnd-kit/sortable', '@dnd-kit/utilities'],
            // Utilities
            utils: ['date-fns', 'clsx', 'dompurify', 'ajv', 'ajv-formats'],
            // Icons
            icons: ['lucide-react', '@heroicons/react'],
            // Syntax highlighting
            highlight: ['highlight.js'],
          },
        },
      },
    },
    
    envPrefix: ['VITE_', 'REACT_APP_'],
    
    define: {
      'process.env.NODE_ENV': JSON.stringify(mode),
      'process.env.REACT_APP_VERSION': JSON.stringify(packageJson.version),
      '__BUILD_INFO__': JSON.stringify(resolveBuildInfo()),
      // __EXTENSIONS__ reflects extensions effectively active in this build.
      // Disabled extensions are removed so existing `__EXTENSIONS__.includes(slug)`
      // gates (App.tsx, Header.tsx, AdminSettingsTabs.tsx) tree-shake their imports.
      '__EXTENSIONS__': JSON.stringify(enabledSlugs),
      '__DISABLED_EXTENSIONS__': JSON.stringify(disabledSlugs),
    },
    
    optimizeDeps: {
      include: [
        'react',
        'react-dom',
        'react-router-dom',
        '@reduxjs/toolkit',
        'axios',
      ],
    },
  };
});
