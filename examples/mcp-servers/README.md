# Example MCP Servers

This directory contains example MCP (Model Context Protocol) servers that demonstrate how to build and integrate MCP tools with the Powernode platform.

## Overview

MCP (Model Context Protocol) is a standardized protocol for AI tool integration. These example servers demonstrate:

- **stdio connection**: Communication via stdin/stdout (for local tools)
- **HTTP connection**: REST-based communication (for remote services)
- **Permission scopes**: Fine-grained access control
- **Tool patterns**: Input validation, error handling, async operations

## Example Servers

### 1. Calculator Server (stdio)

A simple calculator providing arithmetic operations.

**Location**: `stdio-calculator/`

**Tools**:
| Tool | Description | Permission |
|------|-------------|------------|
| `add` | Add two numbers | public |
| `subtract` | Subtract numbers | public |
| `multiply` | Multiply numbers | public |
| `divide` | Divide numbers | public |
| `power` | Exponentiation | public |
| `sqrt` | Square root | public |
| `modulo` | Remainder | public |
| `calculate` | Evaluate expression | account |

**Usage**:
```bash
# Run directly
node stdio-calculator/index.js

# Test with JSON-RPC
echo '{"jsonrpc":"2.0","method":"tools/list","params":{},"id":1}' | node stdio-calculator/index.js
```

**Register in Powernode**:
```json
{
  "name": "Calculator",
  "connection_type": "stdio",
  "command": "node",
  "args": ["/path/to/examples/mcp-servers/stdio-calculator/index.js"]
}
```

---

### 2. Filesystem Server (stdio)

Sandboxed filesystem operations with security constraints.

**Location**: `stdio-filesystem/`

**Tools**:
| Tool | Description | Permission | Scopes |
|------|-------------|------------|--------|
| `list_directory` | List files/dirs | public | file_access:list_directories |
| `read_file` | Read file contents | account | file_access:read_files |
| `write_file` | Write to file | account | file_access:write_files |
| `delete_file` | Delete file/dir | admin | file_access:delete_files |
| `file_info` | Get file metadata | public | file_access:list_directories |
| `search_files` | Search by pattern | account | file_access:list_directories,read_files |

**Environment Variables**:
- `ALLOWED_PATHS`: Comma-separated list of allowed directories (default: `/tmp`)
- `MAX_FILE_SIZE`: Maximum file size in bytes (default: 1MB)

**Usage**:
```bash
# Run with sandbox
ALLOWED_PATHS="/tmp,/home/user/sandbox" node stdio-filesystem/index.js

# Test
echo '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"list_directory","arguments":{"path":"/tmp"}},"id":1}' | node stdio-filesystem/index.js
```

**Register in Powernode**:
```json
{
  "name": "Filesystem",
  "connection_type": "stdio",
  "command": "node",
  "args": ["/path/to/examples/mcp-servers/stdio-filesystem/index.js"],
  "env": {
    "ALLOWED_PATHS": "/tmp",
    "MAX_FILE_SIZE": "1048576"
  }
}
```

---

### 3. Weather Server (HTTP)

Weather information via HTTP endpoint.

**Location**: `http-weather/`

**Tools**:
| Tool | Description | Permission |
|------|-------------|------------|
| `get_weather` | Current conditions | public |
| `get_forecast` | Multi-day forecast | public |
| `search_location` | Find locations | public |

**Environment Variables**:
- `PORT`: HTTP server port (default: 3100)

**Usage**:
```bash
# Start server
node http-weather/index.js

# Health check
curl http://localhost:3100/health

# Call tool via JSON-RPC
curl -X POST http://localhost:3100 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"get_weather","arguments":{"location":"New York"}},"id":1}'
```

**Register in Powernode**:
```json
{
  "name": "Weather",
  "connection_type": "http",
  "url": "http://localhost:3100"
}
```

---

## Shared Base Class

The `shared/mcp-base.js` module provides a reusable base class for building MCP servers:

```javascript
const { McpBaseServer } = require('./shared/mcp-base');

const server = new McpBaseServer({
  name: 'my-server',
  version: '1.0.0',
  description: 'My custom MCP server'
});

// Register tools
server.registerTool({
  name: 'my_tool',
  description: 'Does something useful',
  inputSchema: {
    type: 'object',
    properties: {
      param: { type: 'string', description: 'A parameter' }
    },
    required: ['param']
  },
  permissionLevel: 'public',
  handler: async ({ param }) => {
    return { result: `Processed: ${param}` };
  }
});

// Start in stdio mode
server.startStdio();
```

---

## MCP Protocol Reference

### JSON-RPC 2.0 Format

All MCP messages use JSON-RPC 2.0:

```json
{
  "jsonrpc": "2.0",
  "method": "method_name",
  "params": {},
  "id": 1
}
```

### Core Methods

| Method | Purpose |
|--------|---------|
| `initialize` | Handshake and capability exchange |
| `initialized` | Acknowledge initialization |
| `ping` | Health check |
| `tools/list` | List available tools |
| `tools/call` | Execute a tool |
| `resources/list` | List available resources |
| `resources/read` | Read a resource |

### Tool Response Format

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "content": [
      {
        "type": "text",
        "text": "Tool output here"
      }
    ]
  }
}
```

---

## Permission Levels

| Level | Description |
|-------|-------------|
| `public` | Available to all authenticated users |
| `account` | Requires account-level permissions |
| `admin` | Requires admin permissions |

## Permission Scopes

```javascript
allowedScopes: {
  file_access: ['read_files', 'write_files', 'delete_files', 'list_directories'],
  network: ['http_get', 'http_post', 'external_api', 'email_send'],
  data: ['read_user_data', 'read_account_data', 'read_credentials'],
  system: ['execute_commands', 'environment_access'],
  ai: ['call_other_agents', 'modify_workflow']
}
```

---

## Database Seeding

To seed example MCP servers for testing:

```bash
cd server
rails runner "require_relative 'db/seeds/mcp_example_servers'"
```

Or add to your seeds.rb:
```ruby
require_relative 'seeds/mcp_example_servers'
```

---

## Creating Your Own MCP Server

1. **Create server file** using the base class or implement protocol directly
2. **Define tools** with input schemas, descriptions, and handlers
3. **Set permissions** appropriate to tool capabilities
4. **Register in Powernode** via API or UI
5. **Connect and discover** tools automatically

### Best Practices

- Always validate inputs against schema
- Use appropriate permission levels
- Handle errors gracefully with meaningful messages
- Log to stderr (not stdout) in stdio mode
- Implement health checks for reliability
- Document tools with clear descriptions

---

## Troubleshooting

### stdio server not responding
- Check that the command path is absolute
- Verify Node.js is installed and accessible
- Check stderr output for errors

### HTTP server connection failed
- Verify the server is running on the specified port
- Check firewall/network settings
- Try the `/health` endpoint directly

### Permission denied errors
- Check user has required permissions
- Verify tool permission level settings
- Check allowed scopes configuration

---

## License

MIT License - See LICENSE file for details.
