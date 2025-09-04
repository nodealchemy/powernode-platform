#!/usr/bin/env node

/**
 * Fetch proxy configuration from backend server
 * Used by Vite to dynamically configure allowed hosts
 */

const http = require('http');
const fs = require('fs');
const path = require('path');

// Configuration
const API_BASE = process.env.VITE_API_BASE_URL || 'http://localhost:3000';
const CONFIG_ENDPOINT = '/api/v1/config';
const PROXY_SETTINGS_ENDPOINT = '/api/v1/admin/proxy_settings/url_config';

// Cache file for offline development
const CACHE_FILE = path.join(__dirname, '..', '.proxy-config-cache.json');

/**
 * Fetch configuration from API endpoint
 */
function fetchConfig(url) {
  return new Promise((resolve, reject) => {
    http.get(url, (res) => {
      let data = '';
      
      res.on('data', (chunk) => {
        data += chunk;
      });
      
      res.on('end', () => {
        if (res.statusCode === 200) {
          try {
            const json = JSON.parse(data);
            resolve(json);
          } catch (e) {
            reject(new Error('Invalid JSON response'));
          }
        } else {
          reject(new Error(`HTTP ${res.statusCode}`));
        }
      });
    }).on('error', (err) => {
      reject(err);
    });
  });
}

/**
 * Load cached configuration if available
 */
function loadCache() {
  try {
    if (fs.existsSync(CACHE_FILE)) {
      const data = fs.readFileSync(CACHE_FILE, 'utf8');
      return JSON.parse(data);
    }
  } catch (e) {
    // Ignore cache errors
  }
  return null;
}

/**
 * Save configuration to cache
 */
function saveCache(config) {
  try {
    fs.writeFileSync(CACHE_FILE, JSON.stringify(config, null, 2));
  } catch (e) {
    // Ignore cache errors
  }
}

/**
 * Extract allowed hosts from proxy configuration
 */
function extractAllowedHosts(proxyConfig) {
  const hosts = new Set([
    'localhost',
    '127.0.0.1',
    '::1',
  ]);
  
  // Add trusted hosts from proxy config
  if (proxyConfig?.data?.trusted_hosts) {
    proxyConfig.data.trusted_hosts.forEach(host => {
      hosts.add(host);
    });
  }
  
  // Add default host if configured
  if (proxyConfig?.data?.default_host) {
    hosts.add(proxyConfig.data.default_host);
  }
  
  // Add wildcard patterns for multi-tenancy
  if (proxyConfig?.data?.multi_tenancy?.wildcard_patterns) {
    proxyConfig.data.multi_tenancy.wildcard_patterns.forEach(pattern => {
      hosts.add(pattern);
    });
  }
  
  return Array.from(hosts);
}

/**
 * Main function
 */
async function main() {
  try {
    // Try to fetch proxy settings from backend
    console.log('Fetching proxy configuration from backend...');
    const proxyConfig = await fetchConfig(`${API_BASE}${PROXY_SETTINGS_ENDPOINT}`);
    
    // Extract allowed hosts
    const allowedHosts = extractAllowedHosts(proxyConfig);
    
    // Save to cache for offline use
    const config = {
      allowedHosts,
      fetchedAt: new Date().toISOString(),
      source: 'backend'
    };
    saveCache(config);
    
    // Output for Vite to consume
    console.log('Allowed hosts:', allowedHosts.join(', '));
    process.stdout.write(JSON.stringify(config));
    
  } catch (error) {
    console.log('Failed to fetch from backend:', error.message);
    
    // Try to use cached configuration
    const cached = loadCache();
    if (cached) {
      console.log('Using cached configuration');
      process.stdout.write(JSON.stringify(cached));
    } else {
      // Fallback to default configuration
      const defaultConfig = {
        allowedHosts: [
          'localhost',
          '127.0.0.1',
          '::1',
          'dev-1.ipnode.net',
          'dev-1.ipnode.org',
          '.ipnode.net',
          '.ipnode.org'
        ],
        source: 'default'
      };
      console.log('Using default configuration');
      process.stdout.write(JSON.stringify(defaultConfig));
    }
  }
}

// Run if executed directly
if (require.main === module) {
  main().catch(console.error);
}

module.exports = { fetchConfig, extractAllowedHosts };