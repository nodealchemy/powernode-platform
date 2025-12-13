#!/usr/bin/env node
/**
 * MCP Weather Server (HTTP)
 *
 * An example MCP server that provides weather information via HTTP endpoints.
 * Demonstrates HTTP connection type and external API integration patterns.
 *
 * Connection Type: http
 * Tools: get_weather, get_forecast, search_location
 *
 * This server runs on port 3100 by default (configurable via PORT env var)
 *
 * Usage:
 *   node index.js
 *   PORT=3200 node index.js
 *
 * Or register in Powernode as an MCP server with:
 *   connection_type: http
 *   url: http://localhost:3100
 */

const http = require('http');

const PORT = process.env.PORT || 3100;

// Server info
const SERVER_INFO = {
  name: 'weather-server',
  version: '1.0.0',
  description: 'An MCP server providing weather information (mock data for demonstration)'
};

// Mock weather data (in production, this would call a real weather API)
const MOCK_LOCATIONS = {
  'new york': { lat: 40.7128, lon: -74.0060, name: 'New York, NY, USA' },
  'london': { lat: 51.5074, lon: -0.1278, name: 'London, UK' },
  'tokyo': { lat: 35.6762, lon: 139.6503, name: 'Tokyo, Japan' },
  'paris': { lat: 48.8566, lon: 2.3522, name: 'Paris, France' },
  'sydney': { lat: -33.8688, lon: 151.2093, name: 'Sydney, Australia' },
  'san francisco': { lat: 37.7749, lon: -122.4194, name: 'San Francisco, CA, USA' },
  'berlin': { lat: 52.5200, lon: 13.4050, name: 'Berlin, Germany' },
  'mumbai': { lat: 19.0760, lon: 72.8777, name: 'Mumbai, India' }
};

const WEATHER_CONDITIONS = ['Clear', 'Partly Cloudy', 'Cloudy', 'Rainy', 'Stormy', 'Snowy', 'Foggy'];

/**
 * Generate mock weather data for a location
 */
function generateWeather(location) {
  const now = new Date();
  const condition = WEATHER_CONDITIONS[Math.floor(Math.random() * WEATHER_CONDITIONS.length)];
  const temp = Math.floor(Math.random() * 35) + 5; // 5-40°C

  return {
    location: location.name,
    coordinates: { lat: location.lat, lon: location.lon },
    current: {
      temperature: temp,
      temperatureUnit: 'C',
      temperatureF: Math.round(temp * 9/5 + 32),
      condition,
      humidity: Math.floor(Math.random() * 60) + 30,
      windSpeed: Math.floor(Math.random() * 30) + 5,
      windUnit: 'km/h',
      pressure: Math.floor(Math.random() * 50) + 990,
      pressureUnit: 'hPa',
      visibility: Math.floor(Math.random() * 10) + 5,
      visibilityUnit: 'km',
      uvIndex: Math.floor(Math.random() * 11)
    },
    timestamp: now.toISOString(),
    source: 'mock-weather-api'
  };
}

/**
 * Generate mock forecast data
 */
function generateForecast(location, days = 5) {
  const forecast = [];
  const now = new Date();

  for (let i = 0; i < days; i++) {
    const date = new Date(now);
    date.setDate(date.getDate() + i);

    const high = Math.floor(Math.random() * 15) + 15;
    const low = high - Math.floor(Math.random() * 10) - 5;

    forecast.push({
      date: date.toISOString().split('T')[0],
      dayOfWeek: date.toLocaleDateString('en-US', { weekday: 'long' }),
      condition: WEATHER_CONDITIONS[Math.floor(Math.random() * WEATHER_CONDITIONS.length)],
      high: { value: high, unit: 'C' },
      low: { value: low, unit: 'C' },
      precipitation: Math.floor(Math.random() * 100),
      humidity: Math.floor(Math.random() * 60) + 30
    });
  }

  return {
    location: location.name,
    coordinates: { lat: location.lat, lon: location.lon },
    days,
    forecast,
    generatedAt: now.toISOString()
  };
}

// Tool definitions
const TOOLS = {
  get_weather: {
    name: 'get_weather',
    description: 'Get current weather conditions for a location',
    inputSchema: {
      type: 'object',
      properties: {
        location: {
          type: 'string',
          description: 'City name or location (e.g., "New York", "London")'
        }
      },
      required: ['location']
    },
    handler: (args) => {
      const locationKey = args.location.toLowerCase();
      const location = MOCK_LOCATIONS[locationKey];

      if (!location) {
        throw new Error(`Location not found: ${args.location}. Try: ${Object.keys(MOCK_LOCATIONS).join(', ')}`);
      }

      return generateWeather(location);
    }
  },

  get_forecast: {
    name: 'get_forecast',
    description: 'Get weather forecast for upcoming days',
    inputSchema: {
      type: 'object',
      properties: {
        location: {
          type: 'string',
          description: 'City name or location'
        },
        days: {
          type: 'integer',
          description: 'Number of days to forecast (1-7)',
          minimum: 1,
          maximum: 7,
          default: 5
        }
      },
      required: ['location']
    },
    handler: (args) => {
      const locationKey = args.location.toLowerCase();
      const location = MOCK_LOCATIONS[locationKey];

      if (!location) {
        throw new Error(`Location not found: ${args.location}. Try: ${Object.keys(MOCK_LOCATIONS).join(', ')}`);
      }

      const days = Math.min(Math.max(args.days || 5, 1), 7);
      return generateForecast(location, days);
    }
  },

  search_location: {
    name: 'search_location',
    description: 'Search for available weather locations',
    inputSchema: {
      type: 'object',
      properties: {
        query: {
          type: 'string',
          description: 'Search query (partial city name)'
        }
      },
      required: ['query']
    },
    handler: (args) => {
      const query = args.query.toLowerCase();
      const matches = Object.entries(MOCK_LOCATIONS)
        .filter(([key]) => key.includes(query))
        .map(([key, loc]) => ({
          id: key,
          name: loc.name,
          coordinates: { lat: loc.lat, lon: loc.lon }
        }));

      return {
        query: args.query,
        count: matches.length,
        locations: matches
      };
    }
  }
};

/**
 * Get server capabilities
 */
function getCapabilities() {
  return {
    protocolVersion: '2024-11-05',
    capabilities: {
      tools: { listChanged: false },
      resources: { subscribe: false, listChanged: false }
    },
    serverInfo: SERVER_INFO
  };
}

/**
 * Create JSON-RPC response
 */
function createResponse(id, result) {
  return { jsonrpc: '2.0', id, result };
}

/**
 * Create JSON-RPC error response
 */
function createError(id, code, message) {
  return { jsonrpc: '2.0', id, error: { code, message } };
}

/**
 * Handle JSON-RPC request
 */
function handleRequest(request) {
  const { jsonrpc, method, params, id } = request;

  if (jsonrpc !== '2.0') {
    return createError(id, -32600, 'Invalid Request: jsonrpc must be "2.0"');
  }

  switch (method) {
    case 'initialize':
      return createResponse(id, getCapabilities());

    case 'ping':
      return createResponse(id, { pong: true, timestamp: new Date().toISOString() });

    case 'tools/list':
      return createResponse(id, {
        tools: Object.values(TOOLS).map(t => ({
          name: t.name,
          description: t.description,
          inputSchema: t.inputSchema
        }))
      });

    case 'tools/call': {
      const { name, arguments: args } = params || {};
      const tool = TOOLS[name];

      if (!tool) {
        return createError(id, -32602, `Tool not found: ${name}`);
      }

      try {
        const result = tool.handler(args || {});
        return createResponse(id, {
          content: [{
            type: 'text',
            text: JSON.stringify(result, null, 2)
          }]
        });
      } catch (error) {
        return createError(id, -32000, `Tool execution failed: ${error.message}`);
      }
    }

    default:
      return createError(id, -32601, `Method not found: ${method}`);
  }
}

/**
 * Parse request body
 */
function parseBody(req) {
  return new Promise((resolve, reject) => {
    let body = '';
    req.on('data', chunk => { body += chunk; });
    req.on('end', () => {
      try {
        resolve(JSON.parse(body));
      } catch (e) {
        reject(new Error('Invalid JSON'));
      }
    });
    req.on('error', reject);
  });
}

/**
 * HTTP request handler
 */
async function requestHandler(req, res) {
  // CORS headers for development
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  res.setHeader('Content-Type', 'application/json');

  // Handle preflight
  if (req.method === 'OPTIONS') {
    res.writeHead(204);
    res.end();
    return;
  }

  // Health check endpoint
  if (req.method === 'GET' && req.url === '/health') {
    res.writeHead(200);
    res.end(JSON.stringify({
      status: 'healthy',
      server: SERVER_INFO.name,
      version: SERVER_INFO.version,
      timestamp: new Date().toISOString()
    }));
    return;
  }

  // MCP endpoint (POST only)
  if (req.method !== 'POST') {
    res.writeHead(405);
    res.end(JSON.stringify({ error: 'Method not allowed' }));
    return;
  }

  try {
    const request = await parseBody(req);
    const response = handleRequest(request);

    res.writeHead(200);
    res.end(JSON.stringify(response));
  } catch (error) {
    res.writeHead(400);
    res.end(JSON.stringify(createError(null, -32700, `Parse error: ${error.message}`)));
  }
}

// Create and start server
const server = http.createServer(requestHandler);

server.listen(PORT, () => {
  console.log(`[${SERVER_INFO.name}] MCP HTTP server running on http://localhost:${PORT}`);
  console.log(`[${SERVER_INFO.name}] Health check: http://localhost:${PORT}/health`);
  console.log(`[${SERVER_INFO.name}] Available tools: ${Object.keys(TOOLS).join(', ')}`);
});

// Graceful shutdown
process.on('SIGINT', () => {
  console.log('\nShutting down...');
  server.close(() => process.exit(0));
});

process.on('SIGTERM', () => {
  console.log('\nShutting down...');
  server.close(() => process.exit(0));
});
