import { defineConfig, loadEnv } from 'vite';
import react from '@vitejs/plugin-react';
import viteTsconfigPaths from 'vite-tsconfig-paths';
import svgr from 'vite-plugin-svgr';
import path from 'path';
import fs from 'fs';

// Cached proxy configuration to prevent automatic page refreshes
function getAllowedHosts(): string[] {
  console.log('🔧 getAllowedHosts() called at:', new Date().toISOString());
  const CACHE_FILE = path.join(__dirname, '.proxy-config-cache.json');
  const CACHE_TTL = 30 * 60 * 1000; // 30 minutes TTL
  
  // Default hosts - always available as fallback
  const defaultHosts = [
    'localhost',
    '127.0.0.1',
    '::1'
  ];
  
  try {
    // Check if cache file exists and is still valid
    if (fs.existsSync(CACHE_FILE)) {
      const cacheContent = fs.readFileSync(CACHE_FILE, 'utf8');
      const cache = JSON.parse(cacheContent);
      
      // Check if cache is still valid (within TTL), but use cached hosts anyway for development stability
      const cacheAge = Date.now() - new Date(cache.fetchedAt).getTime();
      if (cache.allowedHosts && cache.allowedHosts.length > 0) {
        if (cacheAge < CACHE_TTL) {
          console.log(`✓ Using cached allowed hosts (${cache.allowedHosts.length} hosts, ${Math.round(cacheAge / 1000 / 60)}min old)`);
        } else {
          console.log(`⚠ Cache expired (${Math.round(cacheAge / 1000 / 60)}min old) but using cached hosts for stability`);
        }
        // Combine defaults with cached hosts, removing duplicates
        const allHosts = [...new Set([...defaultHosts, ...cache.allowedHosts])];
        console.log(`✓ Final allowed hosts:`, allHosts);
        return allHosts;
      } else {
        console.log('⚠ No cached hosts found, using defaults');
      }
    } else {
      console.log('⚠ No proxy cache found, using defaults (background refresh will create)');
    }
  } catch (error: unknown) {
    const errorMessage = error instanceof Error ? error.message : 'Unknown error';
    console.log('⚠ Error reading proxy cache, using defaults:', errorMessage);
  }
  
  // TEMPORARILY DISABLED - Background refresh may be causing 90s refresh cycles
  // Schedule background refresh (non-blocking)
  // This runs after Vite config is loaded, preventing refresh cycles
  // scheduleBackgroundRefresh(CACHE_FILE);
  console.log('⚠️ Background refresh disabled - using cached hosts or defaults');
  console.log(`✓ Using default hosts:`, defaultHosts);
  
  return defaultHosts;
}

// Background refresh that doesn't block Vite configuration
// TEMPORARILY DISABLED - Function preserved for future use
// function scheduleBackgroundRefresh(cacheFile: string): void {
//   // Use setImmediate to ensure this runs after Vite config loading
//   setImmediate(() => {
//     // Fork a child process to avoid blocking
//     const { spawn } = require('child_process');
//
//     const refreshProcess = spawn('node', ['scripts/fetch-proxy-config.js'], {
//       cwd: __dirname,
//       stdio: 'pipe',
//       env: { ...process.env, VITE_QUIET: 'true' },
//       detached: false
//     });
//
//     let output = '';
//     refreshProcess.stdout.on('data', (data: Buffer) => {
//       output += data.toString();
//     });
//
//     refreshProcess.on('close', (code: number) => {
//       if (code === 0 && output.trim()) {
//         try {
//           // Verify the output is valid JSON
//           const config = JSON.parse(output.trim());
//           if (config.allowedHosts && config.allowedHosts.length > 0) {
//             // Update cache file for next Vite restart
//             fs.writeFileSync(cacheFile, JSON.stringify({
//               ...config,
//               fetchedAt: new Date().toISOString()
//             }, null, 2));
//             console.log('✓ Background refresh completed, cache updated for next restart');
//           }
//         } catch (error: unknown) {
//           const errorMessage = error instanceof Error ? error.message : 'Unknown error';
//           console.log('⚠ Background refresh failed to parse response:', errorMessage);
//         }
//       } else {
//         console.log('⚠ Background refresh failed, will retry on next restart');
//       }
//     });
//
//     // Prevent hanging processes
//     refreshProcess.on('error', () => {
//       console.log('⚠ Background refresh process error, will retry on next restart');
//     });
//
//     // Kill after 10 seconds to prevent hanging
//     setTimeout(() => {
//       if (!refreshProcess.killed) {
//         refreshProcess.kill();
//       }
//     }, 10000);
//   });
// }

// https://vitejs.dev/config/
export default defineConfig(({ mode }: { mode: string }) => {
  // Load env file based on `mode` in the current working directory.
  const env = loadEnv(mode, process.cwd(), '');
  
  // Use actual host from environment or detect from context
  const proxyHost = env.VITE_PROXY_HOST || 
                   env.PROXY_HOST ||
                   (typeof process !== 'undefined' && process.env.HOSTNAME) || 
                   'localhost';
  const proxyProtocol = env.VITE_PROXY_PROTOCOL || env.PROXY_PROTOCOL || 'https';
  
  // Runtime proxy detection (similar to API logic)
  // If VITE_BEHIND_PROXY is explicitly set, use it
  // Otherwise, auto-detect based on production mode or domain patterns
  const behindProxy = env.VITE_BEHIND_PROXY === 'true' ||
                     env.BEHIND_PROXY === 'true' ||
                     (env.NODE_ENV === 'production') ||
                     // Auto-detect proxy based on domain patterns (non-localhost, non-IP)
                     (proxyHost !== 'localhost' && !proxyHost.match(/^\d+\.\d+\.\d+\.\d+$/));
  
  console.log('🔧 Vite Configuration:');
  console.log(`  Mode: ${mode}`);
  console.log(`  Behind Proxy: ${behindProxy}`);
  console.log(`  Proxy Host: ${proxyHost}`);
  console.log(`  Proxy Protocol: ${proxyProtocol}`);
  
  // Get allowed hosts from backend proxy settings
  const allowedHosts = getAllowedHosts();
  
  // Parse additional allowed hosts from environment (as override)
  const additionalHosts = env.VITE_ALLOWED_HOSTS ? env.VITE_ALLOWED_HOSTS.split(',') : [];
  
  // Configure base URL for proper asset serving behind proxy
  const base = '/';

  return {
    base,
    
    
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
      alias: {
        '@': path.resolve(__dirname, './src'),
        '@/shared': path.resolve(__dirname, './src/shared'),
        '@/features': path.resolve(__dirname, './src/features'),
        '@/pages': path.resolve(__dirname, './src/pages'),
        '@/assets': path.resolve(__dirname, './src/assets'),
      },
    },
    
    server: {
      host: '0.0.0.0',
      port: 3001,
      open: false,
      strictPort: true, // Don't try alternative ports
      
      // Allow specific hosts for development
      // Fetched dynamically from backend proxy settings
      // Add '.host.docker.internal' for Docker environments
      allowedHosts: [
        ...allowedHosts,      // Hosts from backend proxy settings
        ...additionalHosts,   // Additional hosts from environment variable (override)
        '.host.docker.internal', // Docker host
      ],
      
      // Configure HMR (Hot Module Replacement)
      // Dynamic configuration - client will determine connection type at runtime
      hmr: {
        // Let Vite handle the connection dynamically
        // For proxy scenarios: client will connect via same domain
        // For direct access: client will connect to development server port
        timeout: 30000, // Reduced from 120000ms to prevent long disconnection periods
        overlay: true,
        // Allow Vite to auto-detect the best connection method
        clientPort: undefined,
        protocol: undefined,
      },
      
      // Configure CORS for development
      cors: true,
      
      // Headers to handle reverse proxy
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, PATCH, OPTIONS',
        'Access-Control-Allow-Headers': 'X-Requested-With, content-type, Authorization',
      },
      
      // API proxy configuration
      // Use 127.0.0.1 instead of localhost to force IPv4 (Rails binds to IPv4 only)
      proxy: {
        '/api/v1': {
          target: 'http://127.0.0.1:3000/api/v1',
          changeOrigin: true,
          secure: false,
          ws: true,
          rewrite: (path: string) => path.replace(/^\/api\/v1/, ''),
          configure: (proxy: any) => {
            proxy.on('error', (err: Error) => {
              console.log('proxy error', err);
            });
            proxy.on('proxyReq', (_proxyReq: any, req: any) => {
              console.log('Sending Request to the Target:', req.method, req.url);
            });
            proxy.on('proxyRes', (proxyRes: any, req: any) => {
              console.log('Received Response from the Target:', proxyRes.statusCode, req.url);
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
      // Only expose specific env vars for security (not the entire process.env)
      'process.env.NODE_ENV': JSON.stringify(mode),
      'process.env.REACT_APP_VERSION': JSON.stringify(env.REACT_APP_VERSION || env.npm_package_version || '0.0.1-dev'),
      // Force cache invalidation for proxy config changes
      __PROXY_CONFIG_VERSION__: JSON.stringify('v1.1.0-proxy-fix'),
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
