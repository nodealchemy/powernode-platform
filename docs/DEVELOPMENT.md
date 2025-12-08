# Development Guide

This guide covers how to run the Powernode platform in development mode.

## Quick Start

### Recommended: Auto-Dev Script

```bash
# Start all services (Rails API + React frontend + Worker)
$POWERNODE_ROOT/scripts/auto-dev.sh ensure

# Check service status
$POWERNODE_ROOT/scripts/auto-dev.sh status

# Stop all services
$POWERNODE_ROOT/scripts/auto-dev.sh stop

# Restart all services
$POWERNODE_ROOT/scripts/auto-dev.sh restart

# Health check
$POWERNODE_ROOT/scripts/auto-dev.sh health
```

### Individual Service Scripts

```bash
# Backend service
scripts/backend-manager.sh start    # Start Rails server
scripts/backend-manager.sh stop     # Stop Rails server
scripts/backend-manager.sh restart  # Restart Rails server
scripts/backend-manager.sh status   # Check backend status

# Worker service
scripts/worker-manager.sh start     # Start Sidekiq worker
scripts/worker-manager.sh stop      # Stop Sidekiq worker
scripts/worker-manager.sh restart   # Restart Sidekiq worker
scripts/worker-manager.sh status    # Check worker status

# Frontend service
./frontend/scripts/dev-server.sh    # Start React dev server
```

## Network Access

Both servers are configured to bind to all network interfaces (0.0.0.0), making them accessible from:

### Local Access
- **Backend API**: http://localhost:3000
- **Frontend**: http://localhost:3001

### Domain Access (with local DNS/hosts configuration)
- **Backend API**: http://powernode.dev:3000
- **Frontend**: http://powernode.dev:3001

### Network Access
- **Backend API**: http://[YOUR_IP]:3000
- **Frontend**: http://[YOUR_IP]:3001

Replace `[YOUR_IP]` with your machine's IP address on your local network.

### Setting up powernode.dev locally

To use the powernode.dev domain locally, add this to your `/etc/hosts` file:
```
127.0.0.1 powernode.dev
```

On Windows, edit `C:\Windows\System32\drivers\etc\hosts`

## Configuration Details

### Backend (Rails API)
- **Port**: 3000
- **Binding**: 0.0.0.0 (all interfaces)
- **CORS**: Configured for localhost and powernode.dev domains
- **Host restrictions**: Cleared for development mode

### Frontend (React)
- **Port**: 3001
- **Binding**: 0.0.0.0 (all interfaces)
- **API URL**: Configurable via environment variables
- **Environment**: Uses `.env.development` for configuration

### Environment Variables

Frontend environment variables in `.env.development`:
```env
HOST=0.0.0.0
PORT=3001
BROWSER=none
REACT_APP_API_BASE_URL=http://localhost:3000
REACT_APP_ALLOWED_HOSTS=localhost,127.0.0.1,powernode.dev
REACT_APP_ENVIRONMENT=development
GENERATE_SOURCEMAP=true
```

## Network Security

**Important**: This configuration is for development only. In production:
- CORS is restricted to specific trusted domains
- Host binding should be more restrictive
- Additional security headers should be configured
- Environment variables should be properly secured

## Troubleshooting

### Cannot Access from Network
1. Check your firewall settings
2. Ensure both servers show "binding to 0.0.0.0" in their startup logs
3. Verify your IP address with `hostname -I`
4. Test with curl: `curl http://YOUR_IP:3000/api/v1/health`

### CORS Issues
- Backend CORS is configured for localhost and powernode.dev domains
- If issues persist, check browser developer tools for specific errors
- Ensure the API URL in frontend matches your setup

### Domain Resolution Issues
- Verify `/etc/hosts` file contains the powernode.dev entry
- Clear browser DNS cache
- Try accessing via direct IP if domain doesn't resolve

### Port Conflicts
- Change ports in the respective configuration files if needed
- Backend: modify the `-p` flag in server scripts
- Frontend: modify `PORT` in `.env.development`

---

## Additional Development Commands

```bash
# Database operations
cd $POWERNODE_ROOT/server && rails db:migrate db:seed

# Backend tests
pkill -f rspec 2>/dev/null || true && bundle exec rspec

# Frontend tests
cd $POWERNODE_ROOT/frontend && CI=true npm test

# Type checking
cd $POWERNODE_ROOT/frontend && npm run typecheck
```

## Reference

For complete development workflow documentation, see the main [CLAUDE.md](../CLAUDE.md) file which contains:
- Service management rules
- Testing requirements
- Code quality enforcement
- Git workflow guidelines
