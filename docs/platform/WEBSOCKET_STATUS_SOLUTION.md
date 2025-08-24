# WebSocket Connection Status: Offline Issue - SOLVED

## Root Cause
The WebSocket status indicator shows "Offline" because:
1. **Stale JWT Token**: Your browser has a JWT token from before the database was reset
2. **Invalid User ID**: The user ID in the old token (`956769ac-b86c-4843-9dd3-fe3da696425f`) no longer exists in the new database
3. **Failed Authentication**: ActionCable rejects the connection with "Couldn't find User with 'id'=..."

## Evidence from Logs
```
ActionCable authentication failed: Couldn't find User with 'id'=956769ac-b86c-4843-9dd3-fe3da696425f
```

The new admin user has a different ID: `af9a1d6d-ff32-445d-a6d5-593fd4804f6f`

## Solution: Clear Browser Storage

### Quick Fix - Browser Console
Open DevTools (F12) and run in the console:
```javascript
// Clear all stored tokens
localStorage.clear();
sessionStorage.clear();
location.reload();
```

### Manual Fix - Browser Storage
1. Open DevTools (F12)
2. Go to Application tab → Local Storage
3. Find `http://localhost:3001`
4. Clear all entries
5. Refresh the page

### Then Login Fresh
Use the new credentials:
- **Email:** admin@powernode.org
- **Password:** P0w3rN0d3Admin!@&

## Verification

### ✅ WebSocket Server is Working
Confirmed via direct testing:
```bash
node test-ws.js
# Output: ✅ WebSocket connected!
# Output: 📨 Received: {"type":"welcome"}
```

### ✅ Authentication is Working
Fresh tokens authenticate successfully:
```bash
curl -X POST http://localhost:3000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email": "admin@powernode.org", "password": "P0w3rN0d3Admin!@&"}'
# Returns valid access_token
```

### ✅ Improvements Made
1. **Better error handling** in useWebSocket hook
2. **Clear error messages** when authentication fails
3. **Detailed logging** for debugging connection issues
4. **Test page** at `/dashboard/test-websocket` for verification

## Expected Behavior After Fix

1. **Connection Status**: Shows "Real-time" (green) in header
2. **Browser Console**: Shows successful connection:
   ```
   🔍 WebSocket useEffect triggered
   📡 Conditions met, calling connect()
   🔌 Connecting to WebSocket: ws://localhost:3000/cable?token=***
   ✅ WebSocket connected
   ```
3. **Rails Logs**: Shows successful authentication:
   ```
   ActionCable: Authentication successful for admin@powernode.org
   ```

## Prevention
Always clear browser storage after database resets:
- During development when running `rails db:drop db:create db:seed`
- After deploying with database changes
- When switching between different database states

## Technical Details
- WebSocket endpoint: `ws://localhost:3000/cable`
- Authentication: JWT token in query parameter
- Token storage: localStorage keys: `accessToken`, `refreshToken`
- User verification: ActionCable checks user exists and is active
- Auto-reconnect: Attempts reconnection every 3 seconds on failure