import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import viteTsconfigPaths from 'vite-tsconfig-paths';
import svgr from 'vite-plugin-svgr';
import path from 'path';

// This configuration is specifically for external reverse proxy setup
// Use with: vite --config vite.config.external-proxy.ts

export default defineConfig({
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
    
    // Allow the external proxy host
    allowedHosts: [
      'localhost',
      '127.0.0.1',
      'dev-1.ipnode.net',
      'dev-1.ipnode.org',
      '.ipnode.net',
      '.ipnode.org'
    ],
    
    // HMR configuration for external reverse proxy
    hmr: {
      // Force HMR to use the external proxy URL
      protocol: 'wss',
      host: 'dev-1.ipnode.org',
      port: 443,
      clientPort: 443,
      timeout: 120000,
      overlay: true,
    },
    
    // CORS configuration
    cors: true,
    
    // Headers for reverse proxy
    headers: {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, PATCH, OPTIONS',
      'Access-Control-Allow-Headers': 'X-Requested-With, content-type, Authorization',
    },
    
    // API proxy configuration (not used when behind external proxy)
    proxy: {},
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
    'process.env': {},
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
});