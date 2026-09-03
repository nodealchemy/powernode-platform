# frozen_string_literal: true

module Ai
  module Routing
    # ONE router for both sides (HIER-P1B item 10). Ranks the routable agents
    # (Ai::Routing::RoutableAgents — the SAME set the Claude Code exporter
    # emits) for a task description and names the winner's Claude Code
    # `subagent_type` slug, so `platform.route_task` (MCP) and the Concierge's
    # delegation path (Ai::ConciergeRouter) pick the same specialist for the
    # same task.
    #
    # Honours delegation authority: when a `delegator:` is given, its
    # Ai::DelegationPolicy (the account's own row first — there is no
    # account-less one, the column is NOT NULL) restricts the candidate types
    # via #allows_delegate_type?, and the delegator itself is never a candidate.
    # NOTE the vocabulary: allowed_delegate_types is matched against
    # Ai::Agent#agent_type, so a policy row carrying skill slugs or policy
    # categories empties this pool rather than narrowing it — the no-agent
    # envelope names the policy and its allowed types so that is diagnosable
    # from the result instead of looking like "no agents exist".
    #
    # Scoring dimensions (weights sum to 1.0), each carried back as a reason:
    #   capability  Ai::Autonomy::CapabilityMatrixService — may this agent
    #               execute tools at its trust tier at all?
    #   trust       Ai::AgentTrustScore overall (0.3 when unscored)
    #   skill       keyword overlap between the task and the agent's name,
    #               description, prompt, DECLARED capabilities and bound skills
    #               (the GLOBAL ones plus the account's own — never another
    #               tenant's, HIER-P2G)
    #   domain      the task names one of the agent's policy domains
    #               (PolicyDomains over its intervention-policy categories)
    #   performance completed / total executions over the last 30 days
    #   cost        the agent's model tier vs the classifier's recommended tier
    #
    # Every one of those relations is batched for the whole pool in
    # #build_context before the scoring loop runs (eager-loading rule) — #score
    # touches no database.
    #
    # History: before this rewrite the service had NO caller on the tree
    # (`command grep -rln AgentRouterService server/app` returned only itself)
    # and would have raised on first use — #calculate_skill_match read
    # `agent.capabilities`, which is not a column (IMP-3af9c533d25d);
    # Ai::Agent#declared_capabilities is the live definition.
    class AgentRouterService
      WEIGHTS = {
        capability: 0.25, trust: 0.2, skill: 0.2, domain: 0.15, performance: 0.1, cost: 0.1
      }.freeze
      DEFAULT_LIMIT = 3
      MAX_LIMIT = 10
      UNSCORED_TRUST = 0.3
      NEUTRAL_DOMAIN = 0.25
      MIN_TASK_WORD = 4

      attr_reader :account

      def initialize(account:)
        @account = account
        @complexity_classifier = TaskComplexityClassifierService.new(account: account)
        @capability_service = Ai::Autonomy::CapabilityMatrixService.new(account: account)
      end

      # @param task       [String] task description
      # @param delegator  [Ai::Agent, nil] the agent asking; its delegation policy binds the result
      # @param candidates [Array<Ai::Agent>, nil] restrict to these (must be routable); default RoutableAgents.for(account)
      # @param limit      [Integer] candidates returned (1..MAX_LIMIT)
      # @return [Hash] { agent_id:, agent_name:, subagent_type:, confidence:, reasoning:, complexity:,
      #                  candidates: [...], alternatives: [...], delegation: {...} }
      def route(task:, delegator: nil, candidates: nil, limit: DEFAULT_LIMIT)
        limit = limit.to_i.clamp(1, MAX_LIMIT)
        pool = Array(candidates || RoutableAgents.for(account&.id))
        pool = pool.reject { |agent| delegator && agent.id == delegator.id }
        delegation = { delegator_id: delegator&.id, policy_applied: false }

        policy = delegator && delegation_policy_for(delegator)
        if policy
          before = pool.size
          pool = pool.select { |agent| policy.allows_delegate_type?(agent.agent_type) }
          delegation.merge!(policy_applied: true, allowed_delegate_types: Array(policy.allowed_delegate_types),
                            max_depth: policy.max_depth, excluded_by_policy: before - pool.size)
        end

        if pool.empty?
          reason = if policy && delegation[:excluded_by_policy].to_i.positive?
            "No routable agent allowed by #{delegator.name}'s delegation policy " \
              "(allowed types: #{Array(policy.allowed_delegate_types).presence&.join(', ') || 'any'})"
          else
            "No active agents available"
          end
          return no_agent_available(reason, delegation)
        end

        complexity = classify(task)
        context = build_context(pool)
        scored = pool.map { |agent| score(agent, task, complexity, context) }
                     .sort_by { |entry| [ -entry[:score], entry[:slug] ] }
        best = scored.first

        {
          agent_id: best[:agent_id],
          agent_name: best[:name],
          subagent_type: best[:slug],
          confidence: best[:score],
          reasoning: best[:breakdown],
          complexity: complexity,
          candidates: scored.first(limit),
          alternatives: scored[1..2]&.map { |entry| { agent_id: entry[:agent_id], score: entry[:score] } } || [],
          delegation: delegation
        }
      end

      private

      # The account's own row first, else any row for the agent. There is no
      # account-less delegation policy to prefer — ai_delegation_policies.account_id
      # is NOT NULL — so a "canonical row" branch here would be dead code.
      def delegation_policy_for(delegator)
        rows = ::Ai::DelegationPolicy.where(agent_id: delegator.id).order(:created_at, :id).to_a
        rows.find { |row| row.account_id == account&.id } || rows.first
      end

      def classify(task)
        @complexity_classifier.classify_preview(
          task_type: "agent_task",
          messages: [ { role: "user", content: task.to_s } ],
          tools: [],
          context: {}
        )
      rescue StandardError => e
        Rails.logger.warn("[AgentRouterService] complexity classification failed: #{e.class}: #{e.message}")
        { complexity_score: 0.5, recommended_tier: "standard", complexity_level: "unknown" }
      end

      # EVERY per-candidate relation is fetched ONCE for the whole pool before
      # scoring — policy domains, bound skills, trust scores and the execution
      # window. #score used to reach for each of these per candidate (4+ queries
      # x pool size, ~100 for the 23 canonicals on every route_task call and
      # every Concierge message), which is exactly the eager-loading rule the
      # exporter's own build_context already follows.
      def build_context(pool)
        ids = pool.map(&:id)
        {
          domains: domains_by_agent(ids),
          skills: skills_by_agent(ids),
          trust: trust_by_agent(ids),
          performance: performance_by_agent(ids)
        }
      end

      def domains_by_agent(ids)
        return {} if ids.empty?

        ::Ai::InterventionPolicy.where(ai_agent_id: ids, is_active: true)
                                .distinct.pluck(:ai_agent_id, :action_category)
                                .group_by(&:first)
                                .transform_values { |rows| ::Ai::ClaudeExport::PolicyDomains.for_categories(rows.map(&:last).sort) }
      end

      # The SAME predicate as Ai::Agent#skill_slugs (active binding to an active
      # skill), batched — so #declared_capabilities_for below composes exactly
      # what #declared_capabilities returns — restricted to the skills THIS
      # account can see (GloballyScopable.for_account: GLOBAL rows plus its
      # own). The canonical agents are shared rows, and Ai::AgentSkill carries
      # no account, so another tenant's private skill bound to a canonical
      # would otherwise shape this account's routing (HIER-P2G; before the
      # system skills were global, every account routed on Account.first's
      # rows). Sorted by slug so the profile text a candidate is matched
      # against is deterministic (it feeds a scored comparison, and ties break
      # on slug).
      def skills_by_agent(ids)
        return {} if ids.empty?

        ::Ai::AgentSkill.where(ai_agent_id: ids, is_active: true)
                        .joins(:skill).where(ai_skills: { status: "active" })
                        .merge(::Ai::Skill.for_account(account&.id))
                        .includes(:skill)
                        .each_with_object(Hash.new { |h, k| h[k] = [] }) { |binding, h| h[binding.ai_agent_id] << binding.skill }
                        .transform_values { |skills| skills.compact.sort_by { |skill| skill.slug.to_s } }
      end

      def trust_by_agent(ids)
        return {} if ids.empty?

        ::Ai::AgentTrustScore.where(agent_id: ids).index_by(&:agent_id)
      end

      # One grouped count for the whole pool instead of two counts per candidate.
      # @return [Hash{String => Hash}] agent_id => { total:, completed: }
      def performance_by_agent(ids)
        return {} if ids.empty?

        ::Ai::AgentExecution.where(ai_agent_id: ids).where("created_at > ?", 30.days.ago)
                            .group(:ai_agent_id, :status).count
                            .each_with_object(Hash.new { |h, k| h[k] = { total: 0, completed: 0 } }) do |((agent_id, status), count), out|
          out[agent_id][:total] += count
          out[agent_id][:completed] += count if status.to_s == "completed"
        end
      end

      def score(agent, task, complexity, context)
        domains = context[:domains][agent.id] || []
        task_words = task_words_of(task)
        scores = {}
        reasons = {}

        trust = context[:trust][agent.id]

        capability = capability_for(agent, trust)
        scores[:capability] = { allowed: 1.0, requires_approval: 0.5 }.fetch(capability, 0.0)
        reasons[:capability] = "execute_tool is #{capability} for this agent's trust tier"
        scores[:trust] = trust ? trust.overall_score.to_f : UNSCORED_TRUST
        reasons[:trust] = trust ? "trust score #{trust.overall_score.to_f.round(2)} (#{trust.tier})" : "no trust score yet (#{UNSCORED_TRUST} baseline)"

        matched = skill_matches(agent, task_words, context[:skills][agent.id] || [])
        scores[:skill] = task_words.empty? ? 0.3 : [ matched.size.to_f / task_words.size, 1.0 ].min
        reasons[:skill] = matched.any? ? "matches task terms: #{matched.first(5).join(', ')}" : "no task-term overlap with the agent's profile or skills"

        matched_domains = domains.select { |domain| domain_matches?(domain, task_words) }
        scores[:domain] = if domains.empty?
          NEUTRAL_DOMAIN
        else
          matched_domains.any? ? 1.0 : 0.0
        end
        reasons[:domain] = if domains.empty?
          "no policy domains declared (neutral)"
        elsif matched_domains.any?
          "task names the agent's policy domain(s): #{matched_domains.join(', ')}"
        else
          "task names none of the agent's policy domains (#{domains.join(', ')})"
        end

        scores[:performance] = performance_score(context[:performance][agent.id])
        reasons[:performance] = "#{(scores[:performance] * 100).round}% completed executions in the last 30 days"

        agent_tier = tier_of(agent)
        recommended = complexity[:recommended_tier].to_s.presence || "standard"
        scores[:cost] = cost_score(agent_tier, recommended)
        reasons[:tier] = "agent is #{agent_tier}-tier; classifier recommends #{recommended}"
        reasons[:cost] = cost_reason(agent_tier, recommended)

        total = WEIGHTS.sum { |dim, weight| (scores[dim] || 0.0) * weight }
        {
          agent_id: agent.id,
          slug: RoutableAgents.key(agent),
          subagent_type: RoutableAgents.key(agent),
          name: agent.name,
          agent_type: agent.agent_type,
          score: total.round(3),
          breakdown: scores.transform_values { |v| v.round(3) },
          reasons: reasons
        }
      end

      # Ai::Autonomy::CapabilityMatrixService#check resolves the agent to its
      # TRUST TIER and looks the action up in the (account-wide) matrix, so its
      # answer is a function of the tier alone — but it re-reads the trust score
      # and the guardrail config on every call. Keyed on the tier from the
      # already-batched score, the whole pool costs one lookup per DISTINCT tier
      # (at most a handful) instead of two queries per candidate.
      def capability_for(agent, trust)
        tier = trust&.tier.presence || "supervised"
        @capability_by_tier ||= {}
        return @capability_by_tier[tier] if @capability_by_tier.key?(tier)

        @capability_by_tier[tier] = @capability_service.check(agent: agent, action_type: "execute_tool")
      end

      def task_words_of(task)
        task.to_s.downcase.scan(/[a-z0-9][a-z0-9_-]*/).reject { |w| w.length < MIN_TASK_WORD }.uniq
      end

      # `skills` is the preloaded, slug-sorted binding set for this agent —
      # never `agent.skills` (that is a query per candidate inside the loop).
      def skill_matches(agent, task_words, skills)
        profile = [
          agent.name, agent.description,
          (agent.respond_to?(:system_prompt) ? agent.system_prompt : nil),
          declared_capabilities_for(agent, skills).join(" "),
          skills.map { |skill| [ skill.name, skill.description, Array(skill.tags).join(" ") ] }
        ].flatten.compact.join(" ").downcase
        task_words.select { |word| profile.include?(word) }
      end

      # Ai::Agent#declared_capabilities is skill slugs + the capability tokens in
      # its JSON columns, but it re-plucks the slugs per record — a query per
      # candidate inside the scoring loop. This assembles the SAME thing from the
      # batched skills and the model's own public parts (CAPABILITY_JSON_COLUMNS
      # + .capability_tokens_in), never a reimplementation of the token rules.
      # spec/services/ai/routing/agent_router_service_spec.rb pins the two as
      # EQUAL, so a change to either side fails rather than silently diverging.
      def declared_capabilities_for(agent, skills)
        tokens = skills.map { |skill| skill.slug.to_s }
        ::Ai::Agent::CAPABILITY_JSON_COLUMNS.each { |column| tokens += ::Ai::Agent.capability_tokens_in(agent[column]) }
        tokens.uniq
      end

      def domain_matches?(domain, task_words)
        tokens = domain.to_s.downcase.split(/[_\s-]+/)
        task_words.any? { |word| word == domain.to_s.downcase || tokens.include?(word) }
      end

      # @param counts [Hash, nil] { total:, completed: } from #performance_by_agent
      def performance_score(counts)
        total = counts&.fetch(:total, 0).to_i
        return 0.5 if total.zero?

        (counts[:completed].to_f / total).round(3)
      end

      def tier_of(agent)
        ::Ai::ModelTiers.classify(agent.model)
      rescue StandardError
        ::Ai::ModelTiers::DEFAULT_TIER
      end

      # Same tier as recommended: 1.0; a cheaper agent: 0.7 (may fall short);
      # a pricier one: 0.5 (spends more than the task needs). Ladder order is
      # Ai::ModelTiers::ORDER (ascending price/capability).
      def cost_score(agent_tier, recommended)
        wanted = wanted_tier(recommended)
        return 1.0 if agent_tier == wanted

        cheaper?(agent_tier, wanted) ? 0.7 : 0.5
      end

      def cost_reason(agent_tier, recommended)
        wanted = wanted_tier(recommended)
        return "tier matches the recommended #{recommended} tier" if agent_tier == wanted

        cheaper?(agent_tier, wanted) ? "cheaper than recommended (#{agent_tier} < #{wanted})" : "pricier than recommended (#{agent_tier} > #{wanted})"
      end

      def wanted_tier(recommended)
        ::Ai::ModelTiers::LABEL_TO_TIER.fetch(recommended, ::Ai::ModelTiers::DEFAULT_TIER)
      end

      def cheaper?(tier_a, tier_b)
        ::Ai::ModelTiers::ORDER.index(tier_a).to_i < ::Ai::ModelTiers::ORDER.index(tier_b).to_i
      end

      def no_agent_available(reason, delegation)
        {
          agent_id: nil,
          agent_name: nil,
          subagent_type: nil,
          confidence: 0.0,
          reasoning: { error: reason },
          candidates: [],
          alternatives: [],
          delegation: delegation
        }
      end
    end
  end
end
