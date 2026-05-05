# frozen_string_literal: true

module Ai
  module Tools
    class PlatformApiToolRegistry
      TOOLS = {
        # System extension fleet (Golden Eclipse M5)
        "system_list_nodes" => "Ai::Tools::SystemFleetTool",
        "system_get_node" => "Ai::Tools::SystemFleetTool",
        "system_create_node" => "Ai::Tools::SystemFleetTool",
        "system_list_instances" => "Ai::Tools::SystemFleetTool",
        "system_get_instance" => "Ai::Tools::SystemFleetTool",
        "system_provision_instance" => "Ai::Tools::SystemFleetTool",
        "system_terminate_instance" => "Ai::Tools::SystemFleetTool",
        "system_list_templates" => "Ai::Tools::SystemFleetTool",
        "system_get_template" => "Ai::Tools::SystemFleetTool",
        "system_assign_module_to_template" => "Ai::Tools::SystemFleetTool",
        "system_list_modules" => "Ai::Tools::SystemFleetTool",
        "system_get_module" => "Ai::Tools::SystemFleetTool",
        "system_list_module_versions" => "Ai::Tools::SystemFleetTool",
        "system_promote_module_version" => "Ai::Tools::SystemFleetTool",
        "system_drift_report" => "Ai::Tools::SystemFleetTool",
        "system_list_tasks" => "Ai::Tools::SystemFleetTool",
        "system_cancel_task" => "Ai::Tools::SystemFleetTool",
        # Slice 7 — instance pools
        "system_list_instance_pools" => "Ai::Tools::SystemFleetTool",
        "system_get_instance_pool" => "Ai::Tools::SystemFleetTool",
        "system_create_instance_pool" => "Ai::Tools::SystemFleetTool",
        "system_drain_instance_pool" => "Ai::Tools::SystemFleetTool",
        "system_acquire_pooled_instance" => "Ai::Tools::SystemFleetTool",
        "system_replenish_instance_pool" => "Ai::Tools::SystemFleetTool",
        # Gap remediation slice 1 — operator-runbook-driven actions
        "system_drain_instance" => "Ai::Tools::SystemFleetTool",
        "system_get_silent_instances" => "Ai::Tools::SystemFleetTool",
        "system_validate_module_manifest" => "Ai::Tools::SystemFleetTool",
        # Gap remediation slice 2 — CVE catalog + module assignment cleanup
        "system_get_cve" => "Ai::Tools::SystemFleetTool",
        "system_get_cve_exposure" => "Ai::Tools::SystemFleetTool",
        "system_create_cve" => "Ai::Tools::SystemFleetTool",
        "system_delete_cve" => "Ai::Tools::SystemFleetTool",
        "system_unassign_module_from_template" => "Ai::Tools::SystemFleetTool",
        # Gap remediation slice 3 — pool ops + canary marking
        "system_return_pooled_instance" => "Ai::Tools::SystemFleetTool",
        "system_delete_instance_pool" => "Ai::Tools::SystemFleetTool",
        "system_module_mark_canary" => "Ai::Tools::SystemFleetTool",
        # Gap remediation slice 5 — disk image CI
        "system_list_disk_image_publications" => "Ai::Tools::SystemFleetTool",
        "system_set_default_disk_image_publication" => "Ai::Tools::SystemFleetTool",
        "system_set_disk_image_retention" => "Ai::Tools::SystemFleetTool",
        "system_provision_ci_worker" => "Ai::Tools::SystemFleetTool",
        "system_terminate_ci_worker" => "Ai::Tools::SystemFleetTool",
        "system_list_ci_workers" => "Ai::Tools::SystemFleetTool",
        "system_list_disk_image_webhooks" => "Ai::Tools::SystemFleetTool",
        # Missing-features slice 6a — GitOps reconciler MCP surface
        "system_gitops_register_repository" => "Ai::Tools::SystemFleetTool",
        "system_gitops_sync_repository" => "Ai::Tools::SystemFleetTool",
        "system_gitops_get_sync_run" => "Ai::Tools::SystemFleetTool",
        "system_gitops_get_drift_report" => "Ai::Tools::SystemFleetTool",
        # Missing-features slice Vault DR-3 — pepper rotation
        "system_rotate_vault_transit_pepper" => "Ai::Tools::SystemFleetTool",
        # SDWAN overlay (Slice 1 of we-are-continuing-development-spicy-bear.md)
        "system_sdwan_list_networks"   => "Ai::Tools::SdwanTool",
        "system_sdwan_get_network"     => "Ai::Tools::SdwanTool",
        "system_sdwan_create_network"  => "Ai::Tools::SdwanTool",
        "system_sdwan_update_network"  => "Ai::Tools::SdwanTool",
        "system_sdwan_delete_network"  => "Ai::Tools::SdwanTool",
        "system_sdwan_list_peers"      => "Ai::Tools::SdwanTool",
        "system_sdwan_get_peer"        => "Ai::Tools::SdwanTool",
        "system_sdwan_attach_peer"     => "Ai::Tools::SdwanTool",
        "system_sdwan_detach_peer"     => "Ai::Tools::SdwanTool",
        "system_sdwan_get_topology"    => "Ai::Tools::SdwanTool",
        # Slice 2: firewall
        "system_sdwan_list_firewall_rules"  => "Ai::Tools::SdwanTool",
        "system_sdwan_get_firewall_rule"    => "Ai::Tools::SdwanTool",
        "system_sdwan_create_firewall_rule" => "Ai::Tools::SdwanTool",
        "system_sdwan_update_firewall_rule" => "Ai::Tools::SdwanTool",
        "system_sdwan_delete_firewall_rule" => "Ai::Tools::SdwanTool",
        # Slice 4: user VPN
        "system_sdwan_list_access_grants"   => "Ai::Tools::SdwanTool",
        "system_sdwan_create_access_grant"  => "Ai::Tools::SdwanTool",
        "system_sdwan_revoke_access_grant"  => "Ai::Tools::SdwanTool",
        "system_sdwan_list_user_devices"    => "Ai::Tools::SdwanTool",
        "system_sdwan_issue_user_device"    => "Ai::Tools::SdwanTool",
        "system_sdwan_revoke_user_device"   => "Ai::Tools::SdwanTool",
        # Slice 6: federation
        "system_sdwan_list_federation_peers"   => "Ai::Tools::SdwanTool",
        "system_sdwan_get_federation_peer"     => "Ai::Tools::SdwanTool",
        "system_sdwan_propose_federation_peer" => "Ai::Tools::SdwanTool",
        "system_sdwan_accept_federation_peer"  => "Ai::Tools::SdwanTool",
        "system_sdwan_revoke_federation_peer"  => "Ai::Tools::SdwanTool",
        "system_sdwan_federation_scan"         => "Ai::Tools::SdwanTool",
        # Slice 9a: routing layer (static subnet routing)
        "system_sdwan_set_peer_lan_subnets"        => "Ai::Tools::SdwanTool",
        "system_sdwan_set_network_routing_mode"    => "Ai::Tools::SdwanTool",
        "system_sdwan_list_subnet_advertisements"  => "Ai::Tools::SdwanTool",
        "system_sdwan_get_routing_summary"         => "Ai::Tools::SdwanTool",
        # Slice 9b: virtual IPs
        "system_sdwan_create_virtual_ip"           => "Ai::Tools::SdwanTool",
        "system_sdwan_list_virtual_ips"            => "Ai::Tools::SdwanTool",
        "system_sdwan_get_virtual_ip"              => "Ai::Tools::SdwanTool",
        "system_sdwan_update_virtual_ip"           => "Ai::Tools::SdwanTool",
        "system_sdwan_delete_virtual_ip"           => "Ai::Tools::SdwanTool",
        "system_sdwan_failover_virtual_ip"         => "Ai::Tools::SdwanTool",
        "system_sdwan_list_vip_assignments"        => "Ai::Tools::SdwanTool",
        # Slice 9c: iBGP / FRR control plane
        "system_sdwan_get_account_bgp"             => "Ai::Tools::SdwanTool",
        "system_sdwan_set_account_as_number"       => "Ai::Tools::SdwanTool",
        "system_sdwan_get_bgp_sessions"            => "Ai::Tools::SdwanTool",
        "system_sdwan_get_bgp_config_for_peer"     => "Ai::Tools::SdwanTool",
        # Slice 9e: route policies
        "system_sdwan_list_route_policies"         => "Ai::Tools::SdwanTool",
        "system_sdwan_get_route_policy"            => "Ai::Tools::SdwanTool",
        "system_sdwan_create_route_policy"         => "Ai::Tools::SdwanTool",
        "system_sdwan_update_route_policy"         => "Ai::Tools::SdwanTool",
        "system_sdwan_delete_route_policy"         => "Ai::Tools::SdwanTool",
        "system_sdwan_compile_route_policy"        => "Ai::Tools::SdwanTool",
        # Slice 7b: hub port mappings
        "system_sdwan_list_port_mappings"          => "Ai::Tools::SdwanTool",
        "system_sdwan_get_port_mapping"            => "Ai::Tools::SdwanTool",
        "system_sdwan_create_port_mapping"         => "Ai::Tools::SdwanTool",
        "system_sdwan_update_port_mapping"         => "Ai::Tools::SdwanTool",
        "system_sdwan_delete_port_mapping"         => "Ai::Tools::SdwanTool",
        # Phase B: Docker daemon auto-provisioning on NodeInstances.
        # Distinct from the docker_* family below — those tools manage
        # *external*, operator-registered hosts; these manage *managed*
        # hosts whose lifecycle is bound to a System::NodeInstance.
        "system_provision_docker_runtime"          => "Ai::Tools::DockerProvisioningTool",
        "system_decommission_docker_runtime"       => "Ai::Tools::DockerProvisioningTool",
        "system_mark_docker_ready"                 => "Ai::Tools::DockerProvisioningTool",
        "system_list_managed_docker_hosts"         => "Ai::Tools::DockerProvisioningTool",
        # Phase 2: Kubernetes (K3s today, kubeadm in Phase 3).
        # Cluster *creation* is implicit via module assignment +
        # agent-driven bootstrap — there is no kubernetes_create_cluster
        # action. The MCP surface is read + decommission + kubeconfig.
        "kubernetes_list_clusters"                 => "Ai::Tools::KubernetesClusterTool",
        "kubernetes_get_cluster"                   => "Ai::Tools::KubernetesClusterTool",
        "kubernetes_list_nodes"                    => "Ai::Tools::KubernetesClusterTool",
        "kubernetes_decommission_cluster"          => "Ai::Tools::KubernetesProvisioningTool",
        "kubernetes_get_kubeconfig"                => "Ai::Tools::KubernetesProvisioningTool",
        # Project & CI/CD
        "create_gitea_repository" => "Ai::Tools::ProjectInitTool",
        "update_gitea_repository" => "Ai::Tools::RepoManagementTool",
        "dispatch_to_runner" => "Ai::Tools::RunnerDispatchTool",
        # Gitea Actions: secrets management + workflow_dispatch + run monitoring.
        # Plan: docs/plans/wondrous-yawning-anchor.md (Phase 2 — operator-driven CI).
        "set_gitea_action_secret"        => "Ai::Tools::GiteaActionsTool",
        "set_gitea_action_secrets_bulk"  => "Ai::Tools::GiteaActionsTool",
        "list_gitea_action_secrets"      => "Ai::Tools::GiteaActionsTool",
        "delete_gitea_action_secret"     => "Ai::Tools::GiteaActionsTool",
        "dispatch_gitea_workflow"        => "Ai::Tools::GiteaActionsTool",
        "list_gitea_workflows"           => "Ai::Tools::GiteaActionsTool",
        "list_gitea_workflow_runs"       => "Ai::Tools::GiteaActionsTool",
        "get_gitea_workflow_run"         => "Ai::Tools::GiteaActionsTool",
        "get_gitea_job_logs"             => "Ai::Tools::GiteaActionsTool",
        "cancel_gitea_workflow_run"      => "Ai::Tools::GiteaActionsTool",
        "rerun_gitea_workflow"           => "Ai::Tools::GiteaActionsTool",
        "create_gitea_user_token"        => "Ai::Tools::GiteaActionsTool",
        "list_gitea_user_tokens"         => "Ai::Tools::GiteaActionsTool",
        "delete_gitea_user_token"        => "Ai::Tools::GiteaActionsTool",
        # Platform-side disk-image operator wrappers (one MCP call =
        # one operator-meaningful step). Plan: docs/plans/wondrous-yawning-anchor.md.
        "provision_disk_image_webhook"   => "Ai::Tools::DiskImageOperatorTool",
        "provision_ci_worker"            => "Ai::Tools::DiskImageOperatorTool",
        "bootstrap_disk_image_ci"        => "Ai::Tools::DiskImageOperatorTool",
        # Container deployment & management
        "deploy_container_agent" => "Ai::Tools::ContainerDeploymentTool",
        "container_status" => "Ai::Tools::ContainerStatusTool",
        "container_logs" => "Ai::Tools::ContainerLogsTool",
        "container_terminate" => "Ai::Tools::ContainerTerminateTool",
        # Integration health
        "integration_health" => "Ai::Tools::IntegrationHealthTool",
        # Ralph Loop management (autonomous agent duty cycles)
        "list_ralph_loops" => "Ai::Tools::RalphLoopTool",
        "get_ralph_loop" => "Ai::Tools::RalphLoopTool",
        "pause_ralph_loop" => "Ai::Tools::RalphLoopTool",
        "resume_ralph_loop" => "Ai::Tools::RalphLoopTool",
        "delete_ralph_loop" => "Ai::Tools::RalphLoopTool",
        "get_ralph_loop_statistics" => "Ai::Tools::RalphLoopTool",
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
        # Pipeline management
        "trigger_pipeline" => "Ai::Tools::PipelineManagementTool",
        "list_pipelines" => "Ai::Tools::PipelineManagementTool",
        "get_pipeline_status" => "Ai::Tools::PipelineManagementTool",
        # Memory management
        "write_shared_memory" => "Ai::Tools::MemoryTool",
        "read_shared_memory" => "Ai::Tools::MemoryTool",
        "delete_shared_memory" => "Ai::Tools::MemoryTool",
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
        "delete_knowledge" => "Ai::Tools::SharedKnowledgeTool",
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
        # Conversations (unified — workspaces, agent chats, concierge)
        "send_message" => "Ai::Tools::ConversationTool",
        "send_concierge_message" => "Ai::Tools::ConversationTool",
        "confirm_concierge_action" => "Ai::Tools::ConversationTool",
        "list_messages" => "Ai::Tools::ConversationTool",
        "get_conversation_messages" => "Ai::Tools::ConversationTool",
        "list_conversations" => "Ai::Tools::ConversationTool",
        "list_workspaces" => "Ai::Tools::ConversationTool",
        "create_workspace" => "Ai::Tools::ConversationTool",
        "invite_agent" => "Ai::Tools::ConversationTool",
        "active_sessions" => "Ai::Tools::ConversationTool",
        # Activity monitoring
        "get_activity_feed" => "Ai::Tools::ActivityMonitorTool",
        "get_mission_status" => "Ai::Tools::ActivityMonitorTool",
        "get_notifications" => "Ai::Tools::ActivityMonitorTool",
        "dismiss_notification" => "Ai::Tools::ActivityMonitorTool",
        "dismiss_all_notifications" => "Ai::Tools::ActivityMonitorTool",
        "mark_all_notifications_read" => "Ai::Tools::ActivityMonitorTool",
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
        "docker_remove_volume" => "Ai::Tools::DockerNetworkVolumeTool",
        # Trading — portfolio & wallets
        "trading_list_portfolios" => "Ai::Tools::TradingPortfolioTool",
        "trading_get_portfolio" => "Ai::Tools::TradingPortfolioTool",
        "trading_portfolio_summary" => "Ai::Tools::TradingPortfolioTool",
        "trading_portfolio_performance" => "Ai::Tools::TradingPortfolioTool",
        "trading_portfolio_allocations" => "Ai::Tools::TradingPortfolioTool",
        "trading_create_portfolio" => "Ai::Tools::TradingPortfolioTool",
        "trading_update_portfolio" => "Ai::Tools::TradingPortfolioTool",
        "trading_list_wallets" => "Ai::Tools::TradingPortfolioTool",
        "trading_compounding_summary" => "Ai::Tools::TradingPortfolioTool",
        # Trading — strategies
        "trading_list_strategies" => "Ai::Tools::TradingStrategyTool",
        "trading_get_strategy" => "Ai::Tools::TradingStrategyTool",
        "trading_create_strategy" => "Ai::Tools::TradingStrategyTool",
        "trading_update_strategy" => "Ai::Tools::TradingStrategyTool",
        "trading_activate_strategy" => "Ai::Tools::TradingStrategyTool",
        "trading_pause_strategy" => "Ai::Tools::TradingStrategyTool",
        "trading_decommission_strategy" => "Ai::Tools::TradingStrategyTool",
        "trading_decline_strategy" => "Ai::Tools::TradingStrategyTool",
        "trading_recover_strategy" => "Ai::Tools::TradingStrategyTool",
        "trading_demote_strategy" => "Ai::Tools::TradingStrategyTool",
        "trading_advance_phase" => "Ai::Tools::TradingStrategyTool",
        "trading_strategy_performance" => "Ai::Tools::TradingStrategyTool",
        "trading_strategy_versions" => "Ai::Tools::TradingStrategyTool",
        "trading_lifecycle_summary" => "Ai::Tools::TradingStrategyTool",
        # Trading — orders, positions, trades
        "trading_list_positions" => "Ai::Tools::TradingOrderPositionTool",
        "trading_get_position" => "Ai::Tools::TradingOrderPositionTool",
        "trading_open_positions" => "Ai::Tools::TradingOrderPositionTool",
        "trading_closed_positions" => "Ai::Tools::TradingOrderPositionTool",
        "trading_close_position" => "Ai::Tools::TradingOrderPositionTool",
        "trading_list_orders" => "Ai::Tools::TradingOrderPositionTool",
        "trading_cancel_order" => "Ai::Tools::TradingOrderPositionTool",
        "trading_list_trades" => "Ai::Tools::TradingOrderPositionTool",
        # Trading — market data & venues
        "trading_list_venues" => "Ai::Tools::TradingMarketDataTool",
        "trading_get_venue" => "Ai::Tools::TradingMarketDataTool",
        "trading_test_venue_connection" => "Ai::Tools::TradingMarketDataTool",
        "trading_list_price_feeds" => "Ai::Tools::TradingMarketDataTool",
        "trading_market_regime" => "Ai::Tools::TradingMarketDataTool",
        "trading_list_signals" => "Ai::Tools::TradingMarketDataTool",
        "trading_market_discovery" => "Ai::Tools::TradingMarketDataTool",
        "trading_refresh_market_discovery" => "Ai::Tools::TradingMarketDataTool",
        "trading_market_arms" => "Ai::Tools::TradingMarketDataTool",
        # Trading — risk management
        "trading_get_risk_profile" => "Ai::Tools::TradingRiskTool",
        "trading_update_risk_profile" => "Ai::Tools::TradingRiskTool",
        "trading_risk_events" => "Ai::Tools::TradingRiskTool",
        "trading_reset_circuit_breaker" => "Ai::Tools::TradingRiskTool",
        "trading_list_sweep_rules" => "Ai::Tools::TradingRiskTool",
        "trading_list_sweep_proposals" => "Ai::Tools::TradingRiskTool",
        # Trading — marketplace (publish, subscribe, follow, signals)
        "trading_list_published_strategies" => "Ai::Tools::TradingMarketplaceTool",
        "trading_get_published_strategy" => "Ai::Tools::TradingMarketplaceTool",
        "trading_publish_strategy" => "Ai::Tools::TradingMarketplaceTool",
        "trading_unpublish_strategy" => "Ai::Tools::TradingMarketplaceTool",
        "trading_list_subscriptions" => "Ai::Tools::TradingMarketplaceTool",
        "trading_subscribe" => "Ai::Tools::TradingMarketplaceTool",
        "trading_unsubscribe" => "Ai::Tools::TradingMarketplaceTool",
        "trading_pause_subscription" => "Ai::Tools::TradingMarketplaceTool",
        "trading_resume_subscription" => "Ai::Tools::TradingMarketplaceTool",
        "trading_list_forwarded_signals" => "Ai::Tools::TradingMarketplaceTool",
        "trading_subscription_performance" => "Ai::Tools::TradingMarketplaceTool",
        "trading_follow_publisher" => "Ai::Tools::TradingMarketplaceTool",
        "trading_unfollow_publisher" => "Ai::Tools::TradingMarketplaceTool",
        "trading_list_publisher_follows" => "Ai::Tools::TradingMarketplaceTool",
        "trading_list_performance_fees" => "Ai::Tools::TradingMarketplaceTool",
        "trading_fee_summary" => "Ai::Tools::TradingMarketplaceTool",
        # Trading — simulations & training
        "trading_list_simulations" => "Ai::Tools::TradingSimulationTool",
        "trading_get_simulation" => "Ai::Tools::TradingSimulationTool",
        "trading_create_simulation" => "Ai::Tools::TradingSimulationTool",
        "trading_run_simulation" => "Ai::Tools::TradingSimulationTool",
        "trading_pause_simulation" => "Ai::Tools::TradingSimulationTool",
        "trading_simulation_report" => "Ai::Tools::TradingSimulationTool",
        "trading_list_training_sessions" => "Ai::Tools::TradingSimulationTool",
        "trading_get_training_session" => "Ai::Tools::TradingSimulationTool",
        "trading_create_training_session" => "Ai::Tools::TradingSimulationTool",
        "trading_cancel_training_session" => "Ai::Tools::TradingSimulationTool",
        "trading_complete_training_session" => "Ai::Tools::TradingSimulationTool",
        "trading_retry_training_session" => "Ai::Tools::TradingSimulationTool",
        "trading_resume_training_session" => "Ai::Tools::TradingSimulationTool",
        "trading_discover_venue_series" => "Ai::Tools::TradingSimulationTool",
        "trading_delete_training_session" => "Ai::Tools::TradingSimulationTool",
        "trading_training_session_report" => "Ai::Tools::TradingSimulationTool",
        # Trading — strategy parameters
        "trading_get_strategy_params" => "Ai::Tools::TradingSimulationTool",
        "trading_update_strategy_params" => "Ai::Tools::TradingSimulationTool",
        "trading_seed_strategy_defaults" => "Ai::Tools::TradingSimulationTool",
        "trading_seed_profit_formula" => "Ai::Tools::TradingSimulationTool",
        # Trading — backtesting & parameter sweep
        "trading_import_historical_data" => "Ai::Tools::TradingSimulationTool",
        "trading_run_backtest" => "Ai::Tools::TradingSimulationTool",
        "trading_parameter_sweep" => "Ai::Tools::TradingSimulationTool",
        # Trading — evolution & audit
        "trading_list_evolution_epochs" => "Ai::Tools::TradingEvolutionTool",
        "trading_get_evolution_epoch" => "Ai::Tools::TradingEvolutionTool",
        "trading_evolution_leaderboard" => "Ai::Tools::TradingEvolutionTool",
        "trading_trigger_evolution" => "Ai::Tools::TradingEvolutionTool",
        "trading_list_audit_logs" => "Ai::Tools::TradingEvolutionTool",
        # Codebase Intelligence — Discovery
        "code_context_tree" => "Ai::Tools::CodeDiscoveryTool",
        "code_file_skeleton" => "Ai::Tools::CodeDiscoveryTool",
        "code_semantic_search" => "Ai::Tools::CodeDiscoveryTool",
        "code_identifier_search" => "Ai::Tools::CodeDiscoveryTool",
        "code_semantic_navigate" => "Ai::Tools::CodeDiscoveryTool",
        "code_feature_hub" => "Ai::Tools::CodeDiscoveryTool",
        # Codebase Intelligence — Analysis
        "code_blast_radius" => "Ai::Tools::CodeAnalysisTool",
        "code_static_analysis" => "Ai::Tools::CodeAnalysisTool",
        "code_index_status" => "Ai::Tools::CodeAnalysisTool",
        "code_dead_code" => "Ai::Tools::CodeAnalysisTool",
        "code_find_duplicates" => "Ai::Tools::CodeAnalysisTool",
        "code_analyze_section" => "Ai::Tools::CodeAnalysisTool",
        # Codebase Intelligence — Memory
        "code_upsert_node" => "Ai::Tools::CodeMemoryTool",
        "code_create_relation" => "Ai::Tools::CodeMemoryTool",
        "code_search_graph" => "Ai::Tools::CodeMemoryTool",
        "code_prune_stale" => "Ai::Tools::CodeMemoryTool",
        "code_bulk_index" => "Ai::Tools::CodeMemoryTool"
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
