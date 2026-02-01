# frozen_string_literal: true

module A2a
  # SkillRegistry - Registers and manages A2A skills
  # Maps platform capabilities to A2A skill definitions
  class SkillRegistry
    class << self
      def platform_skills
        @platform_skills ||= build_platform_skills
      end

      def find_skill(skill_id)
        platform_skills.find { |s| s[:id] == skill_id }
      end

      def skills_by_category(category)
        platform_skills.select { |s| s[:category] == category }
      end

      def register_skill(skill)
        @platform_skills ||= []
        @platform_skills << normalize_skill(skill)
      end

      def reload!
        @platform_skills = build_platform_skills
      end

      private

      def build_platform_skills
        [
          *workflow_skills,
          *agent_skills,
          *devops_skills,
          *memory_skills,
          *mcp_skills
        ]
      end

      def normalize_skill(skill)
        {
          id: skill[:id] || skill[:name]&.parameterize,
          name: skill[:name],
          description: skill[:description],
          category: skill[:category],
          input_schema: skill[:input_schema] || {},
          output_schema: skill[:output_schema] || {},
          tags: skill[:tags] || [],
          handler: skill[:handler]
        }
      end

      # === WORKFLOW SKILLS ===
      def workflow_skills
        [
          {
            id: "workflows.list",
            name: "List Workflows",
            description: "List available AI workflows with filtering",
            category: "workflows",
            input_schema: {
              type: "object",
              properties: {
                status: { type: "string", enum: %w[draft active paused inactive archived] },
                workflow_type: { type: "string", enum: %w[ai cicd] },
                page: { type: "integer", default: 1 },
                per_page: { type: "integer", default: 20 }
              }
            },
            output_schema: {
              type: "object",
              properties: {
                workflows: { type: "array" },
                total: { type: "integer" }
              }
            },
            tags: %w[workflows list],
            handler: "A2a::Skills::WorkflowSkills.list"
          },
          {
            id: "workflows.get",
            name: "Get Workflow",
            description: "Get workflow details by ID",
            category: "workflows",
            input_schema: {
              type: "object",
              required: ["workflow_id"],
              properties: {
                workflow_id: { type: "string", format: "uuid" }
              }
            },
            output_schema: {
              type: "object",
              properties: {
                workflow: { type: "object" }
              }
            },
            tags: %w[workflows get],
            handler: "A2a::Skills::WorkflowSkills.get"
          },
          {
            id: "workflows.execute",
            name: "Execute Workflow",
            description: "Execute an AI workflow with input variables",
            category: "workflows",
            input_schema: {
              type: "object",
              required: ["workflow_id"],
              properties: {
                workflow_id: { type: "string", format: "uuid" },
                input_variables: { type: "object" },
                async: { type: "boolean", default: false }
              }
            },
            output_schema: {
              type: "object",
              properties: {
                run_id: { type: "string" },
                status: { type: "string" },
                output: { type: "object" }
              }
            },
            tags: %w[workflows execute],
            handler: "A2a::Skills::WorkflowSkills.execute"
          },
          {
            id: "workflows.create",
            name: "Create Workflow",
            description: "Create a new AI workflow",
            category: "workflows",
            input_schema: {
              type: "object",
              required: ["name"],
              properties: {
                name: { type: "string" },
                description: { type: "string" },
                workflow_type: { type: "string", enum: %w[ai cicd] },
                nodes: { type: "array" },
                edges: { type: "array" }
              }
            },
            output_schema: {
              type: "object",
              properties: {
                workflow: { type: "object" }
              }
            },
            tags: %w[workflows create],
            handler: "A2a::Skills::WorkflowSkills.create"
          },
          {
            id: "workflow_runs.list",
            name: "List Workflow Runs",
            description: "List workflow execution runs",
            category: "workflows",
            input_schema: {
              type: "object",
              properties: {
                workflow_id: { type: "string", format: "uuid" },
                status: { type: "string" },
                page: { type: "integer" },
                per_page: { type: "integer" }
              }
            },
            output_schema: {
              type: "object",
              properties: {
                runs: { type: "array" },
                total: { type: "integer" }
              }
            },
            tags: %w[workflows runs],
            handler: "A2a::Skills::WorkflowSkills.list_runs"
          },
          {
            id: "workflow_runs.get",
            name: "Get Workflow Run",
            description: "Get details of a specific workflow run",
            category: "workflows",
            input_schema: {
              type: "object",
              required: ["run_id"],
              properties: {
                run_id: { type: "string" }
              }
            },
            output_schema: {
              type: "object",
              properties: {
                run: { type: "object" }
              }
            },
            tags: %w[workflows runs],
            handler: "A2a::Skills::WorkflowSkills.get_run"
          },
          {
            id: "workflow_runs.cancel",
            name: "Cancel Workflow Run",
            description: "Cancel a running workflow execution",
            category: "workflows",
            input_schema: {
              type: "object",
              required: ["run_id"],
              properties: {
                run_id: { type: "string" },
                reason: { type: "string" }
              }
            },
            output_schema: {
              type: "object",
              properties: {
                success: { type: "boolean" }
              }
            },
            tags: %w[workflows runs cancel],
            handler: "A2a::Skills::WorkflowSkills.cancel_run"
          }
        ]
      end

      # === AGENT SKILLS ===
      def agent_skills
        [
          {
            id: "agents.list",
            name: "List Agents",
            description: "List available AI agents",
            category: "agents",
            input_schema: {
              type: "object",
              properties: {
                status: { type: "string" },
                agent_type: { type: "string" },
                page: { type: "integer" },
                per_page: { type: "integer" }
              }
            },
            output_schema: {
              type: "object",
              properties: {
                agents: { type: "array" },
                total: { type: "integer" }
              }
            },
            tags: %w[agents list],
            handler: "A2a::Skills::AgentSkills.list"
          },
          {
            id: "agents.get",
            name: "Get Agent",
            description: "Get agent details by ID",
            category: "agents",
            input_schema: {
              type: "object",
              required: ["agent_id"],
              properties: {
                agent_id: { type: "string", format: "uuid" }
              }
            },
            output_schema: {
              type: "object",
              properties: {
                agent: { type: "object" }
              }
            },
            tags: %w[agents get],
            handler: "A2a::Skills::AgentSkills.get"
          },
          {
            id: "agents.execute",
            name: "Execute Agent",
            description: "Execute an AI agent with input",
            category: "agents",
            input_schema: {
              type: "object",
              required: ["agent_id"],
              properties: {
                agent_id: { type: "string", format: "uuid" },
                input: { type: "object" },
                context: { type: "object" }
              }
            },
            output_schema: {
              type: "object",
              properties: {
                output: { type: "object" },
                execution_id: { type: "string" }
              }
            },
            tags: %w[agents execute],
            handler: "A2a::Skills::AgentSkills.execute"
          },
          {
            id: "a2a.discover_agents",
            name: "Discover A2A Agents",
            description: "Discover available A2A agents with filtering",
            category: "a2a",
            input_schema: {
              type: "object",
              properties: {
                skill: { type: "string" },
                tag: { type: "string" },
                query: { type: "string" }
              }
            },
            output_schema: {
              type: "object",
              properties: {
                agents: { type: "array" }
              }
            },
            tags: %w[a2a discovery],
            handler: "A2a::Skills::AgentSkills.discover"
          },
          {
            id: "a2a.submit_task",
            name: "Submit A2A Task",
            description: "Submit a task to an A2A agent",
            category: "a2a",
            input_schema: {
              type: "object",
              required: ["to_agent_card_id", "message"],
              properties: {
                to_agent_card_id: { type: "string" },
                message: { type: "object" },
                sync: { type: "boolean", default: false }
              }
            },
            output_schema: {
              type: "object",
              properties: {
                task: { type: "object" }
              }
            },
            tags: %w[a2a tasks],
            handler: "A2a::Skills::AgentSkills.submit_task"
          }
        ]
      end

      # === DEVOPS SKILLS ===
      def devops_skills
        [
          {
            id: "devops.list_pipelines",
            name: "List DevOps Pipelines",
            description: "List CI/CD pipelines",
            category: "devops",
            input_schema: {
              type: "object",
              properties: {
                status: { type: "string" },
                page: { type: "integer" },
                per_page: { type: "integer" }
              }
            },
            output_schema: {
              type: "object",
              properties: {
                pipelines: { type: "array" },
                total: { type: "integer" }
              }
            },
            tags: %w[devops pipelines],
            handler: "A2a::Skills::DevopsSkills.list_pipelines"
          },
          {
            id: "devops.execute_pipeline",
            name: "Execute Pipeline",
            description: "Trigger a CI/CD pipeline execution",
            category: "devops",
            input_schema: {
              type: "object",
              required: ["pipeline_id"],
              properties: {
                pipeline_id: { type: "string" },
                variables: { type: "object" },
                ref: { type: "string" }
              }
            },
            output_schema: {
              type: "object",
              properties: {
                run_id: { type: "string" },
                status: { type: "string" }
              }
            },
            tags: %w[devops pipelines execute],
            handler: "A2a::Skills::DevopsSkills.execute_pipeline"
          },
          {
            id: "devops.get_logs",
            name: "Get Pipeline Logs",
            description: "Retrieve logs from a pipeline execution",
            category: "devops",
            input_schema: {
              type: "object",
              required: ["run_id"],
              properties: {
                run_id: { type: "string" },
                job_name: { type: "string" }
              }
            },
            output_schema: {
              type: "object",
              properties: {
                logs: { type: "string" },
                job_logs: { type: "array" }
              }
            },
            tags: %w[devops logs],
            handler: "A2a::Skills::DevopsSkills.get_logs"
          }
        ]
      end

      # === MEMORY SKILLS ===
      def memory_skills
        [
          {
            id: "memory.store",
            name: "Store Memory",
            description: "Store information in agent memory",
            category: "memory",
            input_schema: {
              type: "object",
              required: ["agent_id", "content"],
              properties: {
                agent_id: { type: "string" },
                content: { type: "object" },
                memory_type: { type: "string", enum: %w[factual experiential procedural] },
                context: { type: "object" }
              }
            },
            output_schema: {
              type: "object",
              properties: {
                memory_id: { type: "string" },
                success: { type: "boolean" }
              }
            },
            tags: %w[memory store],
            handler: "A2a::Skills::MemorySkills.store"
          },
          {
            id: "memory.retrieve",
            name: "Retrieve Memory",
            description: "Retrieve relevant memories for a context",
            category: "memory",
            input_schema: {
              type: "object",
              required: ["agent_id"],
              properties: {
                agent_id: { type: "string" },
                query: { type: "string" },
                memory_type: { type: "string" },
                limit: { type: "integer", default: 10 }
              }
            },
            output_schema: {
              type: "object",
              properties: {
                memories: { type: "array" }
              }
            },
            tags: %w[memory retrieve],
            handler: "A2a::Skills::MemorySkills.retrieve"
          },
          {
            id: "memory.inject",
            name: "Inject Memory Context",
            description: "Inject memory context into an agent execution",
            category: "memory",
            input_schema: {
              type: "object",
              required: ["agent_id", "task"],
              properties: {
                agent_id: { type: "string" },
                task: { type: "object" },
                token_budget: { type: "integer", default: 2000 }
              }
            },
            output_schema: {
              type: "object",
              properties: {
                context: { type: "object" }
              }
            },
            tags: %w[memory inject],
            handler: "A2a::Skills::MemorySkills.inject"
          }
        ]
      end

      # === MCP SKILLS ===
      def mcp_skills
        [
          {
            id: "mcp.list_servers",
            name: "List MCP Servers",
            description: "List available MCP servers",
            category: "mcp",
            input_schema: {
              type: "object",
              properties: {
                status: { type: "string" },
                page: { type: "integer" }
              }
            },
            output_schema: {
              type: "object",
              properties: {
                servers: { type: "array" }
              }
            },
            tags: %w[mcp servers],
            handler: "A2a::Skills::McpSkills.list_servers"
          },
          {
            id: "mcp.list_tools",
            name: "List MCP Tools",
            description: "List tools available from MCP servers",
            category: "mcp",
            input_schema: {
              type: "object",
              properties: {
                server_id: { type: "string" }
              }
            },
            output_schema: {
              type: "object",
              properties: {
                tools: { type: "array" }
              }
            },
            tags: %w[mcp tools],
            handler: "A2a::Skills::McpSkills.list_tools"
          },
          {
            id: "mcp.execute_tool",
            name: "Execute MCP Tool",
            description: "Execute a tool from an MCP server",
            category: "mcp",
            input_schema: {
              type: "object",
              required: ["server_id", "tool_name"],
              properties: {
                server_id: { type: "string" },
                tool_name: { type: "string" },
                arguments: { type: "object" }
              }
            },
            output_schema: {
              type: "object",
              properties: {
                result: { type: "object" }
              }
            },
            tags: %w[mcp tools execute],
            handler: "A2a::Skills::McpSkills.execute_tool"
          }
        ]
      end
    end
  end
end
