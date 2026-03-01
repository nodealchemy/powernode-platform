# Reverse Proxy Setup for Vite Development

This guide explains how to run the Powernode frontend behind a reverse proxy (nginx, Apache, etc.) for development.

## Quick Start

1. **Using the proxy script** (Recommended):
```bash
./scripts/dev-proxy.sh
```

2. **Manual configuration**:
```bash
# Copy proxy environment configuration
cp .env.proxy .env.local

# Start Vite with host binding
npm run dev -- --host 0.0.0.0
```

## Environment Configuration

### Required Environment Variables

Create or update `.env.local` with:

```bash
# Critical for reverse proxy operation
VITE_BEHIND_PROXY=true
VITE_PROXY_HOST=app.example.com    # Your proxy hostname
VITE_PROXY_PROTOCOL=https          # https or http

# API endpoints (should match your proxy setup)
VITE_API_BASE_URL=https://app.example.com/api/v1
VITE_WS_BASE_URL=wss://app.example.com/cable

# Optional: Explicitly set allowed hosts
VITE_ALLOWED_HOSTS=app.example.com,staging.example.com
```

## Nginx Configuration

Use the provided `nginx-dev-proxy.conf` as a template:

```nginx
server {
    listen 443 ssl http2;
    server_name app.example.com;
    
    # Main application
    location / {
        proxy_pass http://localhost:3001;
        proxy_http_version 1.1;
        
        # Required headers for proper proxy operation
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Port $server_port;
        
        # WebSocket support for HMR
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
    
    # Vite HMR WebSocket endpoint
    location ~ ^/@vite/(client|hmr) {
        proxy_pass http://localhost:3001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_socket_keepalive on;
    }
}
```

## How It Works

### 1. Proxy Detection
The Vite configuration automatically detects when running behind a proxy by checking:
- `VITE_BEHIND_PROXY` environment variable
- Production mode indicators
- Presence of proxy configuration variables

### 2. HMR Configuration
When behind a proxy, Vite's Hot Module Replacement (HMR) is configured to:
- Use WebSocket Secure (wss://) for HTTPS proxies
- Connect through the proxy host/port instead of directly to the dev server
- Set proper client port to match the proxy's public port (443 for HTTPS)

### 3. Allowed Hosts
The frontend dynamically fetches allowed hosts from the backend's proxy settings:
- Runs `scripts/fetch-proxy-config.js` during startup
- Falls back to environment variables or defaults if backend is unavailable
- Prevents DNS rebinding attacks

## Common Issues and Solutions

### Issue: "This host is not allowed"
**Solution**: Add the hostname to `VITE_ALLOWED_HOSTS` in `.env.local` or configure it in the backend proxy settings.

### Issue: WebSocket connection fails
**Solution**: Ensure your reverse proxy is properly forwarding WebSocket upgrade headers:
```nginx
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection "upgrade";
```

### Issue: HMR not working
**Solution**: Check that:
1. `VITE_BEHIND_PROXY=true` is set
2. Nginx is forwarding the `/@vite/` paths
3. WebSocket connections are not being blocked by firewalls

### Issue: Assets loading from wrong URL
**Solution**: The Vite configuration automatically sets the base URL when behind a proxy. Ensure `VITE_PROXY_HOST` and `VITE_PROXY_PROTOCOL` are correctly set.

## Testing the Setup

1. **Check environment detection**:
   - Start the dev server and look for "Behind Proxy: true" in the console

2. **Verify WebSocket connection**:
   - Open browser DevTools → Network tab
   - Look for WebSocket connections to `wss://your-proxy-host/@vite/hmr`
   - Status should be 101 (Switching Protocols)

3. **Test HMR**:
   - Make a change to a React component
   - The page should update without a full reload
   - Check console for HMR messages

## Advanced Configuration

### Custom Proxy Paths
If your proxy uses a sub-path (e.g., `/app/`), set the base in `vite.config.ts`:
```typescript
export default defineConfig({
  base: '/app/',
  // ... rest of config
});
```

### Multiple Proxy Hosts
To support multiple proxy hosts dynamically:
```bash
VITE_ALLOWED_HOSTS=host1.com,host2.com,*.example.org
```

### SSL Configuration
For self-signed certificates in development:
```bash
NODE_TLS_REJECT_UNAUTHORIZED=0 npm run dev
```

## Architecture Overview

```
Internet → Reverse Proxy (nginx:443) → Vite Dev Server (localhost:3001)
                ↓                              ↓
         WebSocket Upgrade              HMR WebSocket Server
                ↓                              ↓
            Browser ← ← ← ← ← HMR Updates ← ← ←
```

The reverse proxy handles:
- SSL termination
- Host validation
- WebSocket upgrades for HMR
- API routing to backend services

## Related Documentation

- [Vite Server Options](https://vitejs.dev/config/server-options.html)
- [Nginx WebSocket Proxying](http://nginx.org/en/docs/http/websocket.html)
- Backend proxy settings: `/api/v1/admin/proxy_settings`