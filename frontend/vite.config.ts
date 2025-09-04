import { defineConfig, loadEnv } from 'vite';
import react from '@vitejs/plugin-react';
import viteTsconfigPaths from 'vite-tsconfig-paths';
import svgr from 'vite-plugin-svgr';
import path from 'path';
import { execSync } from 'child_process';
import fs from 'fs';

// Function to get allowed hosts from backend proxy settings
function getAllowedHosts(): string[] {
  try {
    // Try to fetch from backend proxy settings
    const result = execSync('node scripts/fetch-proxy-config.js', {
      encoding: 'utf-8',
      stdio: ['pipe', 'pipe', 'ignore'] // Ignore stderr to avoid console noise
    });
    
    const config = JSON.parse(result);
    if (config && config.allowedHosts) {
      console.log(`✓ Loaded ${config.allowedHosts.length} allowed hosts from ${config.source}`);
      return config.allowedHosts;
    }
  } catch (error) {
    console.log('⚠ Could not fetch proxy config, using defaults');
  }
  
  // Fallback to default hosts
  return [
    'localhost',
    '127.0.0.1',
    'dev-1.ipnode.net',
    '.ipnode.net',
  ];
}

// https://vitejs.dev/config/
export default defineConfig(({ mode }) => {
  // Load env file based on `mode` in the current working directory.
  const env = loadEnv(mode, process.cwd(), '');
  
  // Determine if we're behind a reverse proxy
  // Check multiple indicators for reverse proxy detection
  const isProduction = mode === 'production';
  const behindProxy = env.VITE_BEHIND_PROXY === 'true' || 
                     env.BEHIND_PROXY === 'true' ||
                     (env.NODE_ENV === 'production') ||
                     (typeof process !== 'undefined' && process.env.NODE_ENV === 'production') ||
                     // Auto-detect based on environment hints
                     env.VITE_PROXY_HOST !== undefined ||
                     env.PROXY_HOST !== undefined;
  
  // Use actual host from environment or detect from context
  const proxyHost = env.VITE_PROXY_HOST || 
                   env.PROXY_HOST ||
                   (typeof process !== 'undefined' && process.env.HOSTNAME) || 
                   'localhost';
  const proxyProtocol = env.VITE_PROXY_PROTOCOL || env.PROXY_PROTOCOL || 'https';
  
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
      
      // Allow specific hosts for development
      // Fetched dynamically from backend proxy settings
      allowedHosts: [
        ...allowedHosts,      // Hosts from backend proxy settings
        ...additionalHosts,   // Additional hosts from environment variable (override)
      ],
      
      // Configure HMR (Hot Module Replacement)
      hmr: behindProxy
        ? {
            // When behind external proxy, client must connect through proxy URL
            protocol: 'wss',
            host: proxyHost,
            port: 443,
            clientPort: 443,
            timeout: 120000,
            overlay: true,
          }
        : {
            protocol: 'ws',
            host: 'localhost',
            port: 3001,
            timeout: 60000,
            overlay: true,
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
      proxy: {
        '/api': {
          target: env.VITE_API_BASE_URL || 'http://localhost:3000',
          changeOrigin: true,
          secure: false,
          ws: true,
          configure: (proxy, _options) => {
            proxy.on('error', (err, _req, _res) => {
              console.log('proxy error', err);
            });
            proxy.on('proxyReq', (proxyReq, req, _res) => {
              console.log('Sending Request to the Target:', req.method, req.url);
            });
            proxy.on('proxyRes', (proxyRes, req, _res) => {
              console.log('Received Response from the Target:', proxyRes.statusCode, req.url);
            });
          },
        },
        '/cable': {
          target: env.VITE_WS_BASE_URL || 'ws://localhost:3000',
          changeOrigin: true,
          ws: true,
          secure: false,
        },
      },
    },
    
    build: {
      outDir: 'build',
      sourcemap: true,
      rollupOptions: {
        output: {
          manualChunks: {
            vendor: ['react', 'react-router-dom', 'react-dom'],
            redux: ['@reduxjs/toolkit', 'react-redux'],
          },
        },
      },
    },
    
    envPrefix: ['VITE_', 'REACT_APP_'],
    
    define: {
      // Ensure process.env is available for libraries that expect it
      'process.env': env,
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
