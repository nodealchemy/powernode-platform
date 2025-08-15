# Powernode Process Management Scripts

This directory contains robust screen-based process management scripts designed to prevent port conflicts and ensure clean server startups during development.

## 🎯 Purpose

The scripts solve common development issues:
- Port conflicts when servers don't shut down properly
- Orphaned background processes consuming resources
- Inconsistent server startup procedures
- Claude Code automation reliability and timeout issues

## 📜 Scripts Overview

### `backend-manager.sh`
**Rails Backend Server Management**
- Screen-based process management (no timeout issues)
- Comprehensive process detection and cleanup
- Health checking with API endpoints
- External access configuration (0.0.0.0 binding)
- Interactive session attachment capabilities

```bash
# Available commands
./scripts/backend-manager.sh {start|stop|restart|status|logs|follow|screen}
```

### `frontend-manager.sh`
**React Frontend Server Management**
- Screen-based process management (consistent with backend)
- Multi-level process detection (npm -> node -> react-scripts)
- Cache clearing and optimization features
- External access configuration (0.0.0.0 binding)
- Interactive session attachment capabilities

```bash
# Available commands
./scripts/frontend-manager.sh {start|stop|restart|status|logs|follow|clear-cache|screen}
```

### `auto-dev.sh`
**Automation-Friendly Development Environment Manager**
- Automatic health checking and server startup
- Designed specifically for Claude Code integration
- Uses the individual manager scripts internally
- Fast status checking with minimal overhead
- Environment validation and verification

```bash
# Available commands
./scripts/auto-dev.sh {ensure|backend|frontend|status|restart|check}
```

## 🔧 Usage Examples

### Individual Server Control
```bash
# Backend server management
./scripts/backend-manager.sh start    # Start Rails server in screen session
./scripts/backend-manager.sh status   # Check server health
./scripts/backend-manager.sh screen   # Attach to interactive session
./scripts/backend-manager.sh logs     # View recent logs

# Frontend server management
./scripts/frontend-manager.sh start   # Start React server in screen session
./scripts/frontend-manager.sh status  # Check server health
./scripts/frontend-manager.sh screen  # Attach to interactive session
./scripts/frontend-manager.sh logs    # View recent logs
```

### Automated Environment Management
```bash
# Ensure both servers are running (preferred for automation)
./scripts/auto-dev.sh ensure         # Start servers if needed
./scripts/auto-dev.sh status         # Quick health check
./scripts/auto-dev.sh restart        # Restart both servers
./scripts/auto-dev.sh backend        # Ensure only backend is running
./scripts/auto-dev.sh frontend       # Ensure only frontend is running
```

### Interactive Session Access
```bash
# Attach to running servers for debugging/monitoring
./scripts/backend-manager.sh screen   # Interactive Rails console access
./scripts/frontend-manager.sh screen  # Interactive React dev server access

# Detach: Ctrl+A, then D (standard screen commands)
```

## 🤖 Claude Code Integration

For AI assistance tools like Claude Code, the scripts provide timeout-free automation:

```bash
# Recommended approach for automation
./scripts/auto-dev.sh ensure    # Automatically start needed servers
./scripts/auto-dev.sh status    # Verify environment health
```

**Benefits for Claude Code:**
- **No timeout issues** - Screen sessions detach cleanly
- **Reliable startup** - Comprehensive process detection
- **Health checking** - API-based verification
- **Consistent interface** - Same commands across all scripts

## 📊 Process Detection & Management

### Backend Processes (Rails)
- **Port binding detection** - `lsof -ti :3000`
- **Process name patterns** - `rails server`, `puma`, `bundle.*rails`
- **Screen session processes** - `SCREEN.*powernode-backend`
- **PID file detection** - Rails temporary PID files
- **Health endpoint** - `http://localhost:3000/api/v1/health`

### Frontend Processes (React)
- **Port binding detection** - `lsof -ti :3001`
- **Process name patterns** - `react-scripts.*start`, `npm.*start`
- **Screen session processes** - `SCREEN.*powernode-frontend`
- **Parent-child relationships** - npm → node → react-scripts
- **HTTP response check** - `http://localhost:3001`

## 🚨 Port Management & External Access

**Managed Ports (all configured for external access on 0.0.0.0):**
- **3000** - Rails backend API (accessible from any IP)
- **3001** - React frontend development server (accessible from any IP)

**Access URLs:**
- **Local**: `http://localhost:3000` (backend), `http://localhost:3001` (frontend)
- **External**: `http://[HOST_IP]:3000` (backend), `http://[HOST_IP]:3001` (frontend)
- **Container/VM/Remote**: Accessible from host machine and other networked systems

## 📁 Screen Session Management

**Active Sessions:**
- `powernode-backend` - Rails server session
- `powernode-frontend` - React server session

**Screen Commands:**
```bash
# List all sessions
screen -list

# Attach to specific session
screen -r powernode-backend
screen -r powernode-frontend

# Detach from session: Ctrl+A, then D
# Kill session
screen -S powernode-backend -X quit
```

## 📁 Logging

Server outputs are logged to:
- `logs/backend.log` - Rails server logs (current)
- `logs/frontend.log` - React development server logs (current)

## 🔒 Safety Features

- **Screen-based isolation** - No timeout issues with background processes
- **Graceful shutdown attempts** - SIGTERM before SIGKILL
- **Process verification** - Multiple detection methods
- **Port availability checking** - Pre-startup validation
- **Health endpoint verification** - API-based readiness checks
- **Session persistence** - Servers survive shell disconnection

## 🛠️ Architecture Evolution

**Previous Approach:** nohup/background processes with complex PID management
**Current Approach:** GNU screen sessions with reliable detachment
**Benefits:** 
- No Bash tool timeouts
- Better process isolation  
- Interactive debugging capabilities
- Consistent behavior across environments

## 📋 Best Practices

1. **Use auto-dev.sh for automation** - Designed for Claude Code reliability
2. **Use individual managers for control** - Fine-grained server management
3. **Check status regularly** - Monitor server health with built-in commands
4. **Use screen sessions for debugging** - Interactive access when needed
5. **Review logs when issues occur** - Comprehensive logging for troubleshooting

## 🐛 Troubleshooting

### Common Issues

**"Port already in use"**
```bash
./scripts/backend-manager.sh stop     # or frontend-manager.sh stop
./scripts/backend-manager.sh status   # Verify cleanup
```

**"Server won't start"**
```bash
# Check logs
./scripts/backend-manager.sh logs
./scripts/frontend-manager.sh logs

# Check screen sessions
screen -list

# Check prerequisites
cd server && bundle install
cd frontend && npm install
```

**"Screen session issues"**
```bash
# List sessions
screen -list

# Kill problematic sessions
screen -S powernode-backend -X quit
screen -S powernode-frontend -X quit

# Restart cleanly
./scripts/auto-dev.sh restart
```

### Advanced Debugging
```bash
# Manual process inspection
./scripts/backend-manager.sh status
./scripts/frontend-manager.sh status

# Check port usage
lsof -i :3000
lsof -i :3001

# Monitor screen sessions
screen -r powernode-backend    # Interactive Rails logs
screen -r powernode-frontend   # Interactive React logs
```

This screen-based process management system ensures reliable, timeout-free development server management for the Powernode platform with excellent automation compatibility for AI assistants like Claude Code.