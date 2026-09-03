# frozen_string_literal: true

module Ai
  class ConciergeService
    INTENTS = %w[create_mission check_status analyze_repo approve_action question delegate_to_team code_review deploy general_chat provision_infrastructure adapt_project view_project].freeze
    CONFIRM_REQUIRED = %w[create_mission delegate_to_team code_review deploy provision_infrastructure].freeze

    # Operating posture injected into every concierge turn: the concierge is the user's
    # primary interface and is AWARE of the full platform capability surface, but its default
    # is to DELEGATE substantial/specialized work to the right executor rather than run
    # low-level tools itself — running tools directly only for simple, single-step tasks.
    #
    # THE EIGHT ACTION NAMES BELOW STAY LITERAL, DELIBERATELY (IMP-6fbbf47fcc3b).
    # Unlike the examples in #delegated_override, every one of them
    # (spawn_task, recruit_agent, execute_agent, execute_team, create_team,
    # campaign_propose, campaign_approve_proposal, campaign_delegate) resolves to
    # a CORE-hosted tool class that overrides neither `.permitted?` nor
    # `.extension_available?` / `.action_advertised?`, so
    # PlatformApiToolRegistry.advertised_action? answers true for all eight on
    # every deployment including core mode — deriving them could only ever
    # subtract a name that is always there, at the cost of a posture whose
    # delegation ladder reads differently per install.
    #
    # ADDING AN EXTENSION-HOSTED NAME HERE REINSTATES THE DEFECT, and this
    # posture is injected on EVERY turn, not just the delegated handoff. The
    # claim is therefore ratcheted, not merely asserted: see
    # spec/services/ai/concierge_service_spec.rb, "action names outside
    # #delegated_override", which resolves each name it finds and fails if the
    # class is extension-hosted or carries an advertisement gate.
    DELEGATION_POSTURE = <<~POSTURE.freeze
      OPERATING POSTURE — DELEGATE FIRST:
      You are the user's primary interface and are aware of the full platform capability
      surface (agents, teams, missions, campaigns, provisioning, devops, knowledge, code,
      governance, and more). Your DEFAULT is to delegate substantial or specialized work to
      the most capable executor rather than running low-level tools yourself:
      - Multi-step / specialized / long-running work → delegate to a platform AGENT
        (spawn_task, recruit_agent, execute_agent), a TEAM (execute_team / create_team), or a
        MISSION. For software improvement or feature work, route a CAMPAIGN (campaign_propose →
        campaign_approve_proposal → campaign_delegate) and hand the loop to a Claude Code session
        or a platform agent.
      - Run tools DIRECTLY only for simple, single-step tasks clearly faster done inline:
        status checks, lookups, listing, a single quick read/update, or answering a question.
      Choose the best specialist for the goal, then briefly tell the user what you delegated and
      to whom. Prefer delegation over doing complex work yourself.
    POSTURE

    # Provider types that support function/tool calling
    TOOL_CAPABLE_PROVIDERS = %w[openai anthropic].freeze

    # Selects the actions named as examples in #delegated_override out of the
    # live tool registry. See #advertised_actions.
    #
    # SUBSTRING, NOT A PREFIX, deliberately. `\Asystem_provision_` matches only
    # three registry keys (system_provision_instance, system_provision_ci_worker,
    # system_provision_docker_runtime) and all three are extension-backed, so on
    # a core-mode control plane — the exact deployment this derivation exists to
    # be honest about — every match disappears and the clause empties, while
    # provision_ci_worker and the platform_provisioning_* family ARE advertised
    # and runnable there. Anchoring on a naming convention that only part of the
    # registry follows reproduces the hardcoded-name defect one level up.
    PROVISIONING_ACTION_PATTERN = /provision/

    # THE REST OF THE SWEEP (IMP-6fbbf47fcc3b). The same block still named
    # system_list_package_repositories, system_list_nodes and
    # system_list_instances as literals. All three live in extensions/system, so
    # in core mode they are absent from tools/list and refused at tools/call by
    # McpPlatformToolRegistrar#unadvertised_refusal — the identical defect the
    # provisioning derivation above was written to remove.
    #
    # A MISS HERE OMITS AN EXAMPLE; IT NEVER INVENTS ONE. Each selector is
    # narrow on purpose: these render a "report the real data" example, so
    # widening (e.g. /node|instance/) would sweep create/delete actions into a
    # read-only illustration. If a control plane names its inventory actions
    # differently, the bullet drops — silence, not a false name.
    #
    # THE FLEET SELECTOR IS BROADER THAN "the NodeInstance fleet": on an
    # extension-complete control plane it also answers docker_list_nodes and
    # kubernetes_list_nodes, which list container/cluster nodes rather than the
    # fleet the surrounding prompt defines. Accepted, not overlooked — every
    # name it yields is one the registry is advertising at that moment, so the
    # example stays truthful; the cost is a slightly wider illustration, which
    # is the right trade against re-hardcoding a name to keep it tidy.
    PACKAGE_REPOSITORY_ACTION_PATTERN = /list_package_repositor/
    FLEET_INVENTORY_ACTION_PATTERN    = /list_(?:nodes|instances)\z/

    # Membership expressed as a selector so every name in the prompt reaches it
    # through one derivation path. discover_skills is core-hosted today, but
    # "core-hosted" is not "advertised" — the predicate, not the file location,
    # decides whether the prompt may name it.
    SKILL_DISCOVERY_ACTION_PATTERN = /\Adiscover_skills\z/

    def initialize(conversation:, user:)
      @conversation = conversation
      @agent = conversation.agent
      @user = user
      @account = user.account
    end

    # Primary entry point — routes to tool-bridge or legacy action-grammar.
    #
    # Wraps the original dispatch with ConciergeRouter (pre-LLM routing).
    # Three outcomes from the router:
    #
    #   :invoked     — A skill was already executed; result is stashed for
    #                  injection into the LLM's system prompt so the model
    #                  phrases a natural reply over the pre-computed data.
    #                  Agent stays as Powernode Assistant.
    #
    #   :delegated   — A specialist agent owns this query better than the
    #                  default. @agent is swapped for this turn only;
    #                  subsequent turns default back unless re-routed.
    #
    #   :passthrough — Router didn't fire; default chat flow runs as before.
    #
    # Router failures are caught and ignored — chat must never regress when
    # the router has a bad day.
    def process_message(content)
      apply_routing!(invoke_router(content))

      credential = find_credential

      if credential && tool_bridge_available?(credential)
        process_with_tools(content, credential)
      else
        process_with_action_grammar(content, credential)
      end
    rescue StandardError => e
      Rails.logger.error("[ConciergeService] Error: #{e.message}")
      @conversation.add_assistant_message(
        "I encountered an error processing your request. Please try again."
      )
    end

    private

    def invoke_router(content)
      return nil unless defined?(::Ai::ConciergeRouter) && @conversation && @user
      return nil if content.to_s.strip.empty?

      stub_message = Struct.new(:body).new(content.to_s)
      ::Ai::ConciergeRouter.route(conversation: @conversation, user_message: stub_message)
    rescue StandardError => e
      Rails.logger.warn("[ConciergeService] router error: #{e.class}: #{e.message}")
      nil
    end

    def apply_routing!(routing)
      return unless routing.respond_to?(:mode)

      case routing.mode
      when :invoked
        # Stash the invocation result; the system prompt builder appends
        # context_addendum so the LLM has the skill output as context
        # before generation. The LLM phrases the natural reply.
        @router_invocation = routing
        Rails.logger.info(
          "[ConciergeService] router :invoked skill=#{routing.skill_slug} for conv=#{@conversation.id}"
        )

        # When the router pre-invokes a skill whose result carries
        # requires_approval + a confirmation block, surface the confirmation
        # card directly here. The LLM-driven path (tool bridge auto-emit)
        # never fires for router-invoked skills because the LLM only
        # narrates the pre-injected result instead of calling the tool.
        emit_router_invoked_confirmation(routing.skill_data) if routing.respond_to?(:skill_data)
      when :delegated
        # Swap to the specialist agent for THIS turn. Conversation state
        # is unchanged — next turn defaults back to the original agent
        # unless re-routed by the next invocation. The @router_delegated
        # flag triggers an adjacent-injection handoff notice in the
        # messages array so the new agent doesn't inherit wrong-domain
        # interpretations from the prior agent's conversation history.
        if routing.delegated_agent.present?
          original = @agent&.name
          @agent = routing.delegated_agent
          @router_delegated = true
          Rails.logger.info(
            "[ConciergeService] router :delegated from=#{original.inspect} to=#{routing.delegated_agent.name.inspect} conv=#{@conversation.id}"
          )
        end
      when :passthrough
        # No-op
      end
    end

    # Mirrors ConciergeToolBridge#auto_emit_confirmation for the router
    # invocation path. The router runs the skill executor directly (no
    # LLM tool call), so the bridge never sees the result — without this
    # method, design-agent-team-from-intent and design-skill-from-intent
    # invocations via the router would yield narration but no clickable
    # confirmation card.
    def emit_router_invoked_confirmation(skill_data)
      return unless skill_data.is_a?(Hash)

      requires_approval = skill_data[:requires_approval] || skill_data["requires_approval"]
      return unless requires_approval

      data = skill_data[:data] || skill_data["data"] || {}
      confirmation = data.is_a?(Hash) ? (data[:confirmation] || data["confirmation"]) : nil
      confirmation ||= skill_data[:confirmation] || skill_data["confirmation"]
      return unless confirmation.is_a?(Hash)

      action_type = confirmation[:action_type] || confirmation["action_type"]
      action_description = confirmation[:action_description] || confirmation["action_description"]
      action_params = confirmation[:action_params] || confirmation["action_params"] || {}

      @conversation.add_assistant_message(
        action_description.to_s,
        content_metadata: {
          "concierge_action" => true,
          "action_type"      => action_type,
          "action_params"    => action_params,
          "actions" => [
            { "type" => "confirm", "label" => "Confirm", "style" => "primary" },
            { "type" => "modify",  "label" => "Modify",  "style" => "secondary" }
          ],
          "action_context" => {
            "type"        => "concierge_confirmation",
            "action_type" => action_type,
            "status"      => "pending",
            "mode"        => "router_invoked"
          }
        }
      )
      Rails.logger.info("[ConciergeService] router auto-emitted confirmation card action=#{action_type}")
    rescue StandardError => e
      Rails.logger.error("[ConciergeService] router confirmation emit failed: #{e.class}: #{e.message}")
    end

    public

    def handle_confirmed_action(action_type, params)
      resolve_pending_action(action_type)

      # Tool-bridge confirmations carry the _tool_name marker
      if params["_tool_name"].present?
        handle_tool_bridge_confirmation(params)
        return
      end

      case action_type
      when "create_mission"
        create_mission(params)
      when "delegate_to_team"
        delegate_to_team(params)
      when "code_review"
        trigger_code_review(params)
      when "deploy"
        trigger_deploy(params)
      when "resume_recipe_run"
        resume_recipe_run(params)
      when "create_recipe_skill"
        create_recipe_skill(params)
      when "create_team_from_spec"
        create_team_from_spec(params)
      when "approve_mission_gate"
        approve_mission_gate(params)
      when "approve_campaign_land"
        approve_campaign_land(params)
      when "reject_campaign_land"
        reject_campaign_land(params)
      else
        @conversation.add_assistant_message("Unknown action type: #{action_type}")
      end
    rescue StandardError => e
      Rails.logger.error("[ConciergeService] Confirmed action error: #{e.message}")
      @conversation.add_assistant_message("Failed to execute action: #{e.message}")
    end

    def post_mission_update(mission, event_type, data = {})
      return unless @conversation

      message = case event_type
      when "phase_changed"
        phase = data[:phase] || data["phase"]
        progress = data[:phase_progress] || data["phase_progress"]
        "Mission **#{mission.name}** entered **#{phase}** phase (#{progress}% complete)"
      when "approval_required"
        gate = data[:gate] || data["gate"]
        "Mission **#{mission.name}** is awaiting **#{gate&.humanize}** — review and approve to proceed"
      when "completed"
        "Mission **#{mission.name}** completed successfully! #{data[:summary] || ''}"
      when "failed"
        "Mission **#{mission.name}** failed: #{data[:error] || 'Unknown error'}"
      else
        return
      end

      @conversation.add_system_message(message, content_metadata: {
        "activity_type" => "mission_#{event_type}",
        "mission_id" => mission.id,
        "mission_name" => mission.name
      })
    end

    private

    # =========================================================================
    # Tool-bridge path (primary — for OpenAI/Anthropic providers)
    # =========================================================================

    # Detect explicit delegation intent: "ask Claude ...", "tell X ...", "have X do ..."
    DELEGATION_PATTERN = /\b(ask|tell|have|message|ping|notify)\s+(claude|the\s+assistant)/i

    def process_with_tools(content, credential = nil)
      llm_client = WorkerLlmClient.new(agent_id: @agent.id)
      tool_bridge = Ai::ConciergeToolBridge.new(
        agent: @agent, account: @account,
        conversation: @conversation, user: @user
      )

      messages = build_tool_messages(content)
      # Fallback chain: explicit agent model → credential's provider default →
      # re-fetched credential (in case caller passed nil). The `credential ||=`
      # guard handles the latter — previously this was `_credential` (unused
      # param) which silently broke when concierge_model returned nil
      # (e.g., for System Concierge whose @agent.model is unset).
      credential ||= find_credential
      model = concierge_model || credential&.provider&.default_model

      # When the user explicitly asks to delegate, force the model to call send_message
      # rather than letting it decide (gpt-4.1-mini often ignores tool-use instructions)
      opts = { temperature: 0.3, max_tokens: 4096, system_prompt: concierge_tool_system_prompt }
      if @conversation.workspace_conversation? && content.match?(DELEGATION_PATTERN)
        opts[:tool_choice] = { "type" => "function", "function" => { "name" => "send_message" } }
        Rails.logger.info("[ConciergeService] Delegation intent detected — forcing send_message tool_choice")
      end

      result = tool_bridge.execute_tool_loop(
        llm_client: llm_client, messages: messages, model: model,
        **opts
      )

      # When the concierge delegated via send_message, the tool call already
      # created a visible message in the conversation. Suppress the LLM's
      # final text to avoid a duplicate/redundant answer.
      # IMPORTANT: Only suppress if the send_message call actually succeeded —
      # a failed send_message means no message was persisted and we must fall
      # through to show the LLM's text response.
      delegated = result[:tool_calls_log]&.any? do |tc|
        tc[:tool] == "send_message" &&
          !tc[:result_preview].to_s.include?('"success":false') &&
          !tc[:result_preview].to_s.include?('"error"')
      end

      if delegated
        Rails.logger.info("[ConciergeService] Delegation detected via send_message (success) — suppressing final text response")
      elsif result[:content].present?
        # Surface non-truncated tool payloads (e.g. provisioning brief/plan)
        # into content_metadata.cards so the chat UI can render rich cards
        # inline. AgentToolBridge collects these via its CARD_TOOLS allowlist.
        cards = result[:chat_cards].presence
        content_metadata = cards ? { cards: cards } : {}

        @conversation.add_assistant_message(
          result[:content],
          content_metadata: content_metadata,
          processing_metadata: {
            mode: "tool_bridge",
            tool_calls: result[:tool_calls_log].presence,
            usage: result[:usage]
          }.compact
        )
      end
    rescue StandardError => e
      Rails.logger.warn("[ConciergeService] Tool bridge failed, falling back: #{e.message}")
      process_with_action_grammar(content, find_credential)
    end

    def tool_bridge_available?(credential)
      return false unless @agent&.persisted?
      return false unless credential&.provider

      TOOL_CAPABLE_PROVIDERS.include?(credential.provider.provider_type)
    end

    def build_tool_messages(user_content)
      messages = []

      @conversation.messages.not_deleted.ordered.last(15).each do |msg|
        messages << { role: msg.role, content: msg.content }
      end

      # Router-invoked skill result, injected as a synthetic system message
      # IMMEDIATELY BEFORE the user's latest message. This positioning is
      # deliberate (R5 fix 2026-05-12): when the addendum lived inside the
      # global system prompt, ~10 turns of accumulated "couldn't find"
      # context in conversation history would outweigh the directive. Placing
      # it adjacent to the user message means the LLM sees the override
      # right next to the question — recency bias works *for* us instead
      # of against us.
      messages << router_override_message if router_override_message

      messages << { role: "user", content: user_content }
      messages
    end

    def concierge_tool_system_prompt
      parts = []

      # Static prompt from the agent's DB record (editable via API/UI)
      # Pass workspace context to filter skills (only workspace-tagged skills in workspace mode)
      ctx = @conversation.workspace_conversation? ? :workspace : nil
      base_prompt = @agent&.build_system_prompt_with_profile(context: ctx).presence
      parts << base_prompt if base_prompt

      # Delegation-first operating posture (applies every turn, regardless of the agent's
      # DB prompt) — the concierge prefers delegating to agents/teams/missions/campaigns.
      parts << DELEGATION_POSTURE

      # Dynamic runtime context (live data: missions, repos, teams, workspace members)
      context_section = build_context_section
      parts << context_section

      # NOTE: router invocation result is NOT injected here. It's placed
      # adjacent to the user message via build_tool_messages /
      # build_legacy_messages instead — adjacent injection avoids the
      # recency-bias problem where ~10 turns of "couldn't find" history
      # outweigh a directive buried in the global system prompt.

      assembled = parts.join("\n\n")

      # Diagnostic logging — helps verify skill injection and workspace context
      has_skill_prompts = assembled.include?("MANDATORY RULE") || assembled.include?("HOW TO DELEGATE")
      has_workspace_context = assembled.include?("CURRENT WORKSPACE:")
      has_delegation_block = assembled.include?("TO SEND A MESSAGE TO AN AGENT")
      Rails.logger.info(
        "[ConciergeService] System prompt assembled: " \
        "length=#{assembled.length} " \
        "has_base_prompt=#{base_prompt.present?} " \
        "base_prompt_length=#{base_prompt&.length || 0} " \
        "has_skill_prompts=#{has_skill_prompts} " \
        "has_delegation_block=#{has_delegation_block} " \
        "has_workspace_context=#{has_workspace_context}"
      )

      assembled
    end

    # =========================================================================
    # Action-grammar path (fallback — for Ollama and non-tool providers)
    # =========================================================================

    def process_with_action_grammar(content, credential = nil)
      response_text = call_concierge_legacy(content, credential)
      action, body = parse_action(response_text)

      case action
      when :confirm
        handle_confirm(body)
      when :action
        execute_action(body)
      else
        handle_respond(body)
      end
    end

    def call_concierge_legacy(content, credential = nil)
      credential ||= find_credential
      unless credential
        return "[RESPOND] I'm unable to process your request right now — no AI provider is configured."
      end

      client = WorkerLlmClient.new(agent_id: @agent.id)
      messages = build_legacy_messages(content)
      model = concierge_model || credential.provider.default_model

      response = client.complete(messages: messages, model: model, max_tokens: 2048, temperature: 0.3)

      if response.success?
        response.content
      else
        Rails.logger.warn("[ConciergeService] LLM call failed: #{response.raw_response&.dig(:error)}")
        "[RESPOND] I'm having trouble processing your request right now. Please try again."
      end
    end

    def build_legacy_messages(user_content)
      messages = []
      messages << { role: "system", content: legacy_system_prompt }

      @conversation.messages.not_deleted.ordered.last(10).each do |msg|
        messages << { role: msg.role, content: msg.content }
      end

      # Router-invoked skill result — same adjacent-injection pattern as
      # build_tool_messages. See R5 fix note there.
      messages << router_override_message if router_override_message

      messages << { role: "user", content: user_content }
      messages
    end

    # Synthetic system message carrying the router's invocation addendum
    # (for :invoked mode) OR a delegation-handoff notice (for :delegated mode).
    # In both cases it sits adjacent to the user message so the LLM sees the
    # override at the top of its working memory rather than buried under
    # accumulated conversation history that may have established a wrong
    # pattern (e.g., 10+ "couldn't find" responses).
    def router_override_message
      return invoked_override if @router_invocation&.context_addendum.present?
      return delegated_override if @router_delegated

      nil
    end

    def invoked_override
      {
        role: "system",
        content: <<~OVERRIDE.strip
          IMPORTANT — IGNORE PRIOR CONVERSATION PATTERN FOR THIS QUERY.
          Earlier responses in this conversation may have said "no records
          found" or "couldn't find in knowledge base." Those answers were
          incorrect for the question now being asked. The platform tool
          has been invoked directly for the user's latest message and the
          authoritative result is below. Use ONLY this data when answering;
          do not invoke search_knowledge or fall back to general training
          data for this specific question.

          #{@router_invocation.context_addendum}
        OVERRIDE
      }
    end

    # THE ONE PLACE #delegated_override MAY LEARN AN ACTION NAME
    # (IMP-128fe17fd8c8, generalised by IMP-6fbbf47fcc3b). Every example in that
    # prompt names actions selected from the registry that answers tools/list,
    # never a literal, because an action the platform does not advertise is also
    # refused at tools/call — so steering the model at one is the same
    # "dishonest catalog" failure the advertisement predicate exists to prevent,
    # arriving through the system prompt instead of the catalog.
    #
    # `agent: nil` is deliberate and is the AVAILABILITY question ("is the
    # backing extension loaded?"), matching the account-wide advertisement
    # surfaces: BaseTool.permitted? short-circuits before any permission lookup
    # when no agent is given, so this neither consults nor leaks @agent's
    # grants. The names are only examples in a prompt; what the model may
    # actually run is still gated at invocation.
    #
    # Empty is a legitimate answer (nothing of that kind is available here), and
    # every caller must render nothing rather than an empty list.
    def advertised_actions(pattern)
      advertised_action_names.grep(pattern).sort
    end

    # Memoised for the life of the service: #delegated_override asks four
    # selectors and .available_tools constantizes the whole registry on every
    # call. A nil registry answer is NOT cached as [] — the rescue returns a
    # fresh empty list so a transient failure cannot pin the prompt empty for
    # the rest of the request.
    def advertised_action_names
      @advertised_action_names ||= ::Ai::Tools::PlatformApiToolRegistry.available_tools.keys
    rescue StandardError => e
      Rails.logger.warn "[ConciergeService] Could not resolve advertised actions: #{e.message}"
      []
    end

    # The provisioning example used to name `system_provision_docker_runtime`
    # literally — core-hosted but extension-BACKED, so de-advertised in core
    # mode (IMP-128fe17fd8c8).
    def advertised_provisioning_actions
      advertised_actions(PROVISIONING_ACTION_PATTERN)
    end

    def advertised_provisioning_clause
      actions = advertised_provisioning_actions
      return "" if actions.empty?

      " (offered on this control plane right now: #{actions.join(', ')})"
    end

    # The "Examples of CORRECT behavior" bullets. Each example that names an
    # action is emitted only when the registry answered its selector; the
    # provisioning bullet always renders because its instruction ("call the
    # matching provisioning action") stands on its own and only the parenthetical
    # list is derived.
    def tool_invocation_examples
      bullets = []

      if (repos = advertised_actions(PACKAGE_REPOSITORY_ACTION_PATTERN)).any?
        bullets << <<~BULLET.strip
          * "How many package repos?" → call #{repos.join(' / ')}, then
            report the actual count. NOT generic CLI advice.
        BULLET
      end

      bullets << <<~BULLET.strip
        * "Provision a runtime" → call request_confirmation with
          the provision plan, then on confirm call the matching
          provisioning action#{advertised_provisioning_clause}.
          NOT generic "install it via apt" instructions.
      BULLET

      if (fleet = advertised_actions(FLEET_INVENTORY_ACTION_PATTERN)).any?
        bullets << <<~BULLET.strip
          * "How is my fleet?" → call #{fleet.join(' / ')},
            report real data. NOT "you should check your dashboard."
        BULLET
      end

      bullets.map { |bullet| bullet.gsub(/^/, "  ") }.join("\n")
    end

    # Naming the discovery action is itself a claim that it is offered here.
    def skill_discovery_clause
      actions = advertised_actions(SKILL_DISCOVERY_ACTION_PATTERN)
      return "" if actions.empty?

      <<~CLAUSE.strip
        If you don't recognize the appropriate tool, call #{actions.join(' / ')}
        first to find it, then invoke. DO NOT fall back to general
        training-data instructions when a platform tool exists for the
        query.
      CLAUSE
    end

    def delegated_override
      {
        role: "system",
        content: <<~OVERRIDE.strip
          IMPORTANT — AGENT HANDOFF FOR THIS QUERY.
          You are now responding as **#{@agent.name}** for this user message.
          Earlier responses in this conversation came from a DIFFERENT agent
          (Powernode Assistant, a general-purpose chat agent) and may have
          interpreted platform-specific terminology incorrectly. For
          example, "NodeModule" in this platform refers to
          `System::NodeModule` — a Powernode unit of installable software
          assigned to nodes — NOT a Node.js npm module. Similarly:
            * "fleet" = the network of managed NodeInstances (NOT AI agents)
            * "module" = NodeModule (NOT Node.js / Python module)
            * "instance" = NodeInstance (NOT AWS EC2 instance — though it
              may be backed by one)
            * "package" = a row in system_packages from a synced apt/rpm repo
            * "repository" = a row in system_package_repositories (apt/rpm
              source), NOT a Git repo

          === MANDATORY: INVOKE TOOLS, DO NOT DESCRIBE ===
          You have direct access to the platform tools this control plane
          advertises. For ANY query that asks about platform state
          ("how many...", "what's configured...", "show me...", "list...")
          or that requests a platform action ("provision...", "create...",
          "deploy..."), you MUST call the appropriate tool DIRECTLY rather
          than describing what tool you would call or providing generic
          install instructions.

          Examples of CORRECT behavior:
          #{tool_invocation_examples}

          #{skill_discovery_clause}

          Treat the latest user message as a fresh query in your domain.
          Do NOT defer to prior responses in this conversation.
        OVERRIDE
          .gsub(/\n{3,}/, "\n\n")
      }
    end

    def legacy_system_prompt
      parts = []

      # Static prompt from the agent's DB record (editable via API/UI)
      ctx = @conversation.workspace_conversation? ? :workspace : nil
      base_prompt = @agent&.build_system_prompt_with_profile(context: ctx).presence
      parts << base_prompt if base_prompt

      # Delegation-first operating posture (applies every turn, regardless of the agent's
      # DB prompt) — the concierge prefers delegating to agents/teams/missions/campaigns.
      parts << DELEGATION_POSTURE

      # Dynamic runtime context (live data: missions, repos, teams, workspace members)
      parts << build_context_section

      # Router invocation result is injected adjacent to the user message
      # in build_legacy_messages, not here. See router_override_message.

      # Action-grammar markers — tightly coupled to parse_action, must stay in code
      parts << <<~INSTRUCTIONS
        Based on the user's message, respond with ONE of these markers:

        [RESPOND] message — Reply directly when you can answer without taking action.
        [ACTION:check_status] — Query and report on active missions, teams, or executions.
        [ACTION:analyze_repo] repo_name — Trigger repository analysis.
        [ACTION:approve_action] gate_info — Handle an approval gate response.
        [ACTION:question] — Answer a question using your knowledge.
        [CONFIRM:create_mission] {"name": "...", "repository": "...", "objective": "...", "mission_type": "development"} — Propose creating a mission (requires user confirmation).
        [CONFIRM:delegate_to_team] {"team": "...", "objective": "..."} — Propose delegating to a team (requires user confirmation).
        [CONFIRM:code_review] {"repository": "...", "branch": "..."} — Propose a code review (requires user confirmation).
        [CONFIRM:deploy] {"mission_id": "..."} — Propose deployment (requires user confirmation).

        Always start your response with exactly one marker. For CONFIRM actions, include a human-readable description after the JSON.
      INSTRUCTIONS

      parts.join("\n\n")
    end

    # =========================================================================
    # Shared context builder (used by both paths)
    # =========================================================================

    def build_context_section
      parts = []

      # Active missions
      active_missions = @account.ai_missions.in_progress.limit(5)
      if active_missions.any?
        mission_lines = active_missions.map { |m| "- #{m.name} (#{m.mission_type}, phase: #{m.current_phase}, #{m.phase_progress}% complete)" }
        parts << "ACTIVE MISSIONS:\n#{mission_lines.join("\n")}"
      else
        parts << "ACTIVE MISSIONS: None currently active"
      end

      # Available repos
      repos = Devops::GitRepository.where(account_id: @account.id).limit(10)
      if repos.any?
        repo_lines = repos.map { |r| "- #{r.full_name}" }
        parts << "AVAILABLE REPOSITORIES:\n#{repo_lines.join("\n")}"
      end

      # Available teams
      teams = @account.ai_agent_teams.active.limit(10)
      if teams.any?
        team_lines = teams.map { |t| "- #{t.name} (#{t.team_type})" }
        parts << "AVAILABLE TEAMS:\n#{team_lines.join("\n")}"
      end

      # Available agents (exclude the concierge itself)
      agents = @account.ai_agents.active.where.not(id: @agent&.id).limit(10)
      if agents.any?
        agent_lines = agents.map { |a| "- #{a.name} (#{a.agent_type})" }
        parts << "AVAILABLE AGENTS:\n#{agent_lines.join("\n")}"
      end

      # Workspace context (when in a workspace conversation)
      # Behavioral instructions come from the Powernode Concierge skill (injected via
      # build_system_prompt_with_profile). This section provides runtime data only.
      if @conversation.workspace_conversation? && @conversation.agent_team
        team = @conversation.agent_team
        workspace_lines = []
        workspace_lines << "CURRENT WORKSPACE: \"#{team.name}\" (conversation_id: #{@conversation.conversation_id})"

        # Unified WORKSPACE MEMBERS header — all participants under one section
        member_lines = []

        # Human participants
        human_users = [@conversation.user].compact
        if @conversation.is_collaborative? && @conversation.participants.any?
          human_users += User.where(id: @conversation.participants).where.not(id: human_users.map(&:id)).to_a
        end
        human_users.each { |u| member_lines << "- #{u.full_name} (human)" }

        # Agent members (type label helps the LLM understand capabilities)
        members = team.members.includes(:agent).where.not(ai_agent_id: @agent&.id)
        members.each do |m|
          next unless m.agent
          type_label = m.agent.agent_type == "mcp_client" ? "mcp_client" : "server"
          member_lines << "- #{m.agent.name} (#{type_label}, role: #{m.role})"
        end

        workspace_lines << "WORKSPACE MEMBERS:\n#{member_lines.join("\n")}" if member_lines.any?

        # Delegation instructions — immediately after member list (proximity principle)
        if members.any?
          mcp_agent = members.find { |m| m.agent&.agent_type == "mcp_client" }&.agent
          example_agent = mcp_agent || members.first&.agent
          workspace_lines << <<~DELEGATION.strip
            TO SEND A MESSAGE TO AN AGENT, call the send_message tool with:
              message: "@#{example_agent&.name} <your request>"
            The conversation_id is auto-filled — do NOT provide it.
            #{mcp_agent ? "\"Claude\" or \"Claude Code\" = @#{mcp_agent.name}" : ""}
            You HAVE access to all agents above via send_message. NEVER say you cannot communicate with them.
          DELEGATION
        end

        parts << workspace_lines.join("\n\n")
        Rails.logger.info("[ConciergeService] Workspace context included: team=#{team.name} humans=#{human_users.size} agents=#{members.size}")
      else
        is_workspace = @conversation.workspace_conversation?
        has_team = @conversation.agent_team.present?
        Rails.logger.info("[ConciergeService] Workspace context skipped: workspace_conversation=#{is_workspace} has_agent_team=#{has_team}")
      end

      parts.join("\n\n")
    end

    # =========================================================================
    # Tool-bridge confirmation handler
    # =========================================================================

    def handle_tool_bridge_confirmation(params)
      tool_name = params.delete("_tool_name")
      tool_bridge = Ai::AgentToolBridgeService.new(agent: @agent, account: @account)

      result_json = tool_bridge.dispatch_tool_call(name: tool_name, arguments: params)
      result = JSON.parse(result_json)

      if result["error"]
        @conversation.add_assistant_message("Action failed: #{result['message'] || result['error']}")
      else
        @conversation.add_assistant_message("Done! #{summarize_tool_result(tool_name, result)}")
      end
    rescue JSON::ParserError
      @conversation.add_assistant_message("Action completed.")
    end

    # Route an operator's inline approval/rejection of a mission gate
    # (rendered as an actionable card on infrastructure-mission approval
    # gates) through the canonical approval engine. Reuses
    # OrchestratorService#handle_approval! rather than duplicating gate
    # bookkeeping — that method records the Ai::MissionApproval, honors the
    # second-signature gate, and advances (or rolls back) the mission.
    def approve_mission_gate(params)
      mission_id = params["mission_id"] || params[:mission_id]
      mission = @account.ai_missions.find_by(id: mission_id)
      unless mission
        @conversation.add_assistant_message("I couldn't find that mission to approve.")
        return
      end

      gate = (params["gate"] || params[:gate] || mission.current_phase).to_s
      decision = (params["decision"] || params[:decision] || "approved").to_s
      comment = params["comment"] || params[:comment]

      # An Approve card can be confirmed stale — a duplicate click, a second
      # operator, or a replayed conversation after the mission has moved on.
      # Unguarded, handle_approval! would record the decision against whatever
      # phase the mission is at NOW and advance (or roll back) it — a phase
      # skip on live infrastructure. Mirror the guard the gateway path already
      # has (Ai::Mission#on_approval_decision): the mission must be sitting at
      # an approval gate, and the card's gate must be the gate it is sitting at.
      unless mission.awaiting_approval?
        @conversation.add_assistant_message(
          "⚠️ **#{mission.name}** isn't awaiting approval (currently at " \
          "**#{mission.current_phase&.humanize}**) — this card looks stale, so I didn't apply it."
        )
        return
      end

      current_gate = ::Ai::MissionApproval.gate_for_phase(mission.current_phase, mission: mission)
      if ::Ai::MissionApproval.gate_for_phase(gate, mission: mission) != current_gate
        @conversation.add_assistant_message(
          "⚠️ **#{mission.name}** is awaiting approval at **#{mission.current_phase&.humanize}**, " \
          "not **#{gate.humanize}** — this card looks stale, so I didn't apply it."
        )
        return
      end

      ::Ai::Missions::OrchestratorService.new(mission: mission).handle_approval!(
        gate: gate, user: @user, decision: decision, comment: comment
      )

      mission.reload
      if decision == "approved"
        @conversation.add_assistant_message(
          "✅ Approved **#{gate.humanize}** for **#{mission.name}** — now in **#{mission.current_phase&.humanize}**."
        )
      else
        @conversation.add_assistant_message(
          "↩️ Sent **#{mission.name}** back from **#{gate.humanize}** for revision."
        )
      end
    end

    def approve_campaign_land(params)
      land = find_campaign_land(params)
      return unless land

      land.operator_approve!(user: @user)
      @conversation.add_assistant_message(
        "✅ Approved land for `#{land.source_branch}` → `#{land.target_branch}` — queued (#{land.reload.status})."
      )
    end

    def reject_campaign_land(params)
      land = find_campaign_land(params)
      return unless land

      land.operator_reject!(user: @user, reason: params["reason"] || params[:reason])
      @conversation.add_assistant_message(
        "↩️ Rejected land for `#{land.source_branch}` → `#{land.target_branch}`."
      )
    end

    def find_campaign_land(params)
      id = params["campaign_land_id"] || params[:campaign_land_id] || params["land_id"] || params[:land_id]
      land = ::Ai::CampaignLand.where(account: @account).find_by(id: id)
      @conversation.add_assistant_message("I couldn't find that campaign land to act on.") unless land
      land
    end

    def summarize_tool_result(tool_name, result)
      # Provide a human-friendly summary based on the tool type
      case tool_name
      when /^execute_/
        result["status"] ? "Status: #{result['status']}" : "Execution started."
      when /^create_/
        id = result["id"] || result["data"]&.dig("id")
        id ? "Created successfully (ID: #{id})" : "Created successfully."
      when /^trigger_/
        "Pipeline triggered."
      when "dispatch_to_runner"
        "Job dispatched to runner."
      else
        "Completed successfully."
      end
    end

    # =========================================================================
    # Legacy action handlers (used by action-grammar path)
    # =========================================================================

    def parse_action(response_text)
      text = response_text.to_s.strip

      if text.match?(/^\[CONFIRM:(\w+)\]/)
        match = text.match(/^\[CONFIRM:(\w+)\]\s*(.*)$/m)
        intent = match[1]
        body = match[2].strip

        # Try to extract JSON params
        json_match = body.match(/\{[^}]+\}/m)
        params = json_match ? (JSON.parse(json_match[0]) rescue {}) : {}
        description = body.sub(/\{[^}]*\}/m, "").strip
        description = body if description.blank?

        [:confirm, { intent: intent, params: params, description: description }]
      elsif text.match?(/^\[ACTION:(\w+)\]/)
        match = text.match(/^\[ACTION:(\w+)\]\s*(.*)$/m)
        intent = match[1]
        body = match[2].strip
        [:action, { intent: intent, body: body }]
      elsif text.start_with?("[RESPOND]")
        [:respond, text.sub("[RESPOND]", "").strip]
      else
        [:respond, text]
      end
    end

    def handle_respond(message)
      @conversation.add_assistant_message(message)
    end

    def handle_confirm(data)
      intent = data[:intent]
      params = data[:params]
      description = data[:description]

      @conversation.add_assistant_message(
        description.presence || "I'd like to #{intent.humanize.downcase}. Shall I proceed?",
        content_metadata: {
          "concierge_action" => true,
          "action_type" => intent,
          "action_params" => params,
          "actions" => [
            { "type" => "confirm", "label" => "Confirm", "style" => "primary" },
            { "type" => "modify", "label" => "Modify", "style" => "secondary" }
          ],
          "action_context" => {
            "type" => "concierge_confirmation",
            "action_type" => intent,
            "status" => "pending"
          }
        }
      )
    end

    def execute_action(data)
      case data[:intent]
      when "check_status"
        check_status
      when "analyze_repo"
        analyze_repo(data[:body])
      when "approve_action"
        handle_approval(data[:body])
      when "question"
        @conversation.add_assistant_message(data[:body])
      else
        @conversation.add_assistant_message(data[:body].presence || "Action completed.")
      end
    end

    def check_status
      missions = @account.ai_missions.in_progress.order(updated_at: :desc).limit(10)

      if missions.empty?
        @conversation.add_assistant_message("No active missions right now. Would you like to create one?")
        return
      end

      lines = missions.map do |m|
        status_emoji = m.awaiting_approval? ? "⏳" : "🔄"
        "#{status_emoji} **#{m.name}** — #{m.current_phase&.humanize} (#{m.phase_progress}%)"
      end

      summary = "Here are your active missions:\n\n#{lines.join("\n")}"
      @conversation.add_assistant_message(summary)
    end

    def analyze_repo(repo_identifier)
      repo = find_repository(repo_identifier)
      unless repo
        @conversation.add_assistant_message("I couldn't find a repository matching \"#{repo_identifier}\". Available repositories: #{available_repo_names.join(', ')}")
        return
      end

      mission = @account.ai_missions.create!(
        name: "Analysis: #{repo.full_name}",
        mission_type: "research",
        status: "draft",
        repository: repo,
        objective: "Analyze repository structure and capabilities",
        created_by: @user
      )

      service = Ai::Missions::RepoAnalysisService.new(mission: mission)
      result = service.analyze!

      analysis_text = format_analysis_result(result, repo)
      @conversation.add_assistant_message(analysis_text)

      mission.update!(status: "completed", completed_at: Time.current)
    rescue StandardError => e
      @conversation.add_assistant_message("Repository analysis failed: #{e.message}")
    end

    def create_mission(params)
      repo = find_repository(params["repository"])
      unless repo
        @conversation.add_assistant_message("Repository \"#{params['repository']}\" not found.")
        return
      end

      mission = @account.ai_missions.create!(
        name: params["name"] || "Mission: #{params['objective']&.truncate(50)}",
        mission_type: params["mission_type"] || "development",
        repository: repo,
        objective: params["objective"],
        description: params["description"],
        created_by: @user,
        conversation: @conversation
      )

      orchestrator = Ai::Missions::OrchestratorService.new(mission: mission)
      orchestrator.start!

      @conversation.add_system_message(
        "Mission **#{mission.name}** created and started! Currently in **#{mission.current_phase}** phase.",
        content_metadata: {
          "activity_type" => "mission_phase_changed",
          "mission_id" => mission.id,
          "mission_name" => mission.name
        }
      )
    end

    def delegate_to_team(params)
      team = @account.ai_agent_teams.active.find_by(name: params["team"])
      unless team
        @conversation.add_assistant_message("Team \"#{params['team']}\" not found or inactive.")
        return
      end

      @conversation.add_system_message("Delegating to team **#{team.name}**: #{params['objective']}")

      WorkerJobService.enqueue_ai_team_execution(
        team_id: team.id,
        user_id: @user.id,
        input: { task: params["objective"] },
        context: { conversation_id: @conversation.id, source: "concierge" }
      )
    end

    def trigger_code_review(params)
      @conversation.add_assistant_message(
        "Code review requested for **#{params['repository']}** (branch: #{params['branch'] || 'default'}). " \
        "This will be routed through the Code Factory review pipeline."
      )
    end

    # M3 — operator approved a paused require_approval step in a recipe run.
    # Resumes the run from the paused step; the runner continues until the
    # next pause point, completion, or failure.
    def resume_recipe_run(params)
      run_id = params["run_id"] || params[:run_id]
      run = ::Ai::SkillRecipeRun.find_by(id: run_id, account: @account)
      unless run
        @conversation.add_assistant_message("Recipe run #{run_id.inspect} not found.")
        return
      end
      unless run.paused?
        @conversation.add_assistant_message(
          "Recipe run #{run_id} is not paused (status=#{run.status}); nothing to resume."
        )
        return
      end

      # Switch the run back to running so the runner knows the pending
      # step was approved (see SkillRecipeRunner#approval_already_granted_for?).
      run.update!(status: "running")
      resumed = ::Ai::SkillRecipeRunner.resume(run: run)

      summary = if resumed.successful?
                  "Recipe **#{run.skill.name}** completed successfully. Final outputs:\n```json\n#{JSON.pretty_generate(resumed.outputs)}\n```"
                elsif resumed.paused?
                  "Recipe **#{run.skill.name}** is paused at the next approval-gated step (#{resumed.pending_step_id}). Confirm again to continue."
                elsif resumed.failed?
                  "Recipe **#{run.skill.name}** failed at step #{resumed.failed_step_id}: #{resumed.error_message}"
                else
                  "Recipe run finished in unexpected state: #{resumed.status}"
                end
      @conversation.add_assistant_message(summary)
    end

    # M4 prep — operator approved the design of a new recipe skill. Persists
    # the Ai::Skill row with metadata.recipe populated, optionally binding
    # to an agent. Called from the create_recipe_skill confirmation flow
    # emitted by DesignSkillFromIntentExecutor.
    def create_recipe_skill(params)
      slug = params["slug"] || params[:slug]
      if slug.blank? || params["recipe"].blank?
        @conversation.add_assistant_message("Cannot create recipe skill: missing slug or recipe payload.")
        return
      end

      skill = ::Ai::Skill.find_or_initialize_by(slug: slug)
      skill.assign_attributes(
        account:     @account,
        name:        params["name"] || slug.titleize,
        description: params["description"] || "Custom recipe skill",
        category:    params["category"] || "skill_management",
        status:      "active",
        is_enabled:  true,
        is_system:   false,
        version:     "1.0.0",
        tags:        Array(params["tags"]).presence || %w[custom recipe operator-defined],
        metadata: {
          "author"          => "operator",
          "icon"            => "recipe",
          "domain"          => "custom",
          "invocation_mode" => "one_shot",
          "recipe"          => params["recipe"]
        }
      )
      skill.save!

      # Bind to the calling agent so it's immediately discoverable to the
      # operator's chat surface. Operator can rebind elsewhere via the
      # skills admin UI.
      if @agent&.persisted?
        ::Ai::AgentSkill.find_or_create_by!(ai_agent_id: @agent.id, ai_skill_id: skill.id) do |bind|
          bind.priority = 500
          bind.is_active = true
        end
      end

      @conversation.add_assistant_message(
        "Recipe skill **#{skill.name}** (`#{skill.slug}`) created and bound. " \
        "It's now discoverable via `discover_skills` and routable by the ConciergeRouter."
      )
    end

    # T3 — operator approved a team spec produced by
    # DesignAgentTeamFromIntentExecutor. Creates any approved new agents
    # (per-role allow-list via approved_new_agent_roles, defaulting to all),
    # then persists Ai::AgentTeam + member rows. Drops members whose backing
    # agent could not be resolved; fails the whole creation if a `required`
    # member is unresolvable.
    #
    # Map between executor vocabulary and AgentTeam columns:
    #   executor "coordination_strategy" → AgentTeam#team_type
    #   AgentTeam#coordination_strategy   ← derived (manager_led for hierarchical/sequential,
    #                                                priority_based for parallel,
    #                                                consensus for mesh).
    TEAM_TYPE_MAP = {
      "hierarchical" => { team_type: "hierarchical", coordination_strategy: "manager_led" },
      "sequential"   => { team_type: "sequential",   coordination_strategy: "manager_led" },
      "parallel"     => { team_type: "parallel",     coordination_strategy: "priority_based" },
      "mesh"         => { team_type: "mesh",         coordination_strategy: "consensus" }
    }.freeze

    def create_team_from_spec(params)
      name = params["name"] || params[:name]
      members = Array(params["members"] || params[:members])
      strategy_in = (params["coordination_strategy"] || params[:coordination_strategy]).to_s

      if name.blank? || members.empty? || !TEAM_TYPE_MAP.key?(strategy_in)
        @conversation.add_assistant_message(
          "Cannot create team: missing name, members, or unrecognized coordination_strategy `#{strategy_in}`."
        )
        return
      end

      # Three states distinguished here:
      #   absent (nil)   → default to allow-all (operator clicked plain "Confirm")
      #   array provided → only those roles approved, even if empty
      raw_allow = params.key?("approved_new_agent_roles") ? params["approved_new_agent_roles"]
                                                          : params[:approved_new_agent_roles]
      allow_all_new = raw_allow.nil?
      approved_new_roles = Array(raw_allow)
      new_specs_by_role = Array(params["new_agents_to_create"]).index_by { |e| e["role"] }

      created_agents = {}
      skipped_unapproved = []
      ActiveRecord::Base.transaction do
        new_specs_by_role.each do |role, entry|
          next unless allow_all_new || approved_new_roles.include?(role)

          agent = create_agent_from_spec(entry["agent_spec"] || entry[:agent_spec], role)
          created_agents[role] = agent if agent
        end

        members.each_with_index do |m, i|
          # Skip members whose new agent wasn't approved
          if m["agent_spec"].present? && !created_agents.key?(m["role"])
            if m["required"]
              raise ActiveRecord::Rollback, "Required member `#{m['role']}` could not be resolved"
            end
            skipped_unapproved << m["role"]
            next
          end
        end

        mapping = TEAM_TYPE_MAP.fetch(strategy_in)
        team = @account.ai_agent_teams.create!(
          name: unique_team_name(name),
          description: params["description"] || "Team composed via DesignAgentTeamFromIntentExecutor",
          team_type: mapping[:team_type],
          coordination_strategy: mapping[:coordination_strategy],
          status: "active",
          team_config: {
            "designed_by_skill" => "design-agent-team-from-intent",
            "designed_at"       => Time.current.iso8601,
            "output_template"   => params["output_template"] || {},
            "skipped_members"   => skipped_unapproved
          }
        )

        # Designate exactly one lead for manager_led teams: the resolvable
        # member with the lowest priority. Setting is_lead on more than one
        # member trips AgentTeamMember's uniqueness validation.
        resolvable_members = members.reject { |m| m["agent_spec"].present? && !created_agents.key?(m["role"]) }
        lead_role = if mapping[:coordination_strategy] == "manager_led"
                      resolvable_members.min_by { |m| (m["priority"] || 100).to_i }&.dig("role")
                    end

        resolvable_members.each do |m|
          agent = if m["agent_slug"].present?
                    @account.ai_agents.find_by(slug: m["agent_slug"])
                  else
                    created_agents[m["role"]]
                  end
          next if agent.blank?

          ::Ai::AgentTeamMember.create!(
            ai_agent_team_id: team.id,
            ai_agent_id:      agent.id,
            role:             m["role"],
            priority_order:   (m["priority"] || 100).to_i,
            is_lead:          m["role"] == lead_role,
            recruited_at:     Time.current
          )

          # Mirror as Ai::TeamRole so the existing role-based UI surfaces
          # this composition. The role_name is account-scoped-unique in
          # the model — disambiguate per-team via "team_id:role" prefix.
          ::Ai::TeamRole.create!(
            account_id:    @account.id,
            agent_team_id: team.id,
            ai_agent_id:   agent.id,
            role_name:     unique_team_role_name(team, m["role"]),
            role_type:     m["role"] == lead_role ? "manager" : "worker",
            role_description: m["role"],
            capabilities:  Array(m["capabilities"]),
            priority_order: (m["priority"] || 100).to_i,
            max_concurrent_tasks: 1
          )
        end

        @created_team = team
      end

      if @created_team
        skip_note = skipped_unapproved.any? ? " Skipped (unapproved new agents): #{skipped_unapproved.join(', ')}." : ""
        new_note  = created_agents.any? ? " Created #{created_agents.size} new agent(s): #{created_agents.keys.join(', ')}." : ""
        @conversation.add_assistant_message(
          "Team **#{@created_team.name}** created with #{@created_team.members.count} member(s).#{new_note}#{skip_note}"
        )
      else
        @conversation.add_assistant_message("Team creation rolled back: required member could not be resolved.")
      end
    end

    def create_agent_from_spec(agent_spec, role)
      return nil if agent_spec.blank?

      agent_type = valid_agent_type(agent_spec["agent_type"])
      recommendation = ::Ai::AgentModelSelector.recommend(
        account:      @account,
        agent_type:   agent_type,
        role:         role,
        description:  agent_spec["system_prompt_summary"],
        requirements: agent_spec["model_requirements"] || {}
      )
      provider = recommendation[:provider]
      model    = recommendation[:model]
      unless provider
        Rails.logger.error("[create_team_from_spec] no active AI provider — cannot create agent for role=#{role}")
        return nil
      end

      Rails.logger.info("[create_team_from_spec] model_selection role=#{role}: #{recommendation[:reason]}")

      base = (agent_spec["name"] || role).to_s.parameterize.truncate(40, omission: "")
      slug = unique_agent_slug(base)
      # Agent + lineage land together or not at all (the caller's transaction
      # only rolls back on a raise; this method returns nil on failure).
      ::ActiveRecord::Base.transaction(requires_new: true) do
        created = ::Ai::Agent.create!(
          account:       @account,
          creator:       @user,
          provider:      provider,
          name:          agent_spec["name"] || role.titleize,
          slug:          slug,
          agent_type:    agent_type,
          status:        "active",
          description:   agent_spec["system_prompt_summary"],
          system_prompt: agent_spec["system_prompt_summary"],
          mcp_metadata:  {
            "created_by"      => "design-agent-team-from-intent",
            "role"            => role,
            "model_config"    => { "model" => model },
            "model_selection" => {
              "provider_type" => recommendation[:provider_type],
              "model"         => model,
              "reason"        => recommendation[:reason],
              "selected_at"   => Time.current.iso8601,
              "score_details" => recommendation[:score_details]
            }.compact
          }
        )
        attach_composed_agent_lineage!(created, role)
        created
      end
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error("[create_team_from_spec] agent_create failed role=#{role}: #{e.message}")
      nil
    end

    # HIER-P1 — an agent composed from a spec is not a root: its lineage
    # parent is the concierge that designed it (this conversation's agent),
    # else the account's resolved concierge, written through the ONE
    # hierarchy seam so the Autonomy forest shows the composition.
    def attach_composed_agent_lineage!(created, role)
      parent = @agent if @agent&.persisted?
      parent ||= ::Ai::Agent.resolve_concierge_for(@account.id)
      return if parent.nil? || parent.id == created.id

      ::Ai::Agents::HierarchyWriter.new(account: @account).attach!(
        child: created, parent: parent, spawn_reason: "team_composition",
        metadata: { "role" => role, "designed_by" => "design-agent-team-from-intent" }
      )
    end

    def valid_agent_type(t)
      allowed = ::Ai::Agent.validators_on(:agent_type).flat_map { |v| Array(v.options[:in]) }
      allowed.include?(t) ? t : "assistant"
    end

    def unique_agent_slug(base)
      slug = base
      i = 1
      while ::Ai::Agent.exists?(slug: slug)
        slug = "#{base}-#{i}"
        i += 1
      end
      slug
    end

    def unique_team_name(base)
      name = base
      i = 1
      while @account.ai_agent_teams.exists?(name: name)
        name = "#{base} (#{i})"
        i += 1
      end
      name
    end

    def unique_team_role_name(team, base)
      candidate = base.to_s
      i = 1
      while ::Ai::TeamRole.exists?(role_name: candidate)
        candidate = "#{base}_#{team.id[0, 6]}_#{i}"
        i += 1
      end
      candidate
    end

    def trigger_deploy(params)
      mission = @account.ai_missions.find_by(id: params["mission_id"])
      unless mission
        @conversation.add_assistant_message("Mission not found.")
        return
      end

      @conversation.add_assistant_message(
        "Deployment requested for mission **#{mission.name}**. " \
        "The mission must be in the deploying phase for deployment to proceed."
      )
    end

    def handle_approval(body)
      mission = @account.ai_missions.in_progress.to_a.select(&:awaiting_approval?).max_by(&:updated_at)
      unless mission
        @conversation.add_assistant_message("There are no missions awaiting approval right now.")
        return
      end

      decision = body.to_s.match?(/\b(reject|deny|decline|disapprove)\b/i) ? "rejected" : "approved"
      approve_mission_gate("mission_id" => mission.id, "gate" => mission.current_phase, "decision" => decision)
    end

    # =========================================================================
    # Shared helpers
    # =========================================================================

    def find_repository(identifier)
      return nil if identifier.blank?
      Devops::GitRepository.where(account_id: @account.id)
        .where("full_name ILIKE ? OR name ILIKE ?", "%#{identifier}%", "%#{identifier}%")
        .first
    end

    def available_repo_names
      Devops::GitRepository.where(account_id: @account.id).limit(5).pluck(:full_name)
    end

    def format_analysis_result(result, repo)
      parts = ["## Repository Analysis: #{repo.full_name}\n"]

      if result.is_a?(Hash)
        if result["tech_stack"].present?
          parts << "**Tech Stack**: #{Array(result['tech_stack']).join(', ')}"
        end
        if result["file_count"].present?
          parts << "**Files**: #{result['file_count']}"
        end
        if result["feature_suggestions"].is_a?(Array) && result["feature_suggestions"].any?
          parts << "\n**Feature Suggestions**:"
          result["feature_suggestions"].each_with_index do |s, i|
            title = s.is_a?(Hash) ? s["title"] || s["name"] : s.to_s
            parts << "#{i + 1}. #{title}"
          end
        end
      end

      parts.join("\n")
    end

    def resolve_pending_action(action_type)
      message = @conversation.messages
                                .where(role: "assistant")
                                .order(created_at: :desc)
                                .find { |m|
                                  m.content_metadata&.dig("concierge_action") &&
                                    m.content_metadata&.dig("action_context", "status") == "pending" &&
                                    m.content_metadata&.dig("action_context", "action_type") == action_type
                                }

      return unless message

      updated_metadata = message.content_metadata.deep_dup
      updated_metadata["action_context"]["status"] = "confirmed"
      updated_metadata["action_context"]["resolved_at"] = Time.current.iso8601
      message.update!(content_metadata: updated_metadata)
    end

    def find_credential
      if @agent&.provider
        @agent.provider.provider_credentials
          .where(is_active: true, account_id: @account.id)
          .first
      else
        Ai::ProviderCredential.where(is_active: true, account_id: @account.id).first
      end
    end

    def concierge_model
      @agent&.model || @agent&.mcp_tool_manifest&.dig("model")
    end

    def extract_response_text(response)
      return response.to_s unless response.is_a?(Hash)

      response.dig(:choices, 0, :message, :content) ||
        response[:content]&.then { |c| c.is_a?(Array) ? c.select { |b| b[:type] == "text" }.map { |b| b[:text] }.join("\n") : c } ||
        response[:text] || response.to_s
    end
  end
end
