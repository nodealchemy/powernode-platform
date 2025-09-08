#!/usr/bin/env node

/**
 * Manually refresh the proxy configuration cache
 * Useful for development when you need to immediately update allowed hosts
 */

const path = require('path');
const { spawn } = require('child_process');

console.log('🔄 Refreshing proxy configuration cache...');

const refreshProcess = spawn('node', ['fetch-proxy-config.js'], {
  cwd: __dirname,
  stdio: 'inherit',
  env: { ...process.env, VITE_QUIET: 'false' }
});

refreshProcess.on('close', (code) => {
  if (code === 0) {
    console.log('✅ Proxy cache refreshed successfully');
    console.log('💡 Restart the Vite dev server to apply changes');
  } else {
    console.log('❌ Failed to refresh proxy cache');
    process.exit(1);
  }
});

refreshProcess.on('error', (error) => {
  console.error('❌ Error running refresh process:', error.message);
  process.exit(1);
});