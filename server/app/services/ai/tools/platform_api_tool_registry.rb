# frozen_string_literal: true

module Ai
  module Tools
    class PlatformApiToolRegistry
      TOOLS = {
        # Project & CI/CD
        "create_gitea_repository" => "Ai::Tools::ProjectInitTool",
        "dispatch_to_runner" => "Ai::Tools::RunnerDispatchTool",
        # Agent management
        "create_agent" => "Ai::Tools::AgentManagementTool",
        "list_agents" => "Ai::Tools::AgentManagementTool",
        "execute_agent" => "Ai::Tools::AgentManagementTool",
        "get_agent" => "Ai::Tools::AgentManagementTool",
        "update_agent" => "Ai::Tools::AgentManagementTool",
        "spawn_task" => "Ai::Tools::AgentManagementTool",
        "check_task_status" => "Ai::Tools::AgentManagementTool",
        "wait_for_task" => "Ai::Tools::AgentManagementTool",
        # Team management
        "create_team" => "Ai::Tools::TeamManagementTool",
        "add_team_member" => "Ai::Tools::TeamManagementTool",
        "execute_team" => "Ai::Tools::TeamManagementTool",
        "get_team" => "Ai::Tools::TeamManagementTool",
        "list_teams" => "Ai::Tools::TeamManagementTool",
        "update_team" => "Ai::Tools::TeamManagementTool",
        # Workflow management
        "create_workflow" => "Ai::Tools::WorkflowManagementTool",
        "execute_workflow" => "Ai::Tools::WorkflowManagementTool",
        "list_workflows" => "Ai::Tools::WorkflowManagementTool",
        "get_workflow" => "Ai::Tools::WorkflowManagementTool",
        "update_workflow" => "Ai::Tools::WorkflowManagementTool",
        # Pipeline management
        "trigger_pipeline" => "Ai::Tools::PipelineManagementTool",
        "list_pipelines" => "Ai::Tools::PipelineManagementTool",
        "get_pipeline_status" => "Ai::Tools::PipelineManagementTool",
        # Memory management
        "write_shared_memory" => "Ai::Tools::MemoryTool",
        "read_shared_memory" => "Ai::Tools::MemoryTool",
        "search_memory" => "Ai::Tools::MemoryTool",
        "consolidate_memory" => "Ai::Tools::MemoryTool",
        "memory_stats" => "Ai::Tools::MemoryTool",
        "list_pools" => "Ai::Tools::MemoryTool",
        # Knowledge & RAG
        "query_knowledge_base" => "Ai::Tools::KnowledgeTool",
        "list_knowledge_bases" => "Ai::Tools::RagManagementTool",
        "create_knowledge_base" => "Ai::Tools::RagManagementTool",
        "add_document" => "Ai::Tools::RagManagementTool",
        "process_document" => "Ai::Tools::RagManagementTool",
        "search_documents" => "Ai::Tools::RagManagementTool",
        "delete_document" => "Ai::Tools::RagManagementTool",
        "get_api_reference" => "Ai::Tools::ApiReferenceTool",
        # KB Article management
        "list_kb_articles" => "Ai::Tools::KbArticleManagementTool",
        "get_kb_article" => "Ai::Tools::KbArticleManagementTool",
        "create_kb_article" => "Ai::Tools::KbArticleManagementTool",
        "update_kb_article" => "Ai::Tools::KbArticleManagementTool",
        # Page management
        "list_pages" => "Ai::Tools::PageManagementTool",
        "get_page" => "Ai::Tools::PageManagementTool",
        "create_page" => "Ai::Tools::PageManagementTool",
        "update_page" => "Ai::Tools::PageManagementTool",
        # Compound learning
        "query_learnings" => "Ai::Tools::LearningTool",
        "reinforce_learning" => "Ai::Tools::LearningTool",
        "learning_metrics" => "Ai::Tools::LearningTool",
        "create_learning" => "Ai::Tools::LearningTool",
        # Shared knowledge
        "search_knowledge" => "Ai::Tools::SharedKnowledgeTool",
        "create_knowledge" => "Ai::Tools::SharedKnowledgeTool",
        "update_knowledge" => "Ai::Tools::SharedKnowledgeTool",
        "promote_knowledge" => "Ai::Tools::SharedKnowledgeTool",
        # Skills
        "list_skills" => "Ai::Tools::SkillTool",
        "get_skill" => "Ai::Tools::SkillTool",
        "discover_skills" => "Ai::Tools::SkillTool",
        "get_skill_context" => "Ai::Tools::SkillTool",
        "skill_health" => "Ai::Tools::SkillTool",
        "skill_metrics" => "Ai::Tools::SkillTool",
        "create_skill" => "Ai::Tools::SkillTool",
        "update_skill" => "Ai::Tools::SkillTool",
        "delete_skill" => "Ai::Tools::SkillTool",
        "toggle_skill" => "Ai::Tools::SkillTool",
        # Knowledge quality
        "verify_learning" => "Ai::Tools::KnowledgeQualityTool",
        "dispute_learning" => "Ai::Tools::KnowledgeQualityTool",
        "resolve_contradiction" => "Ai::Tools::KnowledgeQualityTool",
        "rate_knowledge" => "Ai::Tools::KnowledgeQualityTool",
        "knowledge_health" => "Ai::Tools::KnowledgeQualityTool",
        # Knowledge graph
        "search_knowledge_graph" => "Ai::Tools::KnowledgeGraphTool",
        "reason_knowledge_graph" => "Ai::Tools::KnowledgeGraphTool",
        "get_graph_node" => "Ai::Tools::KnowledgeGraphTool",
        "list_graph_nodes" => "Ai::Tools::KnowledgeGraphTool",
        "get_graph_neighbors" => "Ai::Tools::KnowledgeGraphTool",
        "graph_statistics" => "Ai::Tools::KnowledgeGraphTool",
        "get_subgraph" => "Ai::Tools::KnowledgeGraphTool",
        "extract_to_knowledge_graph" => "Ai::Tools::KnowledgeGraphTool",
        # Concierge
        "send_concierge_message" => "Ai::Tools::ConciergeTool",
        "confirm_concierge_action" => "Ai::Tools::ConciergeTool",
        "list_conversations" => "Ai::Tools::ConciergeTool",
        "get_conversation_messages" => "Ai::Tools::ConciergeTool",
        # Workspace
        "create_workspace" => "Ai::Tools::WorkspaceTool",
        "send_message" => "Ai::Tools::WorkspaceTool",
        "invite_agent" => "Ai::Tools::WorkspaceTool",
        "list_messages" => "Ai::Tools::WorkspaceTool",
        "list_workspaces" => "Ai::Tools::WorkspaceTool",
        "active_sessions" => "Ai::Tools::WorkspaceTool",
        # Activity monitoring
        "get_activity_feed" => "Ai::Tools::ActivityMonitorTool",
        "get_mission_status" => "Ai::Tools::ActivityMonitorTool",
        "get_notifications" => "Ai::Tools::ActivityMonitorTool",
        "dismiss_notification" => "Ai::Tools::ActivityMonitorTool",
        "get_system_health" => "Ai::Tools::ActivityMonitorTool",
        # Kill switch
        "emergency_halt" => "Ai::Tools::KillSwitchTool",
        "emergency_resume" => "Ai::Tools::KillSwitchTool",
        "kill_switch_status" => "Ai::Tools::KillSwitchTool",
        # Agent autonomy
        "create_agent_goal" => "Ai::Tools::AgentAutonomyTool",
        "list_agent_goals" => "Ai::Tools::AgentAutonomyTool",
        "update_agent_goal" => "Ai::Tools::AgentAutonomyTool",
        "agent_introspect" => "Ai::Tools::AgentAutonomyTool",
        "propose_feature" => "Ai::Tools::AgentAutonomyTool",
        "send_proactive_notification" => "Ai::Tools::AgentAutonomyTool",
        "discover_claude_sessions" => "Ai::Tools::AgentAutonomyTool",
        "request_code_change" => "Ai::Tools::AgentAutonomyTool",
        "create_proposal" => "Ai::Tools::AgentAutonomyTool",
        "escalate" => "Ai::Tools::AgentAutonomyTool",
        "request_feedback" => "Ai::Tools::AgentAutonomyTool",
        "report_issue" => "Ai::Tools::AgentAutonomyTool",
        # Image generation
        "generate_image" => "Ai::Tools::ImageGenerationTool",
        "list_generated_images" => "Ai::Tools::ImageGenerationTool"
      }.freeze

      def self.available_tools(agent: nil)
        TOOLS.each_with_object({}) do |(name, class_name), hash|
          klass = class_name.constantize
          hash[name] = klass if klass.permitted?(agent: agent)
        rescue NameError => e
          Rails.logger.warn "[PlatformApiToolRegistry] Tool class not found: #{class_name} - #{e.message}"
        end
      end

      def self.find_tool(name)
        # Check static tools first
        class_name = TOOLS[name]
        if class_name
          return class_name.constantize
        end

        # Check dynamic tools
        dynamic_tool = dynamic_tools.find { |t| t[:name] == name }
        dynamic_tool[:handler_class]&.constantize if dynamic_tool
      rescue NameError
        nil
      end

      def self.tool_definitions(agent: nil)
        available_tools(agent: agent).map do |name, klass|
          action_defs = klass.action_definitions
          if action_defs.key?(name)
            action_defs[name].merge(name: name)
          else
            klass.definition.merge(name: name)  # fallback for unmatched tools
          end
        end
      end

      # Discover tools by natural language query (semantic search)
      def self.discover_tools(query:, account:, capabilities: nil, limit: 10)
        service = SemanticToolDiscoveryService.new(account: account)
        service.discover(query: query, capabilities: capabilities, limit: limit)
      end

      # Register a tool dynamically at runtime
      def self.register_dynamic_tool(account:, name:, description:, parameters:, handler:, metadata: {})
        SemanticToolDiscoveryService.register_dynamic_tool(
          account: account, name: name, description: description,
          parameters: parameters, handler: handler, metadata: metadata
        )
      end

      # Unregister a dynamic tool
      def self.unregister_dynamic_tool(account:, name:)
        SemanticToolDiscoveryService.unregister_dynamic_tool(account: account, name: name)
      end

      # List dynamic tools for an account
      def self.dynamic_tools(account: nil)
        return [] unless account

        Rails.cache.read("tool_discovery:#{account.id}:dynamic_tools") || []
      end
    end
  end
end
