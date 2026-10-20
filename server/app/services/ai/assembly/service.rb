# frozen_string_literal: true

module Ai
  module Assembly
    # assemble_task (skills-first agents, PRE-2) — the MINIMAL assembler. A task
    # and an agent slug in; the skills that own the task, the learnings those
    # skills carry, and the tier / model / effort to run at out; one durable
    # record per call; the same assembly fetched back by id.
    #
    #   candidates  skill-graph traversal (embedding over name + description +
    #               triggers) inside the agent's DOMAIN CEILING, direct matches
    #               only, best five; then the `requires` closure of those five
    #               (a required skill rides along whatever its domain — it is the
    #               selected skill's own dependency — and is marked via: requires).
    #               A read-only role (roster role[:read_only]) is only ever handed
    #               skills that are manifest.read_only: others are not candidates
    #               and a required one is dropped;
    #   floors      the roster tier is the floor and nothing lowers it. Two
    #               independent raisers, max wins: the selected skills'
    #               hints (min_tier, effort) and VERB RISK (any manifest verb
    #               that is gated -> reasoning / high);
    #   model       context claude_code maps the tier to haiku|sonnet|opus|fable
    #               and returns the Agent tool's effort; the platform context
    #               returns no model (provider choice is the router's, later);
    #   learnings   active learnings tagged with a selected skill's tags or
    #               knowledge tags;
    #   record      one Ai::RoutingDecision, request_type "task_assembly", whose
    #               id is the assembly_id. Pre-seed runs persist here (no
    #               migration in the deploy image); a later increment moves them
    #               to a dedicated table with one request_type filter.
    #
    # Called again with an assembly_id it returns the STORED assembly untouched,
    # which is how the spawned subagent picks up what its delegating session
    # assembled. Raises Refusal on anything the caller got wrong.
    class Service
      class Refusal < StandardError; end

      REQUEST_TYPE = "task_assembly"
      STRATEGY = "hybrid"
      CONTEXTS = %w[claude_code platform].freeze
      CLAUDE_CODE_MODELS = { "light" => "haiku", "standard" => "sonnet", "reasoning" => "opus", "frontier" => "fable" }.freeze
      TIER_ORDER = ::Ai::Agents::CanonicalRoster::TIERS
      EFFORT_ORDER = %w[low medium high xhigh max].freeze
      DEFAULT_EFFORT = "medium"
      RISK_TIER = "reasoning"
      RISK_EFFORT = "high"
      MAX_SKILLS = 5
      MAX_LEARNINGS = 5
      LEARNING_CHARS = 600
      DIGEST_CHARS = 500
      # Large enough that ranking, not the prompt-size budget, decides the cut.
      TRAVERSAL_BUDGET = 100_000

      def initialize(account:)
        @account = account
      end

      # @return [Hash] assembly_id, agent_slug, context, skills[], learnings[],
      #   knowledge_tags[], tier, model, effort, floor_reason, uncovered[],
      #   routing_decision_id
      def call(task: nil, agent_slug: nil, context: "claude_code", lane: nil, assembly_id: nil)
        return fetch(assembly_id, agent_slug) if assembly_id.present?

        context = context.to_s.presence || "claude_code"
        raise Refusal, "context must be one of #{CONTEXTS.join('/')}" unless CONTEXTS.include?(context)

        spec = roster_spec(agent_slug)
        raise Refusal, "task is required" if task.to_s.strip.empty?

        skills = select_skills(task.to_s, spec)
        floors = floors_for(spec, skills)
        learnings, tags = learnings_for(skills)
        uncovered = skills.empty? ? [ { facet: "task", reason: "no capability skill matches this task; route_task, or ask the delegating session" } ] : []

        persist(agent_slug.to_s, context, lane, task.to_s, skills, learnings, tags, floors, uncovered)
      end

      private

      attr_reader :account

      def roster_spec(agent_slug)
        slug = agent_slug.to_s
        raise Refusal, "agent_slug is required" if slug.empty?
        raise Refusal, "agent_slug #{slug.inspect} is not a roster agent (#{::Ai::Agents::CanonicalRoster.slugs.join(', ')})" unless ::Ai::Agents::CanonicalRoster.include?(slug)

        ::Ai::Agents::CanonicalRoster.fetch(slug)
      end

      # ---- candidates --------------------------------------------------------

      def select_skills(task, spec)
        result = ::Ai::SkillGraph::TraversalService.new(account).traverse(
          task_context: task, mode: :auto, token_budget: TRAVERSAL_BUDGET, domains: spec[:domains]
        )
        direct = Array(result[:discovered_skills]).select { |entry| entry[:depth].to_i.zero? }
                                                  .sort_by { |entry| -entry[:score].to_f }.first(MAX_SKILLS)
        rows = ::Ai::Skill.where(id: direct.map { |entry| entry[:skill_id] }).index_by(&:id)
        selected = direct.filter_map { |entry| rows[entry[:skill_id]]&.then { |row| skill_hash(row, entry[:score], nil) } }
        read_only = spec[:role][:read_only]
        selected = selected.select { |skill| read_only_skill?(skill) } if read_only
        selected + required_closure(selected, read_only: read_only)
      end

      # The `requires` closure of the selected skills, breadth first, each skill once.
      def required_closure(selected, read_only: false)
        seen = selected.map { |s| s[:slug] }
        queue = selected.flat_map { |s| required_slugs(s[:metadata]) }
        added = []
        until queue.empty?
          slug = queue.shift
          next if seen.include?(slug)

          seen << slug
          row = ::Ai::Skill.for_account(account.id).active.enabled.account_override_first.find_by(slug: slug)
          next unless row

          skill = skill_hash(row, nil, "requires")
          # A read-only role is never handed a skill that writes, not even one a
          # read-only skill requires: the dependency is dropped.
          next if read_only && !read_only_skill?(skill)

          added << skill
          queue.concat(required_slugs(row.metadata))
        end
        added
      end

      def read_only_skill?(skill)
        skill[:manifest]["read_only"] == true
      end

      def required_slugs(metadata)
        Array(metadata.is_a?(Hash) ? metadata.dig("relations", "requires") : nil).map(&:to_s)
      end

      def skill_hash(row, score, via)
        meta = row.metadata.is_a?(Hash) ? row.metadata : {}
        {
          slug: row.slug, name: row.name, system_prompt: row.system_prompt,
          manifest: meta["manifest"].is_a?(Hash) ? meta["manifest"] : {},
          hints: meta["hints"].is_a?(Hash) ? meta["hints"] : {},
          tags: Array(row.tags), score: score&.to_f&.round(4), via: via, metadata: meta
        }
      end

      # ---- floors ------------------------------------------------------------

      # Roster tier is the floor; skill hints and verb risk only raise it.
      def floors_for(spec, skills)
        tier = spec[:tier]
        effort = DEFAULT_EFFORT
        reasons = []

        skills.each do |skill|
          hinted_tier = skill[:hints]["min_tier"].to_s
          hinted_effort = skill[:hints]["effort"].to_s
          raised_tier = TIER_ORDER.index(hinted_tier).to_i > TIER_ORDER.index(tier).to_i
          raised_effort = EFFORT_ORDER.index(hinted_effort).to_i > EFFORT_ORDER.index(effort).to_i
          next unless raised_tier || raised_effort

          tier = hinted_tier if raised_tier
          effort = hinted_effort if raised_effort
          reasons << "skill hint: #{skill[:slug]} (#{hinted_tier.presence || '-'}/#{hinted_effort.presence || '-'})"
        end

        risk = ::Ai::Assembly::VerbRisk.new
        gated = skills.flat_map do |skill|
          risk.gated_verbs(Array(skill[:manifest]["verbs"]), parking: skill[:manifest]["gate_category"] != "read")
        end.uniq
        if gated.any?
          tier = RISK_TIER if TIER_ORDER.index(RISK_TIER) > TIER_ORDER.index(tier)
          effort = RISK_EFFORT if EFFORT_ORDER.index(RISK_EFFORT) > EFFORT_ORDER.index(effort)
          reasons << "verb risk: #{gated.first(5).join(', ')}"
        end

        { tier: tier, effort: effort, reason: reasons.any? ? reasons.join("; ") : "roster tier #{spec[:tier]}" }
      end

      # ---- learnings ---------------------------------------------------------

      def learnings_for(skills)
        tags = skills.flat_map { |s| s[:tags] + Array(s[:manifest]["knowledge_tags"]) }.map(&:to_s).reject(&:blank?).uniq
        return [ [], tags ] if tags.empty?

        rows = ::Ai::CompoundLearning.for_account(account.id).surfacing
                                     .where("jsonb_exists_any(tags, ARRAY[:tags]::text[])", tags: tags)
                                     .order(importance_score: :desc, created_at: :desc).limit(MAX_LEARNINGS)
        learnings = rows.map do |row|
          { id: row.id, title: row.title, category: row.category, content: row.content.to_s.truncate(LEARNING_CHARS), tags: Array(row.tags) }
        end
        [ learnings, tags ]
      end

      # ---- record ------------------------------------------------------------

      def persist(agent_slug, context, lane, task, skills, learnings, tags, floors, uncovered)
        stored_skills = skills.map { |s| s.except(:metadata) }
        model = context == "claude_code" ? CLAUDE_CODE_MODELS.fetch(floors[:tier]) : nil
        decision = ::Ai::RoutingDecision.create!(
          account: account, request_type: REQUEST_TYPE, strategy_used: STRATEGY, model_tier: floors[:tier],
          decision_reason: "assembly",
          request_metadata: {
            "agent_slug" => agent_slug, "context" => context, "lane" => lane, "task_digest" => digest(task),
            "tier" => floors[:tier], "model" => model, "effort" => floors[:effort], "floor_reason" => floors[:reason],
            "selected" => stored_skills.map(&:deep_stringify_keys), "learnings" => learnings.map(&:deep_stringify_keys),
            "knowledge_tags" => tags, "uncovered" => uncovered.map(&:deep_stringify_keys)
          },
          rationale: { "mode" => "assembly", "floor_reason" => floors[:reason] },
          candidates_evaluated: stored_skills.map { |s| { "slug" => s[:slug], "score" => s[:score], "via" => s[:via], "selected" => true } }
        )
        payload_from(decision)
      end

      # ---- fetch -------------------------------------------------------------

      def fetch(assembly_id, agent_slug)
        decision = ::Ai::RoutingDecision.find_by(id: assembly_id.to_s, account_id: account.id, request_type: REQUEST_TYPE) if uuid?(assembly_id)
        raise Refusal, "no assembly #{assembly_id} for this account" unless decision

        stored_slug = decision.request_metadata["agent_slug"]
        if agent_slug.present? && agent_slug.to_s != stored_slug
          raise Refusal, "assembly #{assembly_id} was made for #{stored_slug}, not #{agent_slug}"
        end

        payload_from(decision)
      end

      def uuid?(value)
        value.to_s.match?(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/)
      end

      def payload_from(decision)
        meta = decision.request_metadata
        {
          assembly_id: decision.id,
          agent_slug: meta["agent_slug"],
          context: meta["context"],
          skills: Array(meta["selected"]).map { |s| s.symbolize_keys },
          learnings: Array(meta["learnings"]).map { |l| l.symbolize_keys },
          knowledge_tags: Array(meta["knowledge_tags"]),
          tier: meta["tier"],
          model: meta["model"],
          effort: meta["effort"],
          floor_reason: meta["floor_reason"],
          uncovered: Array(meta["uncovered"]).map { |u| u.symbolize_keys },
          routing_decision_id: decision.id
        }
      end

      def digest(text)
        capped = text.to_s.strip.truncate(DIGEST_CHARS, omission: "…")
        ::Ai::Security::PiiRedactionService.new(account: account)
                                           .redact(text: capped, context: { source_type: "TaskAssembly" }, log: false)[:redacted_text]
                                           .to_s.truncate(DIGEST_CHARS, omission: "…")
      rescue StandardError => e
        Rails.logger.warn("[Ai::Assembly::Service] digest redaction failed, dropping digest: #{e.class}: #{e.message}")
        ""
      end
    end
  end
end
