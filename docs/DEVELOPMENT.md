# Development Guide

This guide covers how to run the Powernode platform in development mode.

## Quick Start

### Recommended: Systemd Services

```bash
# First-time setup (installs units and config to /etc/powernode/)
sudo scripts/systemd/powernode-installer.sh install

# Start all services
sudo systemctl start powernode.target

# Check service status
sudo scripts/systemd/powernode-installer.sh status

# Stop all services
sudo systemctl stop powernode.target

# Restart a specific service
sudo systemctl restart powernode-backend@default
```

### Individual Service Control

```bash
# Start/stop/restart individual services
sudo systemctl start powernode-backend@default
sudo systemctl start powernode-worker@default
sudo systemctl start powernode-worker-web@default
sudo systemctl start powernode-frontend@default

# View logs for a specific service
journalctl -u powernode-backend@default -f
journalctl -u powernode-worker@default -f
journalctl -u powernode-frontend@default -f

# View all Powernode logs
journalctl -u 'powernode-*' --since "5 min ago"
```

## Network Access

All servers are configured to bind to all network interfaces (0.0.0.0), making them accessible from:

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
- **Config**: `/etc/powernode/backend-default.conf`

### Frontend (React)
- **Port**: 3001
- **Binding**: 0.0.0.0 (all interfaces)
- **API URL**: Configurable via environment variables
- **Environment**: Uses `.env.development` for configuration
- **Config**: `/etc/powernode/frontend-default.conf`

### Worker (Sidekiq)
- **Redis**: `redis://localhost:6379/1`
- **Concurrency**: 5 threads (configurable)
- **Config**: `/etc/powernode/worker-default.conf`

### Worker Web UI (Sidekiq Dashboard)
- **Port**: 4567
- **Config**: `/etc/powernode/worker-web-default.conf`

### Global Configuration
- **Config**: `/etc/powernode/powernode.conf`
- Contains: base path, RVM/nvm paths, Ruby/Node versions, operating mode

## Multi-Instance Support

Run multiple instances of any service on different ports:

```bash
# Add a second backend instance
sudo scripts/systemd/powernode-installer.sh add-instance backend api2
# Edit /etc/powernode/backend-api2.conf → set PORT=3002
sudo systemctl enable --now powernode-backend@api2

# Add a high-concurrency worker for AI workloads
sudo scripts/systemd/powernode-installer.sh add-instance worker ai-heavy
# Edit /etc/powernode/worker-ai-heavy.conf → set WORKER_CONCURRENCY=15
sudo systemctl enable --now powernode-worker@ai-heavy
```

## Network Security

**Important**: This configuration is for development only. In production:
- CORS is restricted to specific trusted domains
- Host binding should be more restrictive
- Additional security headers should be configured
- Environment variables should be properly secured

## Troubleshooting

### Services Won't Start

```bash
# Check specific service logs
journalctl -u powernode-backend@default --since "5 min ago" --no-pager

# Reset failed state and retry
sudo systemctl reset-failed 'powernode-*'
sudo systemctl start powernode.target
```

### CORS Issues
- Backend CORS is configured for localhost and powernode.dev domains
- If issues persist, check browser developer tools for specific errors
- Ensure the API URL in frontend matches your setup

### Domain Resolution Issues
- Verify `/etc/hosts` file contains the powernode.dev entry
- Clear browser DNS cache
- Try accessing via direct IP if domain doesn't resolve

### Port Conflicts
- Check what's using a port: `ss -tlnp | grep :3000`
- Change ports in `/etc/powernode/backend-default.conf` (or other service config)
- Reload: `sudo systemctl daemon-reload && sudo systemctl restart powernode-backend@default`

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
