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
          *mcp_skills,
          *chat_skills,
          *community_skills,
          *container_skills,
          *ralph_skills
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
              required: [ "workflow_id" ],
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
              required: [ "workflow_id" ],
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
              required: [ "name" ],
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
              required: [ "run_id" ],
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
              required: [ "run_id" ],
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
              required: [ "agent_id" ],
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
              required: [ "agent_id" ],
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
              required: [ "to_agent_card_id", "message" ],
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
              required: [ "pipeline_id" ],
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
              required: [ "run_id" ],
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
              required: [ "agent_id", "content" ],
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
              required: [ "agent_id" ],
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
              required: [ "agent_id", "task" ],
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
              required: [ "server_id", "tool_name" ],
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

      # === CHAT GATEWAY SKILLS ===
      def chat_skills
        [
          {
            id: "chat.send_message",
            name: "Send Chat Message",
            description: "Send a message to an external chat platform",
            category: "chat",
            input_schema: {
              type: "object",
              required: %w[session_id content],
              properties: {
                session_id: { type: "string", format: "uuid" },
                content: { type: "string" },
                message_type: { type: "string", enum: %w[text image audio video document] }
              }
            },
            output_schema: {
              type: "object",
              properties: {
                message_id: { type: "string" },
                delivery_status: { type: "string" }
              }
            },
            tags: %w[chat send message],
            handler: "A2a::Skills::ChatSkills.send_message"
          },
          {
            id: "chat.list_channels",
            name: "List Chat Channels",
            description: "List connected chat platform channels",
            category: "chat",
            input_schema: {
              type: "object",
              properties: {
                platform: { type: "string", enum: %w[whatsapp telegram discord slack mattermost] },
                status: { type: "string", enum: %w[connected disconnected error] }
              }
            },
            output_schema: {
              type: "object",
              properties: {
                channels: { type: "array" }
              }
            },
            tags: %w[chat channels list],
            handler: "A2a::Skills::ChatSkills.list_channels"
          },
          {
            id: "chat.get_session",
            name: "Get Chat Session",
            description: "Get details of a chat session",
            category: "chat",
            input_schema: {
              type: "object",
              required: [ "session_id" ],
              properties: {
                session_id: { type: "string", format: "uuid" }
              }
            },
            output_schema: {
              type: "object",
              properties: {
                session: { type: "object" }
              }
            },
            tags: %w[chat session get],
            handler: "A2a::Skills::ChatSkills.get_session"
          },
          {
            id: "chat.transfer_session",
            name: "Transfer Chat Session",
            description: "Transfer a chat session to another agent",
            category: "chat",
            input_schema: {
              type: "object",
              required: %w[session_id agent_id],
              properties: {
                session_id: { type: "string", format: "uuid" },
                agent_id: { type: "string", format: "uuid" }
              }
            },
            output_schema: {
              type: "object",
              properties: {
                success: { type: "boolean" }
              }
            },
            tags: %w[chat session transfer],
            handler: "A2a::Skills::ChatSkills.transfer_session"
          },
          {
            id: "chat.transcribe_voice",
            name: "Transcribe Voice Note",
            description: "Transcribe a voice message to text",
            category: "chat",
            input_schema: {
              type: "object",
              required: [ "attachment_id" ],
              properties: {
                attachment_id: { type: "string", format: "uuid" }
              }
            },
            output_schema: {
              type: "object",
              properties: {
                transcription: { type: "string" }
              }
            },
            tags: %w[chat voice transcribe],
            handler: "A2a::Skills::ChatSkills.transcribe_voice"
          },
          {
            id: "chat.get_media",
            name: "Get Chat Media",
            description: "Retrieve a media attachment from a chat message",
            category: "chat",
            input_schema: {
              type: "object",
              required: [ "attachment_id" ],
              properties: {
                attachment_id: { type: "string", format: "uuid" }
              }
            },
            output_schema: {
              type: "object",
              properties: {
                url: { type: "string" },
                mime_type: { type: "string" }
              }
            },
            tags: %w[chat media get],
            handler: "A2a::Skills::ChatSkills.get_media"
          }
        ]
      end

      # === COMMUNITY AGENT SKILLS ===
      def community_skills
        [
          {
            id: "community.register_agent",
            name: "Register Community Agent",
            description: "Publish an agent to the community registry",
            category: "community",
            input_schema: {
              type: "object",
              required: %w[agent_id name description],
              properties: {
                agent_id: { type: "string", format: "uuid" },
                name: { type: "string" },
                description: { type: "string" },
                category: { type: "string" },
                tags: { type: "array", items: { type: "string" } },
                visibility: { type: "string", enum: %w[public unlisted private] }
              }
            },
            output_schema: {
              type: "object",
              properties: {
                community_agent_id: { type: "string" },
                slug: { type: "string" }
              }
            },
            tags: %w[community register publish],
            handler: "A2a::Skills::CommunitySkills.register_agent"
          },
          {
            id: "community.discover_agents",
            name: "Discover Community Agents",
            description: "Search the community agent registry",
            category: "community",
            input_schema: {
              type: "object",
              properties: {
                query: { type: "string" },
                category: { type: "string" },
                tags: { type: "array", items: { type: "string" } },
                min_rating: { type: "number" },
                verified_only: { type: "boolean" }
              }
            },
            output_schema: {
              type: "object",
              properties: {
                agents: { type: "array" },
                total: { type: "integer" }
              }
            },
            tags: %w[community discover search],
            handler: "A2a::Skills::CommunitySkills.discover_agents"
          },
          {
            id: "community.rate_agent",
            name: "Rate Community Agent",
            description: "Rate an agent after task completion",
            category: "community",
            input_schema: {
              type: "object",
              required: %w[community_agent_id rating],
              properties: {
                community_agent_id: { type: "string", format: "uuid" },
                rating: { type: "integer", minimum: 1, maximum: 5 },
                review: { type: "string" },
                task_id: { type: "string", format: "uuid" }
              }
            },
            output_schema: {
              type: "object",
              properties: {
                success: { type: "boolean" }
              }
            },
            tags: %w[community rate review],
            handler: "A2a::Skills::CommunitySkills.rate_agent"
          },
          {
            id: "community.report_agent",
            name: "Report Community Agent",
            description: "Report a malicious or inappropriate agent",
            category: "community",
            input_schema: {
              type: "object",
              required: %w[community_agent_id report_type description],
              properties: {
                community_agent_id: { type: "string", format: "uuid" },
                report_type: { type: "string", enum: %w[malicious spam inappropriate copyright other] },
                description: { type: "string" },
                evidence: { type: "object" }
              }
            },
            output_schema: {
              type: "object",
              properties: {
                report_id: { type: "string" }
              }
            },
            tags: %w[community report abuse],
            handler: "A2a::Skills::CommunitySkills.report_agent"
          }
        ]
      end

      # === CONTAINER EXECUTION SKILLS ===
      def container_skills
        [
          {
            id: "container.execute",
            name: "Execute Container",
            description: "Execute an AI agent in a sandboxed container",
            category: "container",
            input_schema: {
              type: "object",
              required: %w[template_id input_parameters],
              properties: {
                template_id: { type: "string", format: "uuid" },
                input_parameters: { type: "object" },
                timeout_seconds: { type: "integer" }
              }
            },
            output_schema: {
              type: "object",
              properties: {
                execution_id: { type: "string" },
                status: { type: "string" }
              }
            },
            tags: %w[container execute sandbox],
            handler: "A2a::Skills::ContainerSkills.execute"
          },
          {
            id: "container.get_status",
            name: "Get Container Status",
            description: "Get status of a container execution",
            category: "container",
            input_schema: {
              type: "object",
              required: [ "execution_id" ],
              properties: {
                execution_id: { type: "string" }
              }
            },
            output_schema: {
              type: "object",
              properties: {
                status: { type: "string" },
                output: { type: "object" },
                logs: { type: "string" }
              }
            },
            tags: %w[container status],
            handler: "A2a::Skills::ContainerSkills.get_status"
          },
          {
            id: "container.list_templates",
            name: "List Container Templates",
            description: "List available container templates",
            category: "container",
            input_schema: {
              type: "object",
              properties: {
                visibility: { type: "string" }
              }
            },
            output_schema: {
              type: "object",
              properties: {
                templates: { type: "array" }
              }
            },
            tags: %w[container templates list],
            handler: "A2a::Skills::ContainerSkills.list_templates"
          }
        ]
      end

      # === RALPH LOOP SKILLS ===
      def ralph_skills
        [
          {
            id: "ralph.create_loop",
            name: "Create Ralph Loop",
            description: "Create a new Ralph development loop with PRD",
            category: "ralph",
            input_schema: {
              type: "object",
              required: [ "name" ],
              properties: {
                name: { type: "string" },
                description: { type: "string" },
                repository_url: { type: "string" },
                branch: { type: "string", default: "main" },
                default_agent_id: { type: "string", description: "ID of the default agent for execution" },
                max_iterations: { type: "integer", default: 100 },
                prd: { type: "object" },
                configuration: { type: "object" }
              }
            },
            output_schema: {
              type: "object",
              properties: {
                loop_id: { type: "string" },
                loop: { type: "object" }
              }
            },
            tags: %w[ralph loop create],
            handler: "A2a::Skills::RalphSkills.create_loop"
          },
          {
            id: "ralph.start_loop",
            name: "Start Ralph Loop",
            description: "Start execution of a Ralph loop",
            category: "ralph",
            input_schema: {
              type: "object",
              required: [ "loop_id" ],
              properties: {
                loop_id: { type: "string", format: "uuid" }
              }
            },
            output_schema: {
              type: "object",
              properties: {
                success: { type: "boolean" },
                loop: { type: "object" }
              }
            },
            tags: %w[ralph loop start execute],
            handler: "A2a::Skills::RalphSkills.start_loop"
          },
          {
            id: "ralph.pause_loop",
            name: "Pause Ralph Loop",
            description: "Pause a running Ralph loop",
            category: "ralph",
            input_schema: {
              type: "object",
              required: [ "loop_id" ],
              properties: {
                loop_id: { type: "string", format: "uuid" }
              }
            },
            output_schema: {
              type: "object",
              properties: {
                success: { type: "boolean" },
                loop: { type: "object" }
              }
            },
            tags: %w[ralph loop pause],
            handler: "A2a::Skills::RalphSkills.pause_loop"
          },
          {
            id: "ralph.resume_loop",
            name: "Resume Ralph Loop",
            description: "Resume a paused Ralph loop",
            category: "ralph",
            input_schema: {
              type: "object",
              required: [ "loop_id" ],
              properties: {
                loop_id: { type: "string", format: "uuid" }
              }
            },
            output_schema: {
              type: "object",
              properties: {
                success: { type: "boolean" },
                loop: { type: "object" }
              }
            },
            tags: %w[ralph loop resume],
            handler: "A2a::Skills::RalphSkills.resume_loop"
          },
          {
            id: "ralph.cancel_loop",
            name: "Cancel Ralph Loop",
            description: "Cancel a Ralph loop",
            category: "ralph",
            input_schema: {
              type: "object",
              required: [ "loop_id" ],
              properties: {
                loop_id: { type: "string", format: "uuid" },
                reason: { type: "string" }
              }
            },
            output_schema: {
              type: "object",
              properties: {
                success: { type: "boolean" },
                loop: { type: "object" }
              }
            },
            tags: %w[ralph loop cancel],
            handler: "A2a::Skills::RalphSkills.cancel_loop"
          },
          {
            id: "ralph.get_status",
            name: "Get Ralph Loop Status",
            description: "Get current status and progress of a Ralph loop",
            category: "ralph",
            input_schema: {
              type: "object",
              required: [ "loop_id" ],
              properties: {
                loop_id: { type: "string", format: "uuid" }
              }
            },
            output_schema: {
              type: "object",
              properties: {
                loop: { type: "object" },
                tasks: { type: "array" },
                recent_iterations: { type: "array" }
              }
            },
            tags: %w[ralph loop status],
            handler: "A2a::Skills::RalphSkills.get_status"
          },
          {
            id: "ralph.list_tasks",
            name: "List Ralph Loop Tasks",
            description: "List tasks in a Ralph loop PRD",
            category: "ralph",
            input_schema: {
              type: "object",
              required: [ "loop_id" ],
              properties: {
                loop_id: { type: "string", format: "uuid" },
                status: { type: "string", enum: %w[pending in_progress passed failed blocked skipped] }
              }
            },
            output_schema: {
              type: "object",
              properties: {
                tasks: { type: "array" },
                total: { type: "integer" }
              }
            },
            tags: %w[ralph tasks list],
            handler: "A2a::Skills::RalphSkills.list_tasks"
          },
          {
            id: "ralph.get_progress",
            name: "Get Ralph Loop Progress",
            description: "Get accumulated learnings and progress for a Ralph loop",
            category: "ralph",
            input_schema: {
              type: "object",
              required: [ "loop_id" ],
              properties: {
                loop_id: { type: "string", format: "uuid" }
              }
            },
            output_schema: {
              type: "object",
              properties: {
                progress: { type: "object" },
                learnings: { type: "array" }
              }
            },
            tags: %w[ralph progress learnings],
            handler: "A2a::Skills::RalphSkills.get_progress"
          },
          {
            id: "ralph.run_iteration",
            name: "Run Ralph Loop Iteration",
            description: "Run a single iteration of a Ralph loop",
            category: "ralph",
            input_schema: {
              type: "object",
              required: [ "loop_id" ],
              properties: {
                loop_id: { type: "string", format: "uuid" }
              }
            },
            output_schema: {
              type: "object",
              properties: {
                iteration: { type: "object" },
                loop: { type: "object" },
                next_action: { type: "string" }
              }
            },
            tags: %w[ralph iteration execute],
            handler: "A2a::Skills::RalphSkills.run_iteration"
          },
          {
            id: "ralph.list_loops",
            name: "List Ralph Loops",
            description: "List Ralph loops with filtering",
            category: "ralph",
            input_schema: {
              type: "object",
              properties: {
                status: { type: "string", enum: %w[pending running paused completed failed cancelled] },
                default_agent_id: { type: "string", description: "Filter by default agent ID" },
                page: { type: "integer", default: 1 },
                per_page: { type: "integer", default: 20 }
              }
            },
            output_schema: {
              type: "object",
              properties: {
                loops: { type: "array" },
                total: { type: "integer" }
              }
            },
            tags: %w[ralph loops list],
            handler: "A2a::Skills::RalphSkills.list_loops"
          }
        ]
      end
    end
  end
end
