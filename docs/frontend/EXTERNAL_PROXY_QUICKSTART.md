# External Reverse Proxy Quick Start

## Your Setup
- **Frontend URL**: https://dev-1.ipnode.org/
- **Backend API**: https://dev-1.ipnode.org/api/v1
- **External nginx/Apache proxy** already configured

## Quick Start (Recommended)

Run the specialized external proxy script:

```bash
cd frontend
./scripts/dev-external-proxy.sh
```

This script:
- Sets up the correct environment variables
- Configures Vite to connect HMR through your external proxy
- Starts the dev server on port 3001 accessible from your proxy

## Manual Start

If you prefer to start manually:

```bash
cd frontend

# Set environment variables
export VITE_BEHIND_PROXY=true
export VITE_PROXY_HOST=dev-1.ipnode.org
export VITE_PROXY_PROTOCOL=https

# Use the external proxy configuration
npx vite --config vite.config.external-proxy.ts --host 0.0.0.0
```

## What This Solves

1. **HMR WebSocket Connection**: Forces Vite's HMR to connect through `wss://dev-1.ipnode.org` instead of `ws://localhost:3001`
2. **API Routing**: Frontend correctly uses `https://dev-1.ipnode.org/api/v1` for all API calls
3. **Asset Loading**: All assets load through the proxy URL

## Verify It's Working

1. **Check Console Output**:
   You should see:
   ```
   🌐 Starting Vite for External Reverse Proxy
   📍 External URLs:
      Frontend: https://dev-1.ipnode.org/
      Backend:  https://dev-1.ipnode.org/api/v1
   ```

2. **Browser DevTools**:
   - Open Network tab
   - Look for WebSocket connection to `wss://dev-1.ipnode.org/@vite/hmr`
   - Should show status 101 (Switching Protocols)

3. **Test HMR**:
   - Edit any React component
   - Page should update without full reload
   - Console should show: `[vite] hot updated`

## Troubleshooting

### Issue: Still connecting to localhost
**Solution**: Make sure you're using the external proxy config:
```bash
./scripts/dev-external-proxy.sh
# OR
npx vite --config vite.config.external-proxy.ts
```

### Issue: WebSocket fails to connect
**Solution**: Verify your external proxy forwards WebSocket headers:
- nginx must have: `proxy_set_header Upgrade $http_upgrade;`
- Apache must have: `RewriteCond %{HTTP:Upgrade} websocket [NC]`

### Issue: API calls failing
**Solution**: Check that `VITE_API_BASE_URL` is set to `https://dev-1.ipnode.org/api/v1`

## Environment Variables

The external proxy configuration uses these settings:

```env
# Critical settings
VITE_BEHIND_PROXY=true
VITE_PROXY_HOST=dev-1.ipnode.org
VITE_PROXY_PROTOCOL=https

# API endpoints
VITE_API_BASE_URL=https://dev-1.ipnode.org/api/v1
VITE_WS_BASE_URL=wss://dev-1.ipnode.org/cable

# Server binding
HOST=0.0.0.0  # Bind to all interfaces
PORT=3001     # Local port your proxy connects to
```

## External Proxy Requirements

Your external reverse proxy (nginx/Apache) must:

1. **Forward to Vite dev server**: `http://your-server-ip:3001`
2. **Handle WebSocket upgrade** for paths: `/@vite/hmr`, `/@vite/client`
3. **Forward headers**: Host, X-Forwarded-Proto, X-Forwarded-Host
4. **Proxy API requests**: `/api/*` → Rails backend on port 3000

## Using Different Proxy Hosts

To use a different external proxy host:

1. Edit `vite.config.external-proxy.ts`:
   ```typescript
   hmr: {
     host: 'your-proxy-domain.com',  // Change this
     // ...
   }
   ```

2. Update environment:
   ```bash
   export VITE_PROXY_HOST=your-proxy-domain.com
   export VITE_API_BASE_URL=https://your-proxy-domain.com/api/v1
   ```

## Summary

The key difference when using an external proxy:
- **Regular dev**: Vite serves directly, HMR connects to localhost
- **External proxy**: Vite serves to proxy, HMR connects through proxy domain

Your setup with `dev-1.ipnode.org` requires the external proxy configuration to ensure all WebSocket and API connections go through the proxy URL, not localhost.