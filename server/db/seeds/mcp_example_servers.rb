# frozen_string_literal: true

# Seed file for creating example MCP servers
#
# Run with: rails db:seed:mcp_example_servers
# Or include in main seeds: require_relative 'seeds/mcp_example_servers'

module Seeds
  class McpExampleServers
    EXAMPLES_PATH = Rails.root.join('..', 'examples', 'mcp-servers').to_s

    def self.seed(account)
      new(account).seed_all
    end

    def initialize(account)
      @account = account
    end

    def seed_all
      puts "Seeding example MCP servers for account: #{@account.name}"

      seed_calculator_server
      seed_filesystem_server
      seed_weather_server
      seed_time_server
      seed_fetch_server

      puts "Done! Created #{@account.mcp_servers.count} MCP servers"
    end

    private

    def seed_calculator_server
      server = @account.mcp_servers.find_or_initialize_by(name: 'Calculator')

      server.assign_attributes(
        description: 'A simple calculator MCP server providing arithmetic operations (add, subtract, multiply, divide, power, sqrt)',
        connection_type: 'stdio',
        command: 'node',
        args: ["#{EXAMPLES_PATH}/stdio-calculator/index.js"],
        env: {},
        status: 'disconnected',
        capabilities: {
          tools: { listChanged: true },
          resources: { subscribe: false, listChanged: false },
          metadata: {
            icon: '🧮',
            author: 'Powernode',
            url: 'https://github.com/modelcontextprotocol/servers',
            version: '1.0.0'
          }
        }
      )

      if server.save
        puts "  ✓ Created/Updated: Calculator server"
        seed_calculator_tools(server)
      else
        puts "  ✗ Failed to create Calculator server: #{server.errors.full_messages.join(', ')}"
      end
    end

    def seed_calculator_tools(server)
      tools = [
        {
          name: 'add',
          description: 'Add two numbers together',
          input_schema: {
            type: 'object',
            properties: {
              a: { type: 'number', description: 'First number' },
              b: { type: 'number', description: 'Second number' }
            },
            required: %w[a b]
          },
          permission_level: 'public'
        },
        {
          name: 'subtract',
          description: 'Subtract the second number from the first',
          input_schema: {
            type: 'object',
            properties: {
              a: { type: 'number', description: 'Number to subtract from' },
              b: { type: 'number', description: 'Number to subtract' }
            },
            required: %w[a b]
          },
          permission_level: 'public'
        },
        {
          name: 'multiply',
          description: 'Multiply two numbers',
          input_schema: {
            type: 'object',
            properties: {
              a: { type: 'number', description: 'First number' },
              b: { type: 'number', description: 'Second number' }
            },
            required: %w[a b]
          },
          permission_level: 'public'
        },
        {
          name: 'divide',
          description: 'Divide the first number by the second',
          input_schema: {
            type: 'object',
            properties: {
              a: { type: 'number', description: 'Dividend' },
              b: { type: 'number', description: 'Divisor' }
            },
            required: %w[a b]
          },
          permission_level: 'public'
        },
        {
          name: 'calculate',
          description: 'Evaluate a mathematical expression',
          input_schema: {
            type: 'object',
            properties: {
              expression: { type: 'string', description: 'Mathematical expression to evaluate' }
            },
            required: %w[expression]
          },
          permission_level: 'account'
        }
      ]

      tools.each do |tool_attrs|
        tool = server.mcp_tools.find_or_initialize_by(name: tool_attrs[:name])
        tool.assign_attributes(tool_attrs)
        tool.save!
      end

      puts "    → Created #{tools.size} tools"
    end

    def seed_filesystem_server
      server = @account.mcp_servers.find_or_initialize_by(name: 'Filesystem')

      server.assign_attributes(
        description: 'A sandboxed filesystem MCP server for file operations (list, read, write, search). Based on the official @modelcontextprotocol/server-filesystem.',
        connection_type: 'stdio',
        command: 'npx',
        args: ['-y', '@modelcontextprotocol/server-filesystem', '/tmp'],
        env: {},
        status: 'disconnected',
        capabilities: {
          tools: { listChanged: true },
          resources: { subscribe: true, listChanged: true },
          metadata: {
            icon: '📁',
            author: 'Anthropic',
            url: 'https://github.com/modelcontextprotocol/servers/tree/main/src/filesystem',
            version: '0.6.2'
          }
        }
      )

      if server.save
        puts "  ✓ Created/Updated: Filesystem server"
        seed_filesystem_tools(server)
      else
        puts "  ✗ Failed to create Filesystem server: #{server.errors.full_messages.join(', ')}"
      end
    end

    def seed_filesystem_tools(server)
      tools = [
        {
          name: 'read_file',
          description: 'Read the complete contents of a file from the file system',
          input_schema: {
            type: 'object',
            properties: {
              path: { type: 'string', description: 'Path to the file to read' }
            },
            required: %w[path]
          },
          permission_level: 'account'
        },
        {
          name: 'read_multiple_files',
          description: 'Read the contents of multiple files simultaneously',
          input_schema: {
            type: 'object',
            properties: {
              paths: {
                type: 'array',
                items: { type: 'string' },
                description: 'Array of file paths to read'
              }
            },
            required: %w[paths]
          },
          permission_level: 'account'
        },
        {
          name: 'write_file',
          description: 'Create a new file or completely overwrite an existing file with new content',
          input_schema: {
            type: 'object',
            properties: {
              path: { type: 'string', description: 'Path where to write the file' },
              content: { type: 'string', description: 'Content to write to the file' }
            },
            required: %w[path content]
          },
          permission_level: 'account'
        },
        {
          name: 'list_directory',
          description: 'Get a detailed listing of all files and directories in a specified path',
          input_schema: {
            type: 'object',
            properties: {
              path: { type: 'string', description: 'Path of the directory to list' }
            },
            required: %w[path]
          },
          permission_level: 'public'
        },
        {
          name: 'search_files',
          description: 'Recursively search for files and directories matching a pattern',
          input_schema: {
            type: 'object',
            properties: {
              path: { type: 'string', description: 'Starting path for the search' },
              pattern: { type: 'string', description: 'Glob pattern to match against' }
            },
            required: %w[path pattern]
          },
          permission_level: 'account'
        },
        {
          name: 'get_file_info',
          description: 'Retrieve detailed metadata about a file or directory',
          input_schema: {
            type: 'object',
            properties: {
              path: { type: 'string', description: 'Path to the file or directory' }
            },
            required: %w[path]
          },
          permission_level: 'public'
        }
      ]

      tools.each do |tool_attrs|
        tool = server.mcp_tools.find_or_initialize_by(name: tool_attrs[:name])
        tool.assign_attributes(tool_attrs)
        tool.save!
      end

      puts "    → Created #{tools.size} tools"
    end

    def seed_weather_server
      server = @account.mcp_servers.find_or_initialize_by(name: 'Weather')

      server.assign_attributes(
        description: 'Weather information using the free Open-Meteo API. Get current weather, forecasts, and historical data without API keys.',
        connection_type: 'stdio',
        command: 'npx',
        args: ['-y', '@modelcontextprotocol/server-weather'],
        env: {},
        status: 'disconnected',
        capabilities: {
          tools: { listChanged: false },
          resources: { subscribe: false, listChanged: false },
          metadata: {
            icon: '🌤️',
            author: 'Anthropic',
            url: 'https://github.com/modelcontextprotocol/servers/tree/main/src/weather',
            version: '0.6.2'
          }
        }
      )

      if server.save
        puts "  ✓ Created/Updated: Weather server"
        seed_weather_tools(server)
      else
        puts "  ✗ Failed to create Weather server: #{server.errors.full_messages.join(', ')}"
      end
    end

    def seed_weather_tools(server)
      tools = [
        {
          name: 'get_current_weather',
          description: 'Get current weather conditions for a location using Open-Meteo API (free, no API key required)',
          input_schema: {
            type: 'object',
            properties: {
              latitude: { type: 'number', description: 'Latitude of the location' },
              longitude: { type: 'number', description: 'Longitude of the location' }
            },
            required: %w[latitude longitude]
          },
          permission_level: 'public'
        },
        {
          name: 'get_forecast',
          description: 'Get weather forecast for upcoming days using Open-Meteo API',
          input_schema: {
            type: 'object',
            properties: {
              latitude: { type: 'number', description: 'Latitude of the location' },
              longitude: { type: 'number', description: 'Longitude of the location' },
              days: { type: 'integer', description: 'Number of days (1-16)', minimum: 1, maximum: 16 }
            },
            required: %w[latitude longitude]
          },
          permission_level: 'public'
        }
      ]

      tools.each do |tool_attrs|
        tool = server.mcp_tools.find_or_initialize_by(name: tool_attrs[:name])
        tool.assign_attributes(tool_attrs)
        tool.save!
      end

      puts "    → Created #{tools.size} tools"
    end

    def seed_time_server
      server = @account.mcp_servers.find_or_initialize_by(name: 'Time')

      server.assign_attributes(
        description: 'Get current time in various timezones. Uses the official MCP time server from Anthropic.',
        connection_type: 'stdio',
        command: 'npx',
        args: ['-y', '@modelcontextprotocol/server-time'],
        env: {},
        status: 'disconnected',
        capabilities: {
          tools: { listChanged: false },
          resources: { subscribe: false, listChanged: false },
          metadata: {
            icon: '🕐',
            author: 'Anthropic',
            url: 'https://github.com/modelcontextprotocol/servers/tree/main/src/time',
            version: '0.6.2'
          }
        }
      )

      if server.save
        puts "  ✓ Created/Updated: Time server"
        seed_time_tools(server)
      else
        puts "  ✗ Failed to create Time server: #{server.errors.full_messages.join(', ')}"
      end
    end

    def seed_time_tools(server)
      tools = [
        {
          name: 'get_current_time',
          description: 'Get the current time in a specific timezone',
          input_schema: {
            type: 'object',
            properties: {
              timezone: {
                type: 'string',
                description: 'IANA timezone name (e.g., "America/New_York", "Europe/London", "Asia/Tokyo")'
              }
            },
            required: %w[timezone]
          },
          permission_level: 'public'
        }
      ]

      tools.each do |tool_attrs|
        tool = server.mcp_tools.find_or_initialize_by(name: tool_attrs[:name])
        tool.assign_attributes(tool_attrs)
        tool.save!
      end

      puts "    → Created #{tools.size} tools"
    end

    def seed_fetch_server
      server = @account.mcp_servers.find_or_initialize_by(name: 'Fetch')

      server.assign_attributes(
        description: 'Fetch and extract content from any URL. Converts web pages to markdown, handles images, and can fetch raw content.',
        connection_type: 'stdio',
        command: 'npx',
        args: ['-y', '@modelcontextprotocol/server-fetch'],
        env: {},
        status: 'disconnected',
        capabilities: {
          tools: { listChanged: false },
          resources: { subscribe: false, listChanged: false },
          metadata: {
            icon: '🌐',
            author: 'Anthropic',
            url: 'https://github.com/modelcontextprotocol/servers/tree/main/src/fetch',
            version: '0.6.2'
          }
        }
      )

      if server.save
        puts "  ✓ Created/Updated: Fetch server"
        seed_fetch_tools(server)
      else
        puts "  ✗ Failed to create Fetch server: #{server.errors.full_messages.join(', ')}"
      end
    end

    def seed_fetch_tools(server)
      tools = [
        {
          name: 'fetch',
          description: 'Fetches a URL and extracts its contents as markdown. Images are extracted and returned as embedded resources.',
          input_schema: {
            type: 'object',
            properties: {
              url: { type: 'string', description: 'URL to fetch' },
              max_length: {
                type: 'integer',
                description: 'Maximum number of characters to return (default: 5000)',
                default: 5000
              },
              start_index: {
                type: 'integer',
                description: 'Start content from this character index (default: 0)',
                default: 0
              },
              raw: {
                type: 'boolean',
                description: 'Get raw content without markdown conversion (default: false)',
                default: false
              }
            },
            required: %w[url]
          },
          permission_level: 'account'
        }
      ]

      tools.each do |tool_attrs|
        tool = server.mcp_tools.find_or_initialize_by(name: tool_attrs[:name])
        tool.assign_attributes(tool_attrs)
        tool.save!
      end

      puts "    → Created #{tools.size} tools"
    end
  end
end

# Run if executed directly or via rake task
if defined?(Rails) && Rails.application
  # Find default account or first account
  account = Account.find_by(name: 'Demo Account') || Account.first

  if account
    Seeds::McpExampleServers.seed(account)
  else
    puts 'No account found. Please create an account first.'
  end
end
