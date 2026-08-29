# frozen_string_literal: true

module Ai
  # Reduces an agent's tool registry to a relevance-scoped subset for a
  # single LLM call.
  #
  # Why: providers cap tool counts per request — OpenAI rejects >128 with
  # HTTP 400 ("Invalid 'tools': array too long"). Anthropic is higher but
  # still bounded. The Concierge agent registers 158+ tools spanning
  # provisioning, devops, knowledge, memory, governance, code intelligence,
  # etc. — far too many to inject on every chat turn.
  #
  # Filter strategy:
  #   1. Detect intents in the user's most recent message via keyword match.
  #      Multiple intents possible (e.g. "deploy a server with monitoring"
  #      → provisioning + devops + governance).
  #   2. Allowlist tool names that match those intents' name-prefix patterns.
  #   3. Always include a small set of universal tools (confirmation,
  #      notifications, introspection, knowledge search) regardless of intent.
  #   4. If the result still exceeds max_tools, hard-truncate; if no intents
  #      matched, fall back to always-on plus the first N remaining tools.
  #
  # The classifier is intentionally cheap (no LLM pre-pass) — keyword
  # matching keeps the filter ~free and deterministic. False negatives
  # (intent missed) degrade to "fewer tools available" rather than wrong
  # results. False positives (extra category included) just consume more
  # of the cap.
  class ToolRelevanceFilter
    # Universal tools — surfaced for every chat regardless of intent so
    # the agent can always check status, look things up, and ask for
    # confirmation on risky actions.
    ALWAYS_ON = %w[
      request_confirmation
      get_notifications
      dismiss_notification
      mark_all_notifications_read
      agent_introspect
      get_system_health
      search_knowledge
      query_learnings
      search_memory
      get_activity_feed
    ].freeze

    # Maps an intent label to a regex matching tool names belonging to that
    # intent's surface area. Patterns are anchored to the start of the tool
    # name so we don't accidentally match substrings.
    INTENT_TOOL_PATTERNS = {
      "provision_infrastructure" => /\A(platform_provisioning_|system_|docker_|kubernetes_)/,
      "deploy" => /\A(dispatch_to_|create_gitea_|update_gitea_|gitea_|list_gitea_|get_gitea_|delete_gitea_|set_gitea_|trigger_|list_pipelines|get_pipeline|cancel_gitea_|rerun_gitea_|create_gitea_user_token|list_gitea_user_tokens|delete_gitea_user_token|deploy_)/,
      "memory" => /\A(memory_|shared_memory_|agent_remember|agent_forget|agent_recall|agent_reflect|consolidate_memory|read_shared_memory|write_shared_memory|delete_shared_memory|search_memory|list_pools|memory_stats)/,
      "knowledge" => /\A(search_knowledge|query_knowledge|create_knowledge|update_knowledge|delete_knowledge|promote_knowledge|search_documents|knowledge_|kb_|list_kb|get_kb|create_kb|update_kb|query_knowledge_base|get_api_reference|query_learnings|reinforce_learning|create_learning|learning_metrics)/,
      "skill" => /\A(skill_|get_skill|discover_skill|create_skill|update_skill|delete_skill|toggle_skill|clone_skill|compose_skills|mutate_skill|auto_evolve_skill|get_skill_context|list_skills|skill_health|skill_metrics)/,
      "graph" => /\A(graph_|subgraph|reason_knowledge_graph|search_knowledge_graph|extract_to_knowledge_graph|get_graph_node|list_graph_nodes|get_graph_neighbors|graph_statistics|get_subgraph)/,
      "team" => /\A(team_|workspace_|create_team|add_team_member|execute_team|get_team|list_teams|update_team|optimize_team|invite_agent|active_sessions|create_workspace|list_workspaces|send_message|list_messages)/,
      "code" => /\Acode_/,
      "agent_management" => /\A(create_agent|list_agents|get_agent|update_agent|execute_agent|spawn_task|check_task_status|wait_for_task|recruit_agent|get_mission_status)/,
      # `approve_plan` and `validate_plan` were listed here until
      # IMP-4707960fc610. Steering an agent to them was the harmful half of that
      # defect: the filter advertised them as the governance step for a plan,
      # and both verbs answered "service not available" on every call, so an
      # agent following the protocol could reasonably read the refusal as "no
      # gate here" and proceed ungoverned. Neither verb exists any more.
      #
      # Nothing is lost by their removal, because nothing was there: this list
      # STEERS which tools are offered in a turn, it does not GATE anything, and
      # the one live plan-approval verb is `platform_provisioning_approve_plan`,
      # which the provision_infrastructure intent already matches.
      #
      # One residual, stated so it is not mistaken for full coverage: that holds
      # of the PATTERN, not of intent DETECTION. "approve" and "plan" are
      # keywords for `governance`, not for `provision_infrastructure`, so a bare
      # "approve the plan" turn now surfaces no plan-approval verb at all.
      # Strictly better than surfacing an inert one, but it is a gap, not parity.
      "governance" => /\A(governance_|create_agent_goal|update_agent_goal|list_agent_goals|decompose_goal|escalate|create_proposal|propose_feature|report_issue|request_feedback|generate_self_challenge|list_challenges|get_challenge_result|detect_collusion|emit_signal|perceive_signals|reinforce_signal|measure_pressure|perceive_pressure|send_proactive_notification|emergency_|kill_switch_status)/,
      # Autonomous Improvement Campaigns + discovery/delegation control plane: surface the
      # campaign_* queue/delegation tools and the dev-loop drain tools when the user talks
      # about campaigns, the proposal/discovery queue, delegation, or draining a loop.
      "campaign" => /\A(campaign_|dev_next_task|dev_complete_task|dev_list_tasks|dev_update_task|delegate_ralph_task)/,
      # Remaining feature areas — so the concierge can reach EVERY platform capability.
      "mission" => /\A(get_mission_status|mission_|list_missions|create_mission|start_mission)/,
      "rag" => /\A(query_knowledge_base|list_knowledge_bases|create_knowledge_base|add_document|process_document|search_documents|delete_document)/,
      "content" => /\A(list_pages|get_page|create_page|update_page|list_kb_articles|get_kb_article|create_kb_article|update_kb_article)/,
      "image_generation" => /\A(generate_image|list_generated_images)/,
      "monitoring" => /\A(get_activity_feed|recent_events|get_notifications|mark_all_notifications_read|dismiss_notification|dismiss_all_notifications|integration_health|get_system_health|active_sessions)/
    }.freeze

    # Maps free-text keywords to intent labels. Multiple keywords can match
    # the same intent; multiple intents can match a single message.
    KEYWORD_TO_INTENT = {
      "provision_infrastructure" => /\b(provision|host|stack|cluster|server|instance|node template|virtual machine|spin up|infrastructure|database|scale up|scale down|migrate to|qemu|kvm|docker|kubernetes|k3s|k8s|container)\b/i,
      "deploy" => /\b(pipeline|workflow|gitea|github actions?|ci\/cd|runner|build|repo|repository|deploy(ment)?)\b/i,
      "memory" => /\b(remember|recall|memory|forget|context window|stash)\b/i,
      "knowledge" => /\b(search|find|article|wiki|knowledge|learning|how do i|how to|kb |knowledge base)\b/i,
      "skill" => /\b(skill|capability)\b/i,
      "graph" => /\b(knowledge graph|graph node|relationship)\b/i,
      "team" => /\b(team|workspace|delegate|coordinate|hand off|hand-off|assign to)\b|@\w+/i,
      "code" => /\b(code|symbol|class|function|file in (the )?repo|grep|codebase)\b/i,
      "agent_management" => /\b(agent|spawn|sub.?agent|execute (the )?agent|launch (an? )?agent|recruit)\b/i,
      "governance" => /\b(escalate|propose|goal|approve|reject|kill switch|emergency|halt|policy|trust)\b/i,
      "campaign" => /\b(campaign|discovery queue|proposal queue|dev.?loop|ralph loop|improvement campaign|drain (the )?(backlog|queue|loop))\b/i,
      "mission" => /\b(mission|launch (a )?mission|run (a )?mission)\b/i,
      "rag" => /\b(document|rag|upload|index|knowledge base|embed|vectoriz|ingest)/i,
      "content" => /\b(page|wiki|article|kb article|documentation|content)\b/i,
      "image_generation" => /\b(image|picture|logo|diagram|render|illustration|generate (an? )?(image|picture|logo))\b/i,
      "monitoring" => /\b(status|health|monitor|activity|notification|recent events|what.?s happening|dashboard|metrics)\b/i
    }.freeze

    # @param tool_definitions [Array<Hash>] tool defs in LLM function-calling shape
    # @param user_message [String, nil] most recent user message content
    # @param max_tools [Integer] hard cap on returned tool count (provider-bound)
    # @return [Array<Hash>] filtered subset
    def self.filter(tool_definitions, user_message:, max_tools: 100)
      return tool_definitions if tool_definitions.size <= max_tools

      intents = detect_intents(user_message)
      always_on, others = tool_definitions.partition { |t| ALWAYS_ON.include?(tool_name(t)) }

      if intents.empty?
        # No clear intent — return always-on plus the first slice of others
        # to give the agent SOMETHING to work with. Logged as a warn so we
        # know to refine keyword patterns.
        Rails.logger.warn "[ToolRelevanceFilter] no intent detected; falling back to always-on + first #{max_tools - always_on.size}"
        return always_on + others.first(max_tools - always_on.size)
      end

      patterns = intents.map { |i| INTENT_TOOL_PATTERNS[i] }.compact
      matched = others.select { |t| patterns.any? { |p| tool_name(t).match?(p) } }
      result = always_on + matched

      if result.size > max_tools
        Rails.logger.warn "[ToolRelevanceFilter] intent-matched tools (#{result.size}) exceed cap #{max_tools}; truncating"
        result = result.first(max_tools)
      end

      result
    end

    def self.detect_intents(message)
      return [] if message.blank?
      KEYWORD_TO_INTENT.each_with_object([]) do |(intent, pattern), acc|
        acc << intent if message.match?(pattern)
      end
    end

    def self.tool_name(tool)
      tool[:name] || tool.dig(:function, :name) || tool["name"] || tool.dig("function", "name")
    end
  end
end
