# frozen_string_literal: true

module A2a
  module Skills
    # McpSkills - A2A skill implementations for MCP operations
    class McpSkills
      def initialize(account:, user: nil)
        @account = account
        @user = user
      end

      # List MCP servers
      def list_servers(input, task = nil)
        scope = @account.mcp_servers.order(created_at: :desc)

        scope = scope.where(status: input["status"]) if input["status"].present?

        page = (input["page"] || 1).to_i
        per_page = [(input["per_page"] || 20).to_i, 100].min

        servers = scope.offset((page - 1) * per_page).limit(per_page)

        {
          output: {
            servers: servers.map { |s| server_summary(s) },
            total: scope.count,
            page: page,
            per_page: per_page
          }
        }
      end

      # List MCP tools
      def list_tools(input, task = nil)
        if input["server_id"].present?
          server = @account.mcp_servers.find(input["server_id"])
          tools = server.tools
        else
          tools = @account.mcp_servers.active.flat_map(&:tools)
        end

        {
          output: {
            tools: tools.map { |t| tool_summary(t) }
          }
        }
      end

      # Execute MCP tool
      def execute_tool(input, task = nil)
        server = @account.mcp_servers.find(input["server_id"])
        tool_name = input["tool_name"]
        arguments = input["arguments"] || {}

        # Find the tool
        tool = server.tools.find { |t| t["name"] == tool_name }
        unless tool
          raise ArgumentError, "Tool not found: #{tool_name}"
        end

        # Execute the tool
        executor = Mcp::ToolExecutor.new(server: server, account: @account)
        result = executor.execute(tool_name: tool_name, arguments: arguments)

        {
          output: {
            result: result[:output],
            success: result[:success],
            execution_time_ms: result[:execution_time_ms]
          }
        }
      end

      private

      def server_summary(server)
        {
          id: server.id,
          name: server.name,
          description: server.description,
          status: server.status,
          server_type: server.server_type,
          tools_count: server.tools&.size || 0,
          resources_count: server.resources&.size || 0
        }
      end

      def tool_summary(tool)
        {
          name: tool["name"],
          description: tool["description"],
          input_schema: tool["inputSchema"]
        }
      end
    end
  end
end
