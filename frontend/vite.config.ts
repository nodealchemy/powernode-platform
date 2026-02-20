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
    ],
    
    resolve: {
      // Resolve shared packages from core node_modules when processing
      // enterprise source files (enterprise dir has no own node_modules)
      dedupe: [
        'react', 'react-dom', 'react-redux', '@reduxjs/toolkit',
        'react-router-dom', 'lucide-react', 'axios',
      ],
      alias: {
        '@': path.resolve(__dirname, './src'),
        '@/shared': path.resolve(__dirname, './src/shared'),
        '@/features': path.resolve(__dirname, './src/features'),
        '@/pages': path.resolve(__dirname, './src/pages'),
        '@/assets': path.resolve(__dirname, './src/assets'),
        ...(fs.existsSync(path.resolve(__dirname, '../extensions/enterprise/frontend/src'))
          ? { '@enterprise': path.resolve(__dirname, '../extensions/enterprise/frontend/src') }
          : {}),
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

      hmr: {
        timeout: 30000,
        overlay: true,
      },

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
      '__ENTERPRISE__': JSON.stringify(fs.existsSync(path.resolve(__dirname, '../extensions/enterprise/frontend/src'))),
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
