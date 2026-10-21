# frozen_string_literal: true

module Ai
  module ClaudeExport
    # The committed Claude Code skeleton of a C4 survivor
    # (Ai::Agents::CanonicalRoster): a THIN LOADER, at most MAX_LINES lines, that
    # holds no charter, skill list, policy or per-agent tool list. Claude Code
    # hot-reloads .claude/agents/, but anything rendered from platform data would
    # still need a re-sync and a committed diff whenever that data moved, and the
    # platform row would stop being the single source of truth. #render is
    # therefore a pure function of the roster
    # declaration (its tier, description and role) — it reads no database row and no tool registry —
    # and the body tells the subagent to fetch the rest by slug at spawn time
    # (docs/operations/streamlining-review-2026-10-19.md §4.4).
    #
    # `tools:` is a FIXED bootstrap core:
    #   * Read/Grep/Glob for everyone; Edit/Write/Bash for a role that changes code
    #     (the engineer); Bash alone for a guarded role that only checks work (none
    #     in phase 1: the reviewer has no shell);
    #   * ToolSearch: with MCP tool search on (the Claude Code default) every
    #     MCP tool reaches a subagent DEFERRED, its schema loaded on demand
    #     through ToolSearch — a subagent without it cannot call even the
    #     bootstrap verbs it lists;
    #   * the bootstrap verbs, by exact name (BOOTSTRAP_ACTIONS);
    #   * SERVER_GRANT for the roles that act through platform verbs. `tools:`
    #     is a hard allowlist and ToolSearch only searches inside it, so "load
    #     the verbs your skills name" is impossible without it. Claude Code
    #     documents `mcp__<server>__*` as the whole-server grant for `tools:`
    #     (the bare `mcp__<server>` form is documented for disallowedTools
    #     only), and resolves no prefix inside one server. The grant widens
    #     nothing the session itself cannot call: the subagent rides the
    #     session's MCP principal, permission-scoped and AutonomyGate-gated
    #     platform-side — EXCEPT for a session principal: Mcp::Principal#may_invoke?
    #     admits every verb for a user principal, and a verb whose declare_action
    #     carries no action_category never reaches AutonomyGate. DENIED_ACTIONS
    #     are those destructive-but-ungated verbs; the granted roles render them
    #     as `disallowedTools:` so an autonomous executor cannot call them by
    #     name. It holds because a streamable-HTTP call runs the action its
    #     tool name names (McpPlatformToolRegistrar::ACTION_PINNED_ORIGINS), so
    #     a listed verb cannot be reached through a sibling tool of its class.
    #     It is still client-side and advisory: the boundary is the server-side
    #     gate, so drop a name here once its verb is gated (C13 increment 2).
    module ThinLoader
      MCP_PREFIX = ToolAllowlist::MCP_PREFIX
      SERVER_GRANT = "mcp__powernode__*"
      READ_BUILTINS = %w[Read Grep Glob ToolSearch].freeze
      CODE_BUILTINS = ToolAllowlist::CODE_BUILTINS
      # A role that CHECKS work with a shell but never changes it gets Bash and no
      # Edit/Write, held read-only by its role[:shell_guard] hook. No core role uses
      # it in phase 1: the reviewer has no shell (the guard can fail open).
      SHELL_BUILTINS = %w[Bash].freeze

      # The progressive-disclosure floor. Named here, never derived from the
      # registry, so a newly registered verb cannot change a committed file.
      # thin_loader_spec holds it to a subset of the platform's own bootstrap
      # floor (ToolAllowlist::BOOTSTRAP_ACTIONS).
      BOOTSTRAP_ACTIONS = %w[
        get_agent assemble_task discover_skills describe_tool discover_tools
        search_knowledge query_learnings route_task record_agent_execution
      ].freeze

      # Destroy-shaped verbs (Mcp::Principal.destructive_tool? or
      # `destructive: true`) that no AutonomyGate declaration can park: the
      # platform already denies these to instance principals through
      # DESTRUCTIVE_TOOL_PATTERNS; this is that overlay expanded to exact names
      # for a session principal. thin_loader_spec recomputes the set from the
      # registry, so a newly registered ungated destroy-shaped verb fails CI
      # until it is listed here (or gated server-side and dropped).
      DENIED_DESTRUCTIVE_ACTIONS = %w[
        agent_container_terminate approve_deferred_operation archive_by_predicate code_prune_stale
        data_source_delete data_source_unsubscribe delete_agent delete_document delete_gitea_action_secret
        delete_gitea_user_token delete_gitea_workflow_run delete_knowledge delete_memory_pool
        delete_ralph_loop delete_shared_memory delete_skill delete_team detach_skill_from_agent
        docker_delete_config docker_delete_container docker_delete_image docker_delete_network
        docker_delete_secret docker_delete_service docker_delete_stack docker_delete_volume emergency_halt
        emergency_resume hard_delete_archived hard_delete_retired kubernetes_decommission_cluster
        prune_stale_git_runners reject_deferred_operation remove_team_member retire_by_predicate
        system_acme_revoke_certificate system_delete_architecture system_delete_cve
        system_delete_instance_pool system_delete_module system_delete_node system_delete_package_repository
        system_delete_provider system_delete_service system_delete_template system_delete_volume
        system_destroy_instance system_drain_instance system_drain_instance_pool system_instance_hold
        system_instance_release_hold system_reap_agent_fleet system_reboot_instance system_recycle_pool
        system_rotate_vault_transit_pepper system_stop_instance system_terminate_ci_worker
        system_upgrade_boot_image
      ].freeze

      # Sensitive but not destroy-shaped: code execution, credential and
      # token minting, cluster credentials, autonomy and trust levers, plan
      # approval.
      DENIED_SENSITIVE_ACTIONS = %w[
        docker_container_exec system_mint_peer_capability_token create_gitea_user_token
        set_gitea_action_secret set_gitea_action_secrets_bulk kubernetes_get_kubeconfig
        set_agent_autonomy_level update_agent_trust_score disable_autonomy enable_autonomy
        platform_provisioning_approve_plan
      ].freeze

      # Exact names: disallowedTools resolves no prefix inside one server.
      DENIED_ACTIONS = (DENIED_DESTRUCTIVE_ACTIONS + DENIED_SENSITIVE_ACTIONS).freeze

      # Budget for one file (ThinLoader spec, committed-skeleton spec).
      MAX_LINES = 24
      MAX_BYTES = 6_500

      module_function

      # @param slug [String] a roster slug; any other raises KeyError
      # @return [String] the skeleton file's full content
      def render(slug)
        spec = ::Ai::Agents::CanonicalRoster.fetch(slug)
        role = spec.fetch(:role)
        frontmatter = {
          "name" => slug,
          "description" => spec[:description],
          "model" => AgentSkeletonSync::TIER_TO_CC_MODEL.fetch(spec[:tier].to_sym),
          "tools" => tools_for(role).join(", ")
        }
        frontmatter["disallowedTools"] = disallowed_tools_for(role).join(", ") if role[:server_grant]
        # A read-only shell is enforced by a hook in the subagent's OWN frontmatter,
        # which Claude Code scopes to that subagent (settings.json would restrict everyone).
        if role[:shell_guard].present?
          frontmatter["hooks"] = { "PreToolUse" => [ { "matcher" => "Bash", "hooks" => [ { "type" => "command", "command" => "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/#{role[:shell_guard]}" } ] } ] }
        end

        # line_width: -1 keeps each scalar on one physical line (see AgentSkeletonSync#render).
        "#{YAML.dump(frontmatter, line_width: -1)}---\n\n#{body(slug, role)}\n"
      end

      def tools_for(role)
        builtins = if role[:code]
          READ_BUILTINS + CODE_BUILTINS
        elsif role[:shell]
          READ_BUILTINS + SHELL_BUILTINS
        else
          READ_BUILTINS
        end
        builtins + (BOOTSTRAP_ACTIONS + role[:verbs]).map { |action| "#{MCP_PREFIX}#{action}" } + (role[:server_grant] ? [ SERVER_GRANT ] : [])
      end

      def disallowed_tools_for(role)
        role[:server_grant] ? DENIED_ACTIONS.map { |action| "#{MCP_PREFIX}#{action}" } : []
      end

      # The final step's run_key shape is the contract .claude/hooks/subagent-report.sh
      # parses back out of the transcript (one platform row per run); keep the two in step.
      def body(slug, role)
        [
          AgentSkeletonSync::GENERATED_HEADER,
          "",
          "Thin loader for the Powernode platform agent `#{slug}`: its charter, policies, skills and tools live on " \
            "the platform and are loaded on demand, so this file never changes when they do. Load a deferred " \
            "`mcp__powernode__*` verb with ToolSearch (`select:<name>`) before its first call.",
          "",
          "1. Charter: call `#{MCP_PREFIX}get_agent` with `slug: \"#{slug}\"`, adopt the returned `system_prompt` " \
            "and keep its `id`. If the verb is unavailable or finds no agent, do not proceed under a generic " \
            "identity: it is not seeded on this connector, so tell the driver to run phase-1 step 5 or use a " \
            "general-purpose agent; run step 5 with `outcome: \"failed\"` and stop.",
          "2. Assemble: call `#{MCP_PREFIX}assemble_task` with the `assembly_id` from your prompt (none: your task, " \
            "`agent_slug: \"#{slug}\"`, `context: \"claude_code\"`); adopt the returned skills, learnings and verb lists.",
          "3. Tools: load only the verbs those skills name (or `discover_tools` returns); `describe_tool` each " \
            "before its first call. Never load the whole catalog.",
          "4. Work: the delegating prompt defines the task and what to return. #{role[:duty]} Hand anything " \
            "outside your charter back through `route_task`.",
          "5. Report: before returning, call `#{MCP_PREFIX}record_agent_execution` with `agent_slug: \"#{slug}\"`, " \
            "`model`, `outcome` (completed | failed | cancelled), `duration_ms`, `tokens` ({ input, output }), a " \
            "`task_digest` (at most 500 characters, no secrets), the `assembly_id` and " \
            "`run_key: \"<$CLAUDE_CODE_SESSION_ID>:#{slug}:<UTC start time as YYYYMMDDTHHMMSSZ>\"`. It is " \
            "idempotent on run_key."
        ].join("\n")
      end
    end
  end
end
