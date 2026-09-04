# frozen_string_literal: true

module Ai
  # Pre-LLM router for the Powernode Assistant chat experience.
  #
  # Given an incoming user message, this service decides one of three paths:
  #
  #   :invoked     — A high-confidence one_shot skill matches the query;
  #                  the router invokes the skill directly and returns
  #                  the result as context for the LLM to phrase the
  #                  natural-language reply. No specialist takeover.
  #
  #   :delegated   — A workflow_step skill (or cluster of related skills)
  #                  surfaces from a single extension domain. The router
  #                  hands control to that domain's specialist agent;
  #                  subsequent LLM call uses the specialist's prompt +
  #                  tool surface.
  #
  #   :passthrough — Nothing decisive surfaced. Default chat flow
  #                  continues as if the router never ran.
  #
  # Routing is deterministic — no LLM call is consumed deciding which
  # path to take. The LLM still runs once afterward to phrase the
  # response (using injected context for :invoked, or with the
  # specialist's prompt for :delegated).
  #
  # Cost per query: one embedding call (~$0.00001) for discover_skills
  # plus whichever path fires. Routing decisions take <50ms.
  #
  # Skill metadata required for routing (see Ai::Skill):
  #   metadata["domain"]           → "platform" | "system" | "<extension>" | ...
  #   metadata["invocation_mode"]  → "one_shot" | "workflow_step"
  #
  # Auto-invocable skills must have a single required free-text input
  # (intent, query, task_context, or question). The router maps the user's
  # message body onto that input and calls the executor directly.
  class ConciergeRouter
    Result = Struct.new(
      :mode,
      :skill_slug,
      :skill_data,
      :delegated_agent,
      :context_addendum,
      keyword_init: true
    )

    # Input parameter names the router knows how to populate from a
    # natural-language user message. Skills with a single required input
    # named one of these get auto-invoked; others fall through to passthrough.
    AUTO_INVOKABLE_INPUT_KEYS = %w[intent query task_context question text].freeze

    # Max discovered-skill candidates the router will look at when
    # deciding rules. Beyond this, signal-to-noise gets murky and we
    # default to passthrough rather than guess.
    MAX_DISCOVERED_FOR_AUTO_INVOKE = 2

    def self.route(conversation:, user_message:)
      new(conversation: conversation, user_message: user_message).route
    end

    def initialize(conversation:, user_message:)
      @conversation = conversation
      @user_message = user_message
      @account = conversation&.account
      @user = resolve_user
    end

    def route
      text = @user_message&.body.to_s.strip
      return passthrough if text.empty?
      return passthrough unless @account.present?

      ordered = discover_relevant_skills(text)
      return passthrough if ordered.empty?

      if invoke_directly?(ordered)
        top = ordered.first
        return passthrough unless auto_invokable?(top)

        skill_result = invoke_skill(top, text)
        return Result.new(
          mode: :invoked,
          skill_slug: top.slug,
          skill_data: skill_result,
          context_addendum: format_for_llm(top, skill_result)
        )
      end

      if should_delegate?(ordered)
        specialist = resolve_specialist(ordered.first, text)
        return Result.new(mode: :delegated, delegated_agent: specialist) if specialist
      end

      passthrough
    end

    private

    def passthrough
      Result.new(mode: :passthrough)
    end

    # ONE router for both sides (HIER-P1B item 10). The matched skill still
    # nominates the candidates — the active assistant agents bound to it, the
    # same pool Ai::Skill#specialist_agent chooses from — but the CHOICE among
    # them is Ai::Routing::AgentRouterService, the router behind
    # `platform.route_task`, with the conversation's agent as the delegator so
    # its delegation policy binds this path exactly as it binds the MCP one.
    # A policy that allows none of the candidates yields nil (passthrough).
    # Falls back to the binding-only resolution only if the router itself
    # raises, and says so in the log — never silently.
    def resolve_specialist(skill, text)
      candidates = specialist_candidates(skill)
      return nil if candidates.empty?

      routed = ::Ai::Routing::AgentRouterService.new(account: @account)
                                                 .route(task: text, delegator: delegator_agent, candidates: candidates, limit: 1)
      routed[:agent_id] && candidates.find { |agent| agent.id == routed[:agent_id] }
    rescue StandardError => e
      Rails.logger.warn("[ConciergeRouter] AgentRouterService failed (#{e.class}: #{e.message}); falling back to skill binding")
      # The fallback must not be WIDER than the happy path. Ai::Skill#specialist_agent
      # filters on agent_type only, so it can nominate an INACTIVE assistant that
      # #specialist_candidates deliberately excludes; a router exception must not
      # be the way an inactive agent gets delegated to.
      fallback = skill.specialist_agent
      fallback if fallback && candidates.any? { |agent| agent.id == fallback.id }
    end

    def specialist_candidates(skill)
      return [] if skill.domain == "platform"

      skill.agent_skills.includes(:agent).map(&:agent).compact
           .select { |agent| agent.agent_type == "assistant" && agent.status == "active" }
    end

    def delegator_agent
      @conversation.respond_to?(:agent) ? @conversation.agent : nil
    end

    def resolve_user
      return @conversation.user if @conversation.respond_to?(:user) && @conversation.user.present?
      return @conversation.created_by if @conversation.respond_to?(:created_by) && @conversation.created_by.present?

      nil
    end

    # Calls discover_skills via the skill graph traversal service, then
    # rehydrates each result into an Ai::Skill row so we have access to
    # metadata.domain + invocation_mode + the specialist_agent helper.
    # Performs the embedding-based skill lookup with router-specific
    # tuning: a permissive distance threshold (0.85 cosine — keeps medium
    # matches in scope) and a small result cap. Bypasses
    # SkillGraph::TraversalService because that service uses a tighter
    # 0.6 threshold optimized for autonomous agent goal-planning, which
    # rejects too many chat-style queries with "fuzzy" intent.
    ROUTER_DISTANCE_THRESHOLD = 0.85
    ROUTER_TOP_K = 5

    def discover_relevant_skills(text)
      embedding = embedding_service.generate(text)
      return [] if embedding.blank?

      candidates = @account.ai_knowledge_graph_nodes
                           .skill_nodes
                           .active
                           .with_embeddings
                           .nearest_neighbors(:embedding, embedding, distance: "cosine")
                           .first(ROUTER_TOP_K)

      # Filter by router's looser threshold + keep only nodes that map to
      # an active skill row (KG nodes can outlive their skills temporarily).
      eligible = candidates.select { |c| c.neighbor_distance.to_f <= ROUTER_DISTANCE_THRESHOLD }
      return [] if eligible.empty?

      skill_ids = eligible.map(&:ai_skill_id).compact
      return [] if skill_ids.empty?

      skills_by_id = ::Ai::Skill.where(id: skill_ids).index_by(&:id)
      eligible.filter_map { |node| skills_by_id[node.ai_skill_id] }
    rescue StandardError => e
      Rails.logger.warn("[ConciergeRouter] skill discovery failed: #{e.class}: #{e.message}")
      []
    end

    def embedding_service
      @embedding_service ||= ::Ai::Memory::EmbeddingService.new(account: @account)
    end

    # Rule 1: invoke a skill directly when the top-ranked candidate is a
    # one_shot match. Trust the embedding's ranking — if it placed a
    # one_shot skill first, that's the model saying "this query is a
    # single Q&A." We ignore lower-ranked workflow_step neighbors because
    # they're adjacent-but-not-best; surfacing them would push the query
    # toward delegation when a direct answer is what the user wanted.
    def invoke_directly?(ordered)
      return false if ordered.empty?

      top = ordered.first
      return false unless top.one_shot?
      return false if top.domain == "platform" && !auto_invokable?(top)

      true
    end

    # Rule 2: delegate to a specialist when the top match (or the cluster's
    # dominant mode) is workflow_step. Platform-domain top matches never
    # delegate — they're either auto-invokable or fall through to passthrough.
    def should_delegate?(ordered)
      return false if ordered.empty?

      top = ordered.first
      return false if top.domain == "platform"

      # Top match is workflow_step → clear delegation signal.
      return true if top.workflow_step?

      # Top match is one_shot BUT the cluster has multiple workflow_step
      # peers from the same domain → user is probably mid-workflow.
      domain = top.domain
      same_domain = ordered.select { |s| s.domain == domain }
      workflow_count = same_domain.count(&:workflow_step?)
      workflow_count >= 2
    end

    # A skill is auto-invokable when its executor descriptor declares exactly
    # one required input, and that input's name is one we know how to
    # populate from a natural-language message body (intent, query, etc.).
    def auto_invokable?(skill)
      return false unless skill.metadata.is_a?(Hash)

      klass = resolve_executor_class(skill)
      return false unless klass

      desc = klass.respond_to?(:descriptor) ? klass.descriptor : nil
      return false unless desc.is_a?(Hash) && desc[:inputs].is_a?(Hash)

      required_keys = desc[:inputs].select { |_, spec| spec.is_a?(Hash) && spec[:required] }.keys.map(&:to_s)
      return false unless required_keys.size == 1
      AUTO_INVOKABLE_INPUT_KEYS.include?(required_keys.first)
    end

    def resolve_executor_class(skill)
      executor_class_name = skill.metadata["executor_class"]
      return nil if executor_class_name.blank?

      executor_class_name.constantize
    rescue NameError
      nil
    end

    # Constructs the executor and invokes its `execute` method with the
    # user's text mapped onto the skill's free-text input parameter.
    # Returns whatever the executor returns ({success:, data:} convention).
    def invoke_skill(skill, text)
      klass = resolve_executor_class(skill)
      return nil unless klass

      input_key_str = (klass.descriptor[:inputs].keys.map(&:to_s) & AUTO_INVOKABLE_INPUT_KEYS).first
      return nil unless input_key_str

      executor = klass.new(account: @account, agent: nil, user: @user)
      executor.execute(input_key_str.to_sym => text)
    rescue StandardError => e
      Rails.logger.warn("[ConciergeRouter] invoke #{skill.slug} failed: #{e.class}: #{e.message}")
      { success: false, error: "Router invocation failed: #{e.message}" }
    end

    # Renders the skill result as a system-message addendum the LLM sees
    # before phrasing its reply. The LLM doesn't know whether it called
    # the tool or the router did — same downstream shape either way.
    #
    # The directive language is deliberate: the base concierge system prompt
    # has instructions to call `search_knowledge` and report "not found"
    # when it returns empty. Without an explicit override, the LLM follows
    # that path and ignores our injected data. The addendum below is framed
    # as an authoritative override so the LLM treats the skill output as
    # the final answer rather than one signal among many.
    def format_for_llm(skill, result)
      return nil unless result.is_a?(Hash)

      if result[:success]
        body = result[:data].is_a?(Hash) ? JSON.pretty_generate(result[:data]) : result[:data].to_s
        <<~ADDENDUM
          ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
          ROUTER-INVOKED SKILL RESULT — AUTHORITATIVE ANSWER FOR THIS QUERY
          ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

          The user's most recent message was already answered by the
          platform tool `#{skill.slug}`. Use the data below as the
          authoritative answer when composing your reply.

          IMPORTANT — for this specific query:
            * DO NOT call `search_knowledge`, `search_documents`, or other
              fallback search tools. The result below is more accurate than
              anything those tools would return.
            * DO NOT respond with "no records found", "couldn't find in
              the knowledge base", or any other negative phrasing. The
              data below contains real platform results.
            * DO summarize the results naturally in plain language. Don't
              echo the raw JSON. Mention the top 3-5 packages by name and
              their similarity confidence when relevant.
            * DO offer follow-up actions (e.g., "Want me to create a
              NodeModule from one of these?") when appropriate.

          Skill: #{skill.slug}
          Result data:
          #{body}
          ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        ADDENDUM
      else
        <<~ADDENDUM
          ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
          ROUTER-INVOKED SKILL FAILURE
          ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

          The platform tool `#{skill.slug}` was invoked for this query
          but failed: #{result[:error] || 'unknown error'}.

          Acknowledge the failure briefly and offer to retry or use
          general knowledge as fallback.
          ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        ADDENDUM
      end
    end
  end
end
