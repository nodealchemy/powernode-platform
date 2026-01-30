# frozen_string_literal: true

FactoryBot.define do
  factory :mcp_server do
    account
    sequence(:name) { |n| "MCP Server #{n} #{SecureRandom.hex(3)}" }
    description { "MCP server for testing" }
    status { 'disconnected' }
    connection_type { 'stdio' }
    auth_type { 'none' }
    command { 'node' }
    args { [ 'server.js', '--port', '3000' ] }
    env do
      {
        'NODE_ENV' => 'production',
        'LOG_LEVEL' => 'info'
      }
    end
    capabilities do
      {
        'tools' => true,
        'resources' => true,
        'prompts' => false
      }
    end
    last_health_check { nil }

    trait :connected do
      status { 'connected' }
      last_health_check { 1.minute.ago }
      capabilities do
        {
          'tools' => true,
          'resources' => true,
          'prompts' => true,
          'version' => '1.0.0',
          'protocol_version' => '2024-11-05'
        }
      end
    end

    trait :disconnected do
      status { 'disconnected' }
      last_health_check { 10.minutes.ago }
    end

    trait :connecting do
      status { 'connecting' }
      last_health_check { 30.seconds.ago }
    end

    trait :error do
      status { 'error' }
      last_health_check { 5.minutes.ago }
      capabilities do
        {
          'last_error' => 'Connection timeout',
          'error_time' => Time.current.iso8601
        }
      end
    end

    trait :stdio do
      connection_type { 'stdio' }
      command { 'npx' }
      args { [ '-y', '@modelcontextprotocol/server-filesystem', '/tmp' ] }
      env do
        {
          'MCP_SERVER_TYPE' => 'stdio',
          'LOG_LEVEL' => 'debug'
        }
      end
    end

    # Alias for backward compatibility
    trait :stdio_connection do
      connection_type { 'stdio' }
      command { 'npx' }
      args { [ '-y', '@modelcontextprotocol/server-filesystem', '/tmp' ] }
      env do
        {
          'MCP_SERVER_TYPE' => 'stdio',
          'LOG_LEVEL' => 'debug'
        }
      end
    end

    trait :websocket_connection do
      connection_type { 'websocket' }
      command { nil }
      args { [] }
      env do
        {
          'MCP_SERVER_URL' => 'ws://localhost:8080/mcp',
          'MCP_AUTH_TOKEN' => SecureRandom.hex(32)
        }
      end
    end

    trait :http_connection do
      connection_type { 'http' }
      command { nil }
      args { [] }
      env do
        {
          'MCP_SERVER_URL' => 'https://api.example.com/mcp',
          'MCP_API_KEY' => SecureRandom.hex(32)
        }
      end
    end

    trait :with_tools do
      after(:create) do |server|
        create_list(:mcp_tool, 3, mcp_server: server)
      end
    end

    trait :filesystem_server do
      name { 'Filesystem Access' }
      description { 'Provides filesystem operations for AI agents' }
      connection_type { 'stdio' }
      command { 'npx' }
      args { [ '-y', '@modelcontextprotocol/server-filesystem', '/workspace' ] }
      status { 'connected' }
      capabilities do
        {
          'tools' => true,
          'resources' => true,
          'prompts' => false,
          'capabilities' => [ 'read', 'write', 'list', 'search' ]
        }
      end
    end

    trait :database_server do
      name { 'Database Query' }
      description { 'Execute database queries safely' }
      connection_type { 'stdio' }
      command { 'python' }
      args { [ 'mcp_database_server.py' ] }
      status { 'connected' }
      capabilities do
        {
          'tools' => true,
          'resources' => false,
          'prompts' => true,
          'databases' => [ 'postgresql', 'mysql' ]
        }
      end
    end

    trait :web_search_server do
      name { 'Web Search' }
      description { 'Search the web and retrieve information' }
      connection_type { 'http' }
      command { nil }
      args { [] }
      status { 'connected' }
      env do
        {
          'MCP_SERVER_URL' => 'https://search-api.example.com',
          'API_KEY' => SecureRandom.hex(32)
        }
      end
      capabilities do
        {
          'tools' => true,
          'resources' => true,
          'prompts' => false,
          'search_engines' => [ 'google', 'bing', 'duckduckgo' ]
        }
      end
    end

    trait :needs_health_check do
      status { 'connected' }
      last_health_check { 10.minutes.ago }
    end

    trait :recently_checked do
      status { 'connected' }
      last_health_check { 30.seconds.ago }
    end

    trait :oauth2 do
      auth_type { 'oauth2' }
      oauth_client_id { SecureRandom.hex(16) }
      oauth_authorization_url { 'https://oauth.example.com/authorize' }
      oauth_token_url { 'https://oauth.example.com/token' }
    end
  end
end
