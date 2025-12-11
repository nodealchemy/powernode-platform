# frozen_string_literal: true

# MCP Server Seeds
# Creates example MCP servers with tools for demonstration and testing

puts "\n" + '=' * 80
puts 'MCP SERVERS - Creating Example Servers'
puts '=' * 80

# Find admin account
account = Account.find_by(subdomain: 'admin')
unless account
  puts '❌ Error: Admin account not found. Run main seeds first.'
  return
end

puts "✓ Using admin account: #{account.name} (ID: #{account.id})"

# =============================================================================
# MCP SERVER 1: Filesystem MCP Server
# =============================================================================

puts "\n" + '-' * 60
puts '1. Filesystem MCP Server'
puts '-' * 60

filesystem_server = McpServer.find_or_create_by!(account: account, name: 'Filesystem MCP') do |server|
  server.description = 'File system operations - read, write, list, and search files'
  server.status = 'connected'
  server.connection_type = 'stdio'
  server.auth_type = 'none'
  server.command = 'npx'
  server.args = ['-y', '@anthropic-ai/mcp-server-filesystem']
  server.env = { 'MCP_ALLOWED_DIRS' => '/tmp,/home' }
  server.capabilities = {
    'tools' => true,
    'resources' => true,
    'prompts' => false,
    'version' => '1.0.0'
  }
end

# Create tools for filesystem server
filesystem_tools = [
  {
    name: 'read_file',
    description: 'Read the contents of a file at the specified path',
    input_schema: {
      'type' => 'object',
      'properties' => {
        'path' => { 'type' => 'string', 'description' => 'Path to the file to read' }
      },
      'required' => ['path']
    },
    permission_level: 'account'
  },
  {
    name: 'write_file',
    description: 'Write content to a file at the specified path',
    input_schema: {
      'type' => 'object',
      'properties' => {
        'path' => { 'type' => 'string', 'description' => 'Path to the file to write' },
        'content' => { 'type' => 'string', 'description' => 'Content to write to the file' }
      },
      'required' => ['path', 'content']
    },
    permission_level: 'admin'
  },
  {
    name: 'list_directory',
    description: 'List all files and directories in a specified path',
    input_schema: {
      'type' => 'object',
      'properties' => {
        'path' => { 'type' => 'string', 'description' => 'Path to the directory to list' }
      },
      'required' => ['path']
    },
    permission_level: 'account'
  },
  {
    name: 'search_files',
    description: 'Search for files matching a pattern',
    input_schema: {
      'type' => 'object',
      'properties' => {
        'path' => { 'type' => 'string', 'description' => 'Base path to search from' },
        'pattern' => { 'type' => 'string', 'description' => 'Glob pattern to match files' }
      },
      'required' => ['path', 'pattern']
    },
    permission_level: 'account'
  }
]

filesystem_tools.each do |tool_data|
  McpTool.find_or_create_by!(mcp_server: filesystem_server, name: tool_data[:name]) do |tool|
    tool.description = tool_data[:description]
    tool.input_schema = tool_data[:input_schema]
    tool.permission_level = tool_data[:permission_level]
    tool.enabled = true
  end
end

puts "✓ Created Filesystem MCP Server (#{filesystem_server.mcp_tools.count} tools)"

# =============================================================================
# MCP SERVER 2: Content Enhancement MCP Server
# =============================================================================

puts "\n" + '-' * 60
puts '2. Content Enhancement MCP Server'
puts '-' * 60

content_server = McpServer.find_or_create_by!(account: account, name: 'Content Enhancement MCP') do |server|
  server.description = 'AI-powered content enhancement tools for writing and editing'
  server.status = 'connected'
  server.connection_type = 'http'
  server.auth_type = 'none'
  server.command = 'http://localhost:8080/mcp/content'
  server.env = { 'MCP_URL' => 'http://localhost:8080/mcp/content' }
  server.capabilities = {
    'tools' => true,
    'resources' => true,
    'prompts' => true,
    'version' => '1.0.0'
  }
end

content_tools = [
  {
    name: 'content_enhancer',
    description: 'Enhance content quality, grammar, and readability',
    input_schema: {
      'type' => 'object',
      'properties' => {
        'content' => { 'type' => 'string', 'description' => 'Content to enhance' },
        'style' => { 'type' => 'string', 'enum' => ['formal', 'casual', 'technical'], 'description' => 'Writing style' },
        'tone' => { 'type' => 'string', 'enum' => ['professional', 'friendly', 'neutral'], 'description' => 'Desired tone' }
      },
      'required' => ['content']
    },
    permission_level: 'account'
  },
  {
    name: 'seo_optimizer',
    description: 'Optimize content for search engines',
    input_schema: {
      'type' => 'object',
      'properties' => {
        'content' => { 'type' => 'string', 'description' => 'Content to optimize' },
        'target_keywords' => { 'type' => 'array', 'items' => { 'type' => 'string' }, 'description' => 'Target keywords' },
        'max_length' => { 'type' => 'integer', 'description' => 'Maximum content length' }
      },
      'required' => ['content']
    },
    permission_level: 'account'
  },
  {
    name: 'summarize',
    description: 'Create a summary of long content',
    input_schema: {
      'type' => 'object',
      'properties' => {
        'content' => { 'type' => 'string', 'description' => 'Content to summarize' },
        'max_sentences' => { 'type' => 'integer', 'description' => 'Maximum sentences in summary' },
        'style' => { 'type' => 'string', 'enum' => ['bullet', 'paragraph', 'tldr'], 'description' => 'Summary format' }
      },
      'required' => ['content']
    },
    permission_level: 'account'
  },
  {
    name: 'translate',
    description: 'Translate content to another language',
    input_schema: {
      'type' => 'object',
      'properties' => {
        'content' => { 'type' => 'string', 'description' => 'Content to translate' },
        'target_language' => { 'type' => 'string', 'description' => 'Target language code (e.g., es, fr, de)' },
        'preserve_formatting' => { 'type' => 'boolean', 'description' => 'Preserve original formatting' }
      },
      'required' => ['content', 'target_language']
    },
    permission_level: 'account'
  }
]

content_tools.each do |tool_data|
  McpTool.find_or_create_by!(mcp_server: content_server, name: tool_data[:name]) do |tool|
    tool.description = tool_data[:description]
    tool.input_schema = tool_data[:input_schema]
    tool.permission_level = tool_data[:permission_level]
    tool.enabled = true
  end
end

puts "✓ Created Content Enhancement MCP Server (#{content_server.mcp_tools.count} tools)"

# =============================================================================
# MCP SERVER 3: Database MCP Server
# =============================================================================

puts "\n" + '-' * 60
puts '3. Database MCP Server'
puts '-' * 60

database_server = McpServer.find_or_create_by!(account: account, name: 'Database MCP') do |server|
  server.description = 'Database operations - query, insert, update, and manage data'
  server.status = 'connected'
  server.connection_type = 'stdio'
  server.auth_type = 'none'
  server.command = 'npx'
  server.args = ['-y', '@anthropic-ai/mcp-server-postgres']
  server.env = { 'DATABASE_URL' => 'postgresql://localhost/powernode_development' }
  server.capabilities = {
    'tools' => true,
    'resources' => true,
    'prompts' => false,
    'version' => '1.0.0'
  }
end

database_tools = [
  {
    name: 'query',
    description: 'Execute a read-only SQL query',
    input_schema: {
      'type' => 'object',
      'properties' => {
        'sql' => { 'type' => 'string', 'description' => 'SQL query to execute' },
        'params' => { 'type' => 'array', 'description' => 'Query parameters' }
      },
      'required' => ['sql']
    },
    permission_level: 'admin'
  },
  {
    name: 'list_tables',
    description: 'List all tables in the database',
    input_schema: {
      'type' => 'object',
      'properties' => {
        'schema' => { 'type' => 'string', 'description' => 'Schema name (default: public)' }
      }
    },
    permission_level: 'account'
  },
  {
    name: 'describe_table',
    description: 'Get the schema of a specific table',
    input_schema: {
      'type' => 'object',
      'properties' => {
        'table_name' => { 'type' => 'string', 'description' => 'Name of the table' }
      },
      'required' => ['table_name']
    },
    permission_level: 'account'
  }
]

database_tools.each do |tool_data|
  McpTool.find_or_create_by!(mcp_server: database_server, name: tool_data[:name]) do |tool|
    tool.description = tool_data[:description]
    tool.input_schema = tool_data[:input_schema]
    tool.permission_level = tool_data[:permission_level]
    tool.enabled = true
  end
end

puts "✓ Created Database MCP Server (#{database_server.mcp_tools.count} tools)"

# =============================================================================
# MCP SERVER 4: Web Fetch MCP Server
# =============================================================================

puts "\n" + '-' * 60
puts '4. Web Fetch MCP Server'
puts '-' * 60

web_server = McpServer.find_or_create_by!(account: account, name: 'Web Fetch MCP') do |server|
  server.description = 'Web content fetching and processing tools'
  server.status = 'connected'
  server.connection_type = 'stdio'
  server.auth_type = 'none'
  server.command = 'npx'
  server.args = ['-y', '@anthropic-ai/mcp-server-fetch']
  server.env = {}
  server.capabilities = {
    'tools' => true,
    'resources' => false,
    'prompts' => false,
    'version' => '1.0.0'
  }
end

web_tools = [
  {
    name: 'fetch_url',
    description: 'Fetch content from a URL and return as text',
    input_schema: {
      'type' => 'object',
      'properties' => {
        'url' => { 'type' => 'string', 'format' => 'uri', 'description' => 'URL to fetch' },
        'headers' => { 'type' => 'object', 'description' => 'Optional HTTP headers' }
      },
      'required' => ['url']
    },
    permission_level: 'account'
  },
  {
    name: 'extract_text',
    description: 'Extract and clean text content from HTML',
    input_schema: {
      'type' => 'object',
      'properties' => {
        'url' => { 'type' => 'string', 'format' => 'uri', 'description' => 'URL to extract text from' },
        'selector' => { 'type' => 'string', 'description' => 'CSS selector for specific content' }
      },
      'required' => ['url']
    },
    permission_level: 'account'
  }
]

web_tools.each do |tool_data|
  McpTool.find_or_create_by!(mcp_server: web_server, name: tool_data[:name]) do |tool|
    tool.description = tool_data[:description]
    tool.input_schema = tool_data[:input_schema]
    tool.permission_level = tool_data[:permission_level]
    tool.enabled = true
  end
end

puts "✓ Created Web Fetch MCP Server (#{web_server.mcp_tools.count} tools)"

# =============================================================================
# MCP SERVER 5: Slack Integration MCP Server
# =============================================================================

puts "\n" + '-' * 60
puts '5. Slack Integration MCP Server'
puts '-' * 60

slack_server = McpServer.find_or_create_by!(account: account, name: 'Slack MCP') do |server|
  server.description = 'Slack workspace integration for messaging and notifications'
  server.status = 'disconnected'  # Requires API key setup
  server.connection_type = 'http'
  server.auth_type = 'api_key'  # API key auth for simplicity in demo
  server.command = 'https://slack.com/api/mcp'
  server.env = { 'MCP_URL' => 'https://slack.com/api/mcp', 'SLACK_BOT_TOKEN' => '' }
  server.capabilities = {
    'tools' => true,
    'resources' => false,
    'prompts' => false,
    'version' => '1.0.0',
    'requires_api_key' => true
  }
end

slack_tools = [
  {
    name: 'send_message',
    description: 'Send a message to a Slack channel',
    input_schema: {
      'type' => 'object',
      'properties' => {
        'channel' => { 'type' => 'string', 'description' => 'Channel ID or name' },
        'text' => { 'type' => 'string', 'description' => 'Message text' },
        'thread_ts' => { 'type' => 'string', 'description' => 'Thread timestamp for replies' }
      },
      'required' => ['channel', 'text']
    },
    permission_level: 'admin'
  },
  {
    name: 'list_channels',
    description: 'List available Slack channels',
    input_schema: {
      'type' => 'object',
      'properties' => {
        'types' => { 'type' => 'string', 'description' => 'Channel types (public,private)' }
      }
    },
    permission_level: 'account'
  }
]

slack_tools.each do |tool_data|
  McpTool.find_or_create_by!(mcp_server: slack_server, name: tool_data[:name]) do |tool|
    tool.description = tool_data[:description]
    tool.input_schema = tool_data[:input_schema]
    tool.permission_level = tool_data[:permission_level]
    tool.enabled = true
  end
end

puts "✓ Created Slack MCP Server (#{slack_server.mcp_tools.count} tools) - Requires OAuth setup"

# =============================================================================
# SUMMARY
# =============================================================================

puts "\n" + '=' * 80
puts 'MCP SERVERS - COMPLETE'
puts '=' * 80

total_servers = McpServer.where(account: account).count
total_tools = McpTool.joins(:mcp_server).where(mcp_servers: { account_id: account.id }).count
connected_servers = McpServer.where(account: account, status: 'connected').count

puts "\n📊 Summary:"
puts "   Total MCP Servers: #{total_servers}"
puts "   Connected Servers: #{connected_servers}"
puts "   Total Tools: #{total_tools}"

puts "\n🔧 Servers Created:"
McpServer.where(account: account).each do |server|
  status_emoji = server.connected? ? '🟢' : '🔴'
  puts "   #{status_emoji} #{server.name} (#{server.connection_type})"
  puts "      Tools: #{server.mcp_tools.count}"
  puts "      Status: #{server.status}"
end

puts "\n💡 Next Steps:"
puts "   1. Configure actual MCP server connections"
puts "   2. Set up OAuth for Slack integration"
puts "   3. Test tool execution through workflow nodes"
puts "   4. Create workflows using mcp_operation nodes"

puts "\n" + '=' * 80
