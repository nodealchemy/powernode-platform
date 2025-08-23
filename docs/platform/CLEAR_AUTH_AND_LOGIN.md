# Clear Authentication and Login Instructions

## The Issue
The WebSocket shows "Offline" because your browser has a stale JWT token from before the database was reset. The user ID in that token no longer exists in the new database.

## Solution: Clear Browser Storage and Login Fresh

### Step 1: Clear Browser Storage
1. Open your browser DevTools (F12)
2. Go to the **Application** tab (Chrome) or **Storage** tab (Firefox)
3. Find **Local Storage** in the left sidebar
4. Click on `http://localhost:3001`
5. Right-click and select "Clear" or click the clear button
6. Also clear **Session Storage** the same way

### Alternative: Use Console
Open the browser console and run:
```javascript
localStorage.clear();
sessionStorage.clear();
console.log('Storage cleared! Please refresh the page.');
```

### Step 2: Refresh and Login
1. Refresh the page (Ctrl+R or Cmd+R)
2. You should be redirected to the login page
3. Login with the new credentials:
   - **Email:** admin@powernode.org
   - **Password:** P0w3rN0d3Admin!@&

### Step 3: Verify WebSocket Connection
After logging in:
1. Check the header - the connection status indicator should show **"Real-time"** in green
2. Open the browser console and look for:
   - `🔍 WebSocket useEffect triggered`
   - `📡 Conditions met, calling connect()`
   - `🔌 Connecting to WebSocket:`
   - `✅ WebSocket connected`

### Step 4: Test Debug Page (Optional)
Navigate to: http://localhost:3001/dashboard/test-websocket

This page will show:
- Your current user email
- Account ID
- Access token status
- WebSocket connection status

## Why This Happens
When we reset the database:
1. All user IDs change (new UUIDs are generated)
2. Old JWT tokens reference user IDs that no longer exist
3. ActionCable rejects the connection with "Couldn't find User"
4. The WebSocket indicator shows "Offline"

## Prevention
Always clear browser storage after resetting the database to ensure fresh authentication tokens.