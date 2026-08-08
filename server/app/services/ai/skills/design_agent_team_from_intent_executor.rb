# frozen_string_literal: true

module Ai
  module Skills
    # LLM-driven team composer. Given an operator's natural-language
    # description of a collaboration ("I want a team that reviews PRs for
    # security AND style with a coordinator that summarizes findings"),
    # produces a team specification — name, description, member roster
    # (existing agents or proposed new ones), coordination strategy,
    # output template.
    #
    # The spec is NOT persisted. Operator reviews + confirms, then a
    # follow-up action creates the Ai::AgentTeam + member rows via the
    # `create_team_from_spec` confirmation flow.
    #
    # This is the team-side analog of DesignSkillFromIntentExecutor for
    # recipes. They share patterns: shortlist candidates → LLM-design →
    # validate → return for confirmation.
    class DesignAgentTeamFromIntentExecutor
      # Supplies tracked_client_for (IMP 019fe1da).
      include AgentBackedService

      MAX_SHORTLIST_AGENTS = 20
      MAX_MEMBERS          = 6
      DEFAULT_STRATEGY     = "sequential"

      def self.descriptor
        {
          name: "design_agent_team_from_intent",
          description: "Design an Ai::AgentTeam from a free-text operator intent. Returns a team spec (NOT persisted) listing proposed members (existing agents or new agent specs to create), coordination strategy, and output template — for operator confirmation. Use when the operator describes a multi-agent collaboration like 'a team that reviews PRs for security and style'.",
          category: "skill_management",
          inputs: {
            intent:           { type: "string",  required: true,
                                description: "Free-text description of the team's purpose + collaboration shape" },
            suggested_name:   { type: "string",  required: false },
            max_members:      { type: "integer", required: false,
                                default: MAX_MEMBERS,
                                description: "Max member count (1-#{MAX_MEMBERS})" },
            preferred_strategy: { type: "string", required: false,
                                  description: "parallel | sequential | hierarchical | mesh — overrides LLM choice" }
          },
          outputs: {
            slug:                  :string,
            name:                  :string,
            description:           :string,
            coordination_strategy: :string,
            members:               :array,    # [{role, agent_slug | agent_spec, priority, required}]
            output_template:       :object,
            new_agents_to_create:  :array,    # subset of members where agent_slug doesn't exist yet
            existing_agents_used:  :array,    # subset where agent_slug references an existing row
            confidence:            :string
          }
        }
      end

      def initialize(account:, agent: nil, user: nil)
        @account = account
        @agent   = agent
        @user    = user
      end

      def execute(intent:, suggested_name: nil, max_members: MAX_MEMBERS, preferred_strategy: nil)
        return failure("intent is required") if intent.to_s.strip.empty?
        return failure("account is required") if @account.blank?

        max_members = max_members.to_i.clamp(1, MAX_MEMBERS)

        # 1. Shortlist existing agents the LLM can draw from
        existing_agents = shortlist_existing_agents
        return failure("No existing agents available in account for team composition") if existing_agents.empty?

        # 2. LLM call: design the team
        design = generate_team_design(intent, existing_agents, suggested_name, max_members, preferred_strategy)
        return failure(design[:error]) if design[:error]

        spec = design[:spec]

        # 3. Validate + classify members (existing vs new)
        validation = validate_spec(spec, existing_agents, max_members)
        return failure("Team spec invalid: #{validation[:errors].join('; ')}") if validation[:errors].any?

        slug = build_slug(spec["name"] || suggested_name || intent)
        name = spec["name"] || suggested_name || "Team from: #{intent.truncate(40)}"
        strategy = validate_strategy(spec["coordination_strategy"] || preferred_strategy || DEFAULT_STRATEGY)
        members  = validation[:normalized_members]
        new_count = validation[:new_agents].size

        result_data = {
          slug:                  slug,
          name:                  name,
          description:           spec["description"] || intent,
          coordination_strategy: strategy,
          members:               members,
          output_template:       spec["output"] || {},
          new_agents_to_create:  validation[:new_agents],
          existing_agents_used:  validation[:existing_agents],
          confidence:            confidence_for(validation, existing_agents)
        }

        # Structured confirmation hint — ConciergeToolBridge auto-surfaces
        # a confirmation card so operators don't depend on the LLM choosing
        # to call request_confirmation next.
        result_data[:confirmation] = {
          action_type:        "create_team_from_spec",
          action_description: "Create team **#{name}** (#{strategy}, #{members.size} member#{members.size == 1 ? '' : 's'}#{new_count.positive? ? ", #{new_count} new agent#{new_count == 1 ? '' : 's'} to create" : ''})",
          action_params:      result_data.deep_stringify_keys.except("confirmation")
        }

        success(result_data)
      rescue StandardError => e
        Rails.logger.error("[DesignAgentTeamFromIntent] crash: #{e.class}: #{e.message}")
        failure("Designer crashed: #{e.class}: #{e.message}")
      end

      private

      # === Agent shortlisting ===========================================

      def shortlist_existing_agents
        @account.ai_agents.where(status: "active").limit(MAX_SHORTLIST_AGENTS).map do |a|
          {
            slug:         a.slug || a.id.to_s,
            name:         a.name,
            agent_type:   a.agent_type,
            description:  (a.description || a.mcp_metadata&.dig("description")).to_s.truncate(120),
            domain:       a.autonomy_config.is_a?(Hash) ? a.autonomy_config["extension"] : nil
          }
        end
      end

      # === LLM-driven design ============================================

      def generate_team_design(intent, existing_agents, suggested_name, max_members, preferred_strategy)
        # Wrapped so the design call lands an Ai::AgentExecution (IMP 019fe1da).
        # Attributed to the INVOKING agent only: this is skill design, not
        # provisioning, so falling back to a provisioning agent would file the
        # cost under the wrong actor. With no invoking agent the call stays
        # untracked rather than mis-attributed. The openai preference and the
        # provider that serves the call are unchanged — this only wraps.
        llm = ::WorkerLlmClient.for_account(@account, provider_type: "openai") ||
              ::WorkerLlmClient.for_account(@account)
        llm = tracked_client_for(llm, agent: @agent)
        return { error: "No LLM provider configured for account" } unless llm

        messages = build_design_messages(intent, existing_agents, suggested_name, max_members, preferred_strategy)

        result = llm.complete(
          messages: messages,
          model:    llm.provider&.default_model || "gpt-4o-mini",
          temperature: 0.2,
          max_tokens: 2048
        )

        unless result&.success?
          return { error: "LLM call failed (finish_reason=#{result&.finish_reason || 'no response'})" }
        end

        content = result.content.to_s.strip
        content = content.sub(/\A```(?:json)?\s*\n?/i, "").sub(/\n?```\s*\z/, "").strip
        parsed = JSON.parse(content)
        { spec: parsed }
      rescue JSON::ParserError => e
        { error: "LLM returned malformed JSON: #{e.message.truncate(120)}" }
      rescue StandardError => e
        { error: "Team design failed: #{e.class}: #{e.message}" }
      end

      def build_design_messages(intent, existing_agents, suggested_name, max_members, preferred_strategy)
        agents_section = existing_agents.each_with_index.map do |a, idx|
          domain = a[:domain].present? ? " (domain: #{a[:domain]})" : ""
          "  #{idx + 1}. `#{a[:slug]}` — #{a[:name]} [#{a[:agent_type]}]#{domain}\n     #{a[:description]}"
        end.join("\n")

        system_prompt = <<~SYSTEM
          You design Ai::AgentTeams for the Powernode platform. Given an
          operator's natural-language description of a desired collaboration
          and a list of existing agents in the account, produce a team
          specification.

          Team spec format (JSON):
          {
            "name":        "<short team name>",
            "description": "<one-sentence purpose>",
            "coordination_strategy": "parallel" | "sequential" | "hierarchical" | "mesh",
            "members": [
              {
                "role": "<role name e.g. 'security_reviewer'>",
                "agent_slug": "<existing agent slug from shortlist>",
                "priority": <integer; lower = higher priority>,
                "required": true | false
              },
              // OR for a NEW agent the operator should create:
              {
                "role": "<role name>",
                "agent_spec": {
                  "name": "<proposed agent name>",
                  "agent_type": "assistant",
                  "system_prompt_summary": "<one-line description of this agent's purpose>"
                },
                "priority": <integer>,
                "required": true | false
              }
            ],
            "output": { "<key>": "<{{ role.field }} reference>" }
          }

          Coordination strategy hints:
            * parallel     — members work concurrently on the same input (good for reviews/audits)
            * sequential   — output of member N feeds member N+1 (good for pipelines)
            * hierarchical — one coordinator delegates to others
            * mesh         — members communicate freely with each other

          Rules:
            * Prefer existing agents from the shortlist when their description matches a role.
            * Propose new agents ONLY when no existing agent fits a needed role.
            * Member count: max #{max_members}. Pick the smallest team that does the job.
            * Output template references roles, not agent_slugs.
            * If the intent can't be accomplished with a team, return members=[] and explain in description.
        SYSTEM

        strategy_hint = preferred_strategy.present? ? "OPERATOR PREFERS strategy: #{preferred_strategy}\n\n" : ""
        name_hint     = suggested_name.present? ? "OPERATOR-SUGGESTED NAME: #{suggested_name}\n\n" : ""

        user_prompt = <<~USER
          OPERATOR INTENT:
          #{intent}

          #{name_hint}#{strategy_hint}EXISTING AGENTS (shortlist of #{existing_agents.size}):
          #{agents_section}

          Design the team to accomplish the intent above. Output only the
          JSON team spec — no commentary, no markdown fences.
        USER

        [
          { role: "system", content: system_prompt },
          { role: "user",   content: user_prompt }
        ]
      end

      # === Validation ===================================================

      def validate_spec(spec, existing_agents, max_members)
        errors   = []
        members  = Array(spec["members"])
        normalized = []
        new_agents = []
        existing_used = []

        errors << "missing name" if spec["name"].to_s.empty?
        errors << "missing description" if spec["description"].to_s.empty?
        errors << "no members proposed" if members.empty?
        errors << "too many members (max #{max_members})" if members.size > max_members

        existing_slugs = existing_agents.map { |a| a[:slug] }

        members.each_with_index do |m, i|
          role = m["role"].to_s
          errors << "member #{i + 1} missing role" if role.empty?

          if m["agent_slug"].present?
            if existing_slugs.include?(m["agent_slug"])
              existing_used << { role: role, agent_slug: m["agent_slug"] }
              normalized << {
                "role" => role, "agent_slug" => m["agent_slug"],
                "priority" => (m["priority"] || (i + 1) * 10).to_i,
                "required" => m["required"] != false
              }
            else
              errors << "member #{i + 1} references unknown agent_slug #{m['agent_slug'].inspect}"
            end
          elsif m["agent_spec"].is_a?(Hash)
            spec_attrs = m["agent_spec"]
            if spec_attrs["name"].to_s.empty?
              errors << "member #{i + 1} new agent_spec missing name"
            else
              new_agents << { role: role, agent_spec: spec_attrs }
              normalized << {
                "role" => role, "agent_spec" => spec_attrs,
                "priority" => (m["priority"] || (i + 1) * 10).to_i,
                "required" => m["required"] != false
              }
            end
          else
            errors << "member #{i + 1} must declare either agent_slug or agent_spec"
          end
        end

        { errors: errors, normalized_members: normalized,
          new_agents: new_agents, existing_agents: existing_used }
      end

      def validate_strategy(strategy)
        %w[parallel sequential hierarchical mesh].include?(strategy.to_s) ? strategy.to_s : DEFAULT_STRATEGY
      end

      # === Helpers ======================================================

      def build_slug(source)
        base = source.to_s.parameterize.truncate(60, omission: "")
        candidate = "team-#{base}"
        i = 1
        while ::Ai::AgentTeam.exists?(name: candidate)  # AgentTeam has no slug column; use name uniqueness
          candidate = "team-#{base}-#{i}"
          i += 1
        end
        candidate
      end

      def confidence_for(validation, existing_agents)
        return "low" if existing_agents.empty? || validation[:normalized_members].empty?
        # High when all members are existing agents (no new agent creation required)
        return "high" if validation[:new_agents].empty?
        # Medium when some new agents need to be created (more operator review needed)
        "medium"
      end

      def success(data)
        { success: true, data: data, requires_approval: true }
      end

      def failure(msg)
        { success: false, error: msg }
      end
    end
  end
end
