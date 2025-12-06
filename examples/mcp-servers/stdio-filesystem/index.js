#!/usr/bin/env node
/**
 * MCP Filesystem Server
 *
 * An example MCP server that provides filesystem operations.
 * Demonstrates permission scopes, security constraints, and advanced tool patterns.
 *
 * Connection Type: stdio
 * Tools: list_directory, read_file, write_file, file_info, search_files
 *
 * Security: Operations are restricted to allowed directories (configurable via env)
 *
 * Usage:
 *   ALLOWED_PATHS="/tmp,/home/user/documents" node index.js
 *
 * Or register in Powernode as an MCP server with:
 *   connection_type: stdio
 *   command: node
 *   args: ["/path/to/examples/mcp-servers/stdio-filesystem/index.js"]
 *   env: { "ALLOWED_PATHS": "/tmp,/home/user/sandbox" }
 */

const { McpBaseServer } = require('../shared/mcp-base');
const fs = require('fs').promises;
const path = require('path');

// Get allowed paths from environment (defaults to temp directory only)
const ALLOWED_PATHS = (process.env.ALLOWED_PATHS || '/tmp')
  .split(',')
  .map(p => path.resolve(p.trim()));

const MAX_FILE_SIZE = parseInt(process.env.MAX_FILE_SIZE || '1048576', 10); // 1MB default

// Create server instance
const server = new McpBaseServer({
  name: 'filesystem-server',
  version: '1.0.0',
  description: 'A filesystem MCP server with sandboxed access to specified directories'
});

/**
 * Security: Validate that a path is within allowed directories
 */
function validatePath(targetPath) {
  const resolved = path.resolve(targetPath);

  const isAllowed = ALLOWED_PATHS.some(allowedPath => {
    return resolved === allowedPath || resolved.startsWith(allowedPath + path.sep);
  });

  if (!isAllowed) {
    throw new Error(`Access denied: Path "${resolved}" is outside allowed directories`);
  }

  return resolved;
}

/**
 * Format file size for display
 */
function formatSize(bytes) {
  const units = ['B', 'KB', 'MB', 'GB'];
  let size = bytes;
  let unitIndex = 0;

  while (size >= 1024 && unitIndex < units.length - 1) {
    size /= 1024;
    unitIndex++;
  }

  return `${size.toFixed(2)} ${units[unitIndex]}`;
}

// Register tools
server.registerTool({
  name: 'list_directory',
  description: 'List files and directories in a specified path',
  inputSchema: {
    type: 'object',
    properties: {
      path: {
        type: 'string',
        description: 'Directory path to list (must be within allowed directories)'
      },
      include_hidden: {
        type: 'boolean',
        description: 'Include hidden files (starting with dot)',
        default: false
      }
    },
    required: ['path']
  },
  permissionLevel: 'public',
  allowedScopes: {
    file_access: ['list_directories']
  },
  handler: async ({ path: dirPath, include_hidden = false }) => {
    const safePath = validatePath(dirPath);

    const entries = await fs.readdir(safePath, { withFileTypes: true });

    const items = await Promise.all(
      entries
        .filter(entry => include_hidden || !entry.name.startsWith('.'))
        .map(async (entry) => {
          const fullPath = path.join(safePath, entry.name);
          let stats;

          try {
            stats = await fs.stat(fullPath);
          } catch {
            stats = null;
          }

          return {
            name: entry.name,
            type: entry.isDirectory() ? 'directory' : 'file',
            size: stats ? formatSize(stats.size) : 'unknown',
            sizeBytes: stats?.size || 0,
            modified: stats?.mtime?.toISOString() || null
          };
        })
    );

    // Sort: directories first, then alphabetically
    items.sort((a, b) => {
      if (a.type !== b.type) {
        return a.type === 'directory' ? -1 : 1;
      }
      return a.name.localeCompare(b.name);
    });

    return {
      path: safePath,
      count: items.length,
      items
    };
  }
});

server.registerTool({
  name: 'read_file',
  description: 'Read the contents of a text file',
  inputSchema: {
    type: 'object',
    properties: {
      path: {
        type: 'string',
        description: 'File path to read'
      },
      encoding: {
        type: 'string',
        description: 'File encoding (default: utf8)',
        default: 'utf8'
      },
      max_lines: {
        type: 'integer',
        description: 'Maximum number of lines to read (optional)'
      }
    },
    required: ['path']
  },
  permissionLevel: 'account',
  allowedScopes: {
    file_access: ['read_files']
  },
  handler: async ({ path: filePath, encoding = 'utf8', max_lines }) => {
    const safePath = validatePath(filePath);

    // Check file size before reading
    const stats = await fs.stat(safePath);

    if (!stats.isFile()) {
      throw new Error('Path is not a file');
    }

    if (stats.size > MAX_FILE_SIZE) {
      throw new Error(`File too large (${formatSize(stats.size)}). Maximum allowed: ${formatSize(MAX_FILE_SIZE)}`);
    }

    let content = await fs.readFile(safePath, encoding);

    if (max_lines) {
      const lines = content.split('\n');
      content = lines.slice(0, max_lines).join('\n');
      if (lines.length > max_lines) {
        content += `\n... (${lines.length - max_lines} more lines)`;
      }
    }

    return {
      path: safePath,
      size: formatSize(stats.size),
      lines: content.split('\n').length,
      content
    };
  }
});

server.registerTool({
  name: 'write_file',
  description: 'Write content to a file (creates or overwrites)',
  inputSchema: {
    type: 'object',
    properties: {
      path: {
        type: 'string',
        description: 'File path to write'
      },
      content: {
        type: 'string',
        description: 'Content to write to the file'
      },
      append: {
        type: 'boolean',
        description: 'Append to file instead of overwriting',
        default: false
      }
    },
    required: ['path', 'content']
  },
  permissionLevel: 'account',
  requiredPermissions: ['files.write'],
  allowedScopes: {
    file_access: ['write_files']
  },
  handler: async ({ path: filePath, content, append = false }) => {
    const safePath = validatePath(filePath);

    // Ensure directory exists
    const dir = path.dirname(safePath);
    await fs.mkdir(dir, { recursive: true });

    if (append) {
      await fs.appendFile(safePath, content, 'utf8');
    } else {
      await fs.writeFile(safePath, content, 'utf8');
    }

    const stats = await fs.stat(safePath);

    return {
      path: safePath,
      size: formatSize(stats.size),
      mode: append ? 'appended' : 'written',
      success: true
    };
  }
});

server.registerTool({
  name: 'delete_file',
  description: 'Delete a file or empty directory',
  inputSchema: {
    type: 'object',
    properties: {
      path: {
        type: 'string',
        description: 'Path to delete'
      }
    },
    required: ['path']
  },
  permissionLevel: 'admin',
  requiredPermissions: ['files.delete'],
  allowedScopes: {
    file_access: ['delete_files']
  },
  handler: async ({ path: targetPath }) => {
    const safePath = validatePath(targetPath);

    const stats = await fs.stat(safePath);

    if (stats.isDirectory()) {
      // Only delete empty directories
      const entries = await fs.readdir(safePath);
      if (entries.length > 0) {
        throw new Error('Directory is not empty. Remove contents first.');
      }
      await fs.rmdir(safePath);
    } else {
      await fs.unlink(safePath);
    }

    return {
      path: safePath,
      deleted: true,
      type: stats.isDirectory() ? 'directory' : 'file'
    };
  }
});

server.registerTool({
  name: 'file_info',
  description: 'Get detailed information about a file or directory',
  inputSchema: {
    type: 'object',
    properties: {
      path: {
        type: 'string',
        description: 'Path to get info for'
      }
    },
    required: ['path']
  },
  permissionLevel: 'public',
  allowedScopes: {
    file_access: ['list_directories']
  },
  handler: async ({ path: targetPath }) => {
    const safePath = validatePath(targetPath);

    const stats = await fs.stat(safePath);

    return {
      path: safePath,
      name: path.basename(safePath),
      type: stats.isDirectory() ? 'directory' : 'file',
      size: formatSize(stats.size),
      sizeBytes: stats.size,
      created: stats.birthtime.toISOString(),
      modified: stats.mtime.toISOString(),
      accessed: stats.atime.toISOString(),
      permissions: stats.mode.toString(8).slice(-3),
      isSymlink: stats.isSymbolicLink()
    };
  }
});

server.registerTool({
  name: 'search_files',
  description: 'Search for files matching a pattern in a directory',
  inputSchema: {
    type: 'object',
    properties: {
      path: {
        type: 'string',
        description: 'Directory to search in'
      },
      pattern: {
        type: 'string',
        description: 'Search pattern (supports * wildcard)'
      },
      recursive: {
        type: 'boolean',
        description: 'Search subdirectories',
        default: false
      },
      max_results: {
        type: 'integer',
        description: 'Maximum number of results',
        default: 100
      }
    },
    required: ['path', 'pattern']
  },
  permissionLevel: 'account',
  allowedScopes: {
    file_access: ['list_directories', 'read_files']
  },
  handler: async ({ path: dirPath, pattern, recursive = false, max_results = 100 }) => {
    const safePath = validatePath(dirPath);

    // Convert glob pattern to regex
    const regexPattern = new RegExp(
      '^' + pattern.replace(/\*/g, '.*').replace(/\?/g, '.') + '$',
      'i'
    );

    const results = [];

    async function searchDir(dir, depth = 0) {
      if (results.length >= max_results) return;
      if (depth > 10) return; // Prevent infinite recursion

      const entries = await fs.readdir(dir, { withFileTypes: true });

      for (const entry of entries) {
        if (results.length >= max_results) break;

        const fullPath = path.join(dir, entry.name);

        if (regexPattern.test(entry.name)) {
          const stats = await fs.stat(fullPath);
          results.push({
            path: fullPath,
            name: entry.name,
            type: entry.isDirectory() ? 'directory' : 'file',
            size: formatSize(stats.size),
            modified: stats.mtime.toISOString()
          });
        }

        if (recursive && entry.isDirectory()) {
          try {
            await searchDir(fullPath, depth + 1);
          } catch {
            // Skip inaccessible directories
          }
        }
      }
    }

    await searchDir(safePath);

    return {
      searchPath: safePath,
      pattern,
      count: results.length,
      truncated: results.length >= max_results,
      results
    };
  }
});

// Register resources for configuration info
server.registerResource({
  uri: 'filesystem://config',
  name: 'Filesystem Configuration',
  description: 'Current filesystem server configuration',
  mimeType: 'application/json'
});

// Log configuration on startup
server.log(`Allowed paths: ${ALLOWED_PATHS.join(', ')}`);
server.log(`Max file size: ${formatSize(MAX_FILE_SIZE)}`);

// Start the server
server.startStdio();
