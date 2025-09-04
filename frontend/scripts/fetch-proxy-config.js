#!/usr/bin/env node

/**
 * Fetch proxy configuration from backend server
 * Used by Vite to dynamically configure allowed hosts
 */

const http = require('http');
const https = require('https');
const fs = require('fs');
const path = require('path');

// Configuration
const API_BASE = process.env.VITE_API_BASE_URL || 'http://localhost:3000';
const CONFIG_ENDPOINT = '/api/v1/config';
const ALLOWED_HOSTS_ENDPOINT = '/api/v1/config/allowed_hosts';
const QUIET_MODE = process.env.VITE_QUIET !== 'false'; // Default to quiet

// Cache file for offline development
const CACHE_FILE = path.join(__dirname, '..', '.proxy-config-cache.json');

/**
 * Fetch configuration from API endpoint
 */
function fetchConfig(url) {
  return new Promise((resolve, reject) => {
    const urlObj = new URL(url);
    const client = urlObj.protocol === 'https:' ? https : http;
    
    const options = {
      hostname: urlObj.hostname,
      port: urlObj.port || (urlObj.protocol === 'https:' ? 443 : 80),
      path: urlObj.pathname + urlObj.search,
      method: 'GET',
      timeout: 3000, // 3 second timeout
      headers: {
        'Accept': 'application/json'
      }
    };
    
    const req = client.request(options, (res) => {
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
    });
    
    req.on('error', (err) => {
      reject(err);
    });
    
    req.on('timeout', () => {
      req.destroy();
      reject(new Error('Request timeout'));
    });
    
    req.end();
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
 * Extract allowed hosts from backend response
 */
function extractAllowedHosts(response) {
  // If the response already has allowed_hosts array, use it directly
  if (response?.data?.allowed_hosts && Array.isArray(response.data.allowed_hosts)) {
    return response.data.allowed_hosts;
  }
  
  // Fallback for legacy format
  const hosts = new Set([
    'localhost',
    '127.0.0.1',
    '::1',
  ]);
  
  // Add trusted hosts from proxy config (legacy)
  if (response?.data?.trusted_hosts) {
    response.data.trusted_hosts.forEach(host => {
      hosts.add(host);
    });
  }
  
  // Add default host if configured (legacy)
  if (response?.data?.default_host) {
    hosts.add(response.data.default_host);
  }
  
  // Add wildcard patterns for multi-tenancy (legacy)
  if (response?.data?.multi_tenancy?.wildcard_patterns) {
    response.data.multi_tenancy.wildcard_patterns.forEach(pattern => {
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
    // Try to fetch allowed hosts from public endpoint
    if (!QUIET_MODE) {
      console.error('Fetching allowed hosts from backend...');
    }
    const response = await fetchConfig(`${API_BASE}${ALLOWED_HOSTS_ENDPOINT}`);
    
    // Extract allowed hosts
    const allowedHosts = extractAllowedHosts(response);
    
    // Save to cache for offline use
    const config = {
      allowedHosts,
      fetchedAt: new Date().toISOString(),
      source: 'backend'
    };
    saveCache(config);
    
    // Output for Vite to consume (stdout only, no console.log)
    process.stdout.write(JSON.stringify(config));
    
  } catch (error) {
    if (!QUIET_MODE) {
      console.error('Failed to fetch from backend:', error.message);
    }
    
    // Try to use cached configuration
    const cached = loadCache();
    if (cached) {
      if (!QUIET_MODE) {
        console.error('Using cached configuration');
      }
      process.stdout.write(JSON.stringify(cached));
    } else {
      // Fallback to default configuration
      const defaultConfig = {
        allowedHosts: [
          'localhost',
          '127.0.0.1',
          '::1'
        ],
        source: 'default'
      };
      if (!QUIET_MODE) {
        console.error('Using default configuration');
      }
      process.stdout.write(JSON.stringify(defaultConfig));
    }
  }
}

// Run if executed directly
if (require.main === module) {
  main().catch(console.error);
}

module.exports = { fetchConfig, extractAllowedHosts };