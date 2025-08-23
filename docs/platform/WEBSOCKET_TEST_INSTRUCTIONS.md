# WebSocket Connection Test Instructions

## Testing the WebSocket Connection

### 1. Login to the Application
Open http://localhost:3001 in your browser and login with:
- **Email:** admin@powernode.org
- **Password:** P0werN0de#Adm1n2024!

### 2. Check Connection Status Indicator
Look at the top-right of the header. You should see the connection status indicator showing:
- **"Real-time"** (green) if connected
- **"Offline"** (gray) if not connected
- **"Error"** (red) if there's an error

### 3. Test Debug Page
Navigate to: http://localhost:3001/dashboard/test-websocket

This page shows:
- Current user email
- Account ID
- Access token presence
- WebSocket connection status
- Any connection errors

### 4. Check Browser Console
Open the browser Developer Console (F12) and look for messages:
- `🔍 WebSocket useEffect triggered` - Shows when the hook runs
- `📡 Conditions met, calling connect()` - Shows when connection should start
- `🔌 Connecting to WebSocket:` - Shows the connection attempt
- `✅ WebSocket connected` - Shows successful connection

### 5. Verify Backend Logs
Check Rails logs for WebSocket activity:
```bash
cd server && tail -f log/development.log | grep ActionCable
```

You should see:
- `ActionCable: Token present: true`
- `ActionCable: Authentication successful for admin@powernode.org`

## What We Fixed

1. **Added debugging logs** to the useWebSocket hook to track connection attempts
2. **Fixed admin user password** to allow login
3. **Verified ActionCable is working** using direct WebSocket testing
4. **Created test page** to display WebSocket connection state

## Known Working WebSocket Test

Run this Node.js script to verify the WebSocket server is working:
```bash
cd /home/rett/Drive/Projects/powernode-platform
node test-ws.js
```

This confirms the WebSocket server accepts connections and sends welcome messages.

## Current Status

✅ WebSocket server (ActionCable) is working correctly
✅ Authentication via JWT tokens is working
✅ Direct WebSocket connections work (verified with Node.js)
⚠️  React app connection needs verification in browser

## Next Steps

1. Open the browser and navigate to the test page
2. Check the browser console for WebSocket connection logs
3. Verify the connection status indicator shows "Real-time" when connected

The WebSocket connection should automatically establish when:
- User is logged in (has valid JWT token)
- User account has an ID
- Component is mounted

The connection will automatically reconnect if disconnected.