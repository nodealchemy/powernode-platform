# frozen_string_literal: true

module Ai
  module Tools
    class PlatformApiToolRegistry
      TOOLS = {
        # Project & CI/CD
        "create_gitea_repository" => "Ai::Tools::ProjectInitTool",
        "update_gitea_repository" => "Ai::Tools::RepoManagementTool",
        "dispatch_to_runner" => "Ai::Tools::RunnerDispatchTool",
        # Container deployment & management
        "deploy_container_agent" => "Ai::Tools::ContainerDeploymentTool",
        "container_status" => "Ai::Tools::ContainerStatusTool",
        "container_logs" => "Ai::Tools::ContainerLogsTool",
        "container_terminate" => "Ai::Tools::ContainerTerminateTool",
        # Integration health
        "integration_health" => "Ai::Tools::IntegrationHealthTool",
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
        # Agent-managed memory (MemGPT-style)
        "agent_remember" => "Ai::Tools::AgentMemoryManagementTool",
        "agent_forget" => "Ai::Tools::AgentMemoryManagementTool",
        "agent_reflect" => "Ai::Tools::AgentMemoryManagementTool",
        "agent_recall" => "Ai::Tools::AgentMemoryManagementTool",
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
        # Goal decomposition (autonomous planning)
        "decompose_goal" => "Ai::Tools::AgentAutonomyTool",
        "validate_plan" => "Ai::Tools::AgentAutonomyTool",
        "approve_plan" => "Ai::Tools::AgentAutonomyTool",
        # Self-improvement (skill mutation, challenges)
        "generate_self_challenge" => "Ai::Tools::SelfImprovementTool",
        "list_challenges" => "Ai::Tools::SelfImprovementTool",
        "get_challenge_result" => "Ai::Tools::SelfImprovementTool",
        "mutate_skill" => "Ai::Tools::SelfImprovementTool",
        "compose_skills" => "Ai::Tools::SelfImprovementTool",
        "auto_evolve_skill" => "Ai::Tools::SelfImprovementTool",
        # Governance (monitoring, collusion detection)
        "governance_scan" => "Ai::Tools::GovernanceTool",
        "list_governance_reports" => "Ai::Tools::GovernanceTool",
        "get_governance_report" => "Ai::Tools::GovernanceTool",
        "resolve_governance_report" => "Ai::Tools::GovernanceTool",
        "detect_collusion" => "Ai::Tools::GovernanceTool",
        "governance_dashboard" => "Ai::Tools::GovernanceTool",
        # Coordination (stigmergic signals, pressure fields, self-organizing teams)
        "emit_signal" => "Ai::Tools::CoordinationTool",
        "perceive_signals" => "Ai::Tools::CoordinationTool",
        "reinforce_signal" => "Ai::Tools::CoordinationTool",
        "measure_pressure" => "Ai::Tools::CoordinationTool",
        "perceive_pressure" => "Ai::Tools::CoordinationTool",
        "optimize_team" => "Ai::Tools::CoordinationTool",
        "recruit_agent" => "Ai::Tools::CoordinationTool",
        # Image generation
        "generate_image" => "Ai::Tools::ImageGenerationTool",
        "list_generated_images" => "Ai::Tools::ImageGenerationTool",
        # Docker infrastructure management — containers
        "docker_list_containers" => "Ai::Tools::DockerContainerTool",
        "docker_get_container" => "Ai::Tools::DockerContainerTool",
        "docker_create_container" => "Ai::Tools::DockerContainerTool",
        "docker_start_container" => "Ai::Tools::DockerContainerTool",
        "docker_stop_container" => "Ai::Tools::DockerContainerTool",
        "docker_restart_container" => "Ai::Tools::DockerContainerTool",
        "docker_remove_container" => "Ai::Tools::DockerContainerTool",
        "docker_container_logs" => "Ai::Tools::DockerContainerTool",
        "docker_container_stats" => "Ai::Tools::DockerContainerTool",
        "docker_container_exec" => "Ai::Tools::DockerContainerTool",
        # Docker infrastructure management — Swarm services
        "docker_list_services" => "Ai::Tools::DockerServiceTool",
        "docker_get_service" => "Ai::Tools::DockerServiceTool",
        "docker_create_service" => "Ai::Tools::DockerServiceTool",
        "docker_update_service" => "Ai::Tools::DockerServiceTool",
        "docker_scale_service" => "Ai::Tools::DockerServiceTool",
        "docker_rollback_service" => "Ai::Tools::DockerServiceTool",
        "docker_remove_service" => "Ai::Tools::DockerServiceTool",
        "docker_service_logs" => "Ai::Tools::DockerServiceTool",
        "docker_service_tasks" => "Ai::Tools::DockerServiceTool",
        # Docker infrastructure management — Swarm stacks
        "docker_list_stacks" => "Ai::Tools::DockerStackTool",
        "docker_get_stack" => "Ai::Tools::DockerStackTool",
        "docker_deploy_stack" => "Ai::Tools::DockerStackTool",
        "docker_remove_stack" => "Ai::Tools::DockerStackTool",
        "docker_adopt_stack" => "Ai::Tools::DockerStackTool",
        # Docker infrastructure management — clusters, nodes, secrets, configs
        "docker_list_clusters" => "Ai::Tools::DockerClusterTool",
        "docker_get_cluster" => "Ai::Tools::DockerClusterTool",
        "docker_cluster_health" => "Ai::Tools::DockerClusterTool",
        "docker_list_nodes" => "Ai::Tools::DockerClusterTool",
        "docker_node_promote" => "Ai::Tools::DockerClusterTool",
        "docker_node_demote" => "Ai::Tools::DockerClusterTool",
        "docker_node_drain" => "Ai::Tools::DockerClusterTool",
        "docker_node_activate" => "Ai::Tools::DockerClusterTool",
        "docker_list_secrets" => "Ai::Tools::DockerClusterTool",
        "docker_create_secret" => "Ai::Tools::DockerClusterTool",
        "docker_remove_secret" => "Ai::Tools::DockerClusterTool",
        "docker_list_configs" => "Ai::Tools::DockerClusterTool",
        "docker_create_config" => "Ai::Tools::DockerClusterTool",
        "docker_remove_config" => "Ai::Tools::DockerClusterTool",
        # Docker infrastructure management — hosts
        "docker_list_hosts" => "Ai::Tools::DockerHostTool",
        "docker_get_host" => "Ai::Tools::DockerHostTool",
        "docker_sync_host" => "Ai::Tools::DockerHostTool",
        "docker_test_host" => "Ai::Tools::DockerHostTool",
        # Docker infrastructure management — images
        "docker_list_images" => "Ai::Tools::DockerImageTool",
        "docker_pull_image" => "Ai::Tools::DockerImageTool",
        "docker_remove_image" => "Ai::Tools::DockerImageTool",
        "docker_tag_image" => "Ai::Tools::DockerImageTool",
        # Docker infrastructure management — networks and volumes
        "docker_list_networks" => "Ai::Tools::DockerNetworkVolumeTool",
        "docker_create_network" => "Ai::Tools::DockerNetworkVolumeTool",
        "docker_remove_network" => "Ai::Tools::DockerNetworkVolumeTool",
        "docker_list_volumes" => "Ai::Tools::DockerNetworkVolumeTool",
        "docker_create_volume" => "Ai::Tools::DockerNetworkVolumeTool",
        "docker_remove_volume" => "Ai::Tools::DockerNetworkVolumeTool"
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
