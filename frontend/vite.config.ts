import { defineConfig, loadEnv } from 'vite';
import react from '@vitejs/plugin-react';
import viteTsconfigPaths from 'vite-tsconfig-paths';
import svgr from 'vite-plugin-svgr';
import path from 'path';
import fs from 'fs';
import packageJson from './package.json';

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
export default defineConfig(({ mode }: { mode: string }) => {
  const env = loadEnv(mode, process.cwd(), '');

  // Get allowed hosts from cache or environment
  const allowedHosts = getAllowedHosts();
  const additionalHosts = env.VITE_ALLOWED_HOSTS ? env.VITE_ALLOWED_HOSTS.split(',') : [];

  // Dynamic extension discovery
  const extensionsDir = path.resolve(__dirname, '../extensions');
  const extensionAliases: Record<string, string> = {};
  const discoveredSlugs: string[] = [];

  if (fs.existsSync(extensionsDir)) {
    for (const slug of fs.readdirSync(extensionsDir)) {
      const manifestPath = path.resolve(extensionsDir, slug, 'extension.json');
      const frontendSrc = path.resolve(extensionsDir, slug, 'frontend/src');
      if (fs.existsSync(manifestPath) && fs.existsSync(frontendSrc)) {
        extensionAliases[`@ext/${slug}`] = frontendSrc;
        extensionAliases[`@${slug}`] = frontendSrc; // intra-extension imports (e.g. @business/)
        discoveredSlugs.push(slug);
      }
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
            if (id.includes(`/extensions/${slug}/`)) {
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
