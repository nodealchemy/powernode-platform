# frozen_string_literal: true

module Ai
  module ClaudeExport
    # Builds the Claude Code frontmatter `description` for an exported platform
    # agent (HIER-P1B item 9). Claude Code's Agent tool picks a subagent_type by
    # reading each definition's description, so this is a ROUTING description,
    # not a blurb: "Use this agent when …" with concrete triggers, then "Do not
    # use for …" naming the sibling that owns the adjacent domain, so automatic
    # delegation lands on the right specialist (SDWAN Manager vs Fleet Autonomy).
    #
    # Triggers, in order of specificity: the agent's policy domains
    # (PolicyDomains over its intervention-policy categories — ACCOUNT scope
    # only; those rows are account data, so a CANONICAL description has none and
    # leans on the global signal), its bound skills' names and tags, then a
    # compacted first sentence of its own description.
    #
    # The exclusion names the ADJACENT sibling: the one whose vocabulary most
    # overlaps this agent's while still owning topics this agent does not — the
    # neighbour a caller could confuse with it. Ranking on foreign topics alone
    # made every agent exclude the single topic-richest sibling, which is not a
    # routing signal but a standing bias. With no such sibling it names one of a
    # different type, and with no sibling at all it points at the general-purpose
    # agent — so every description carries exactly one exclusion by construction.
    #
    # Bounded at MAX_CHARS. The exclusion is built first and always kept whole;
    # triggers are dropped from the least specific end until the text fits.
    # The tier guidance the exporter appends afterwards is NOT counted here.
    module RoutingDescription
      MAX_CHARS = 400
      TRIGGER_PREFIX = "Use this agent when the task involves "
      EXCLUSION_PREFIX = "Do not use for "
      MAX_SKILL_TRIGGERS = 3
      MAX_TAG_TRIGGERS = 4
      MAX_DESCRIPTION_CHARS = 140
      MIN_VOCABULARY_WORD = 4
      ELLIPSIS = "…"

      module_function

      # Batch entry point the exporter uses: siblings are every OTHER agent in
      # the same export set, described by key/name/domains/type.
      #
      # @return [Hash{String => String}] key => description
      def build_all(agents, skills_by_agent: {}, domains_by_agent: {})
        profiles = agents.map do |agent|
          domains = Array(domains_by_agent[agent.id])
          skills = skills_by_agent[agent.id] || []
          { key: key(agent), name: agent.name.to_s, domains: domains,
            agent_type: agent.agent_type.to_s,
            topics: topics_of(agent, skills, domains), vocabulary: vocabulary_of(agent, skills, domains) }
        end

        agents.each_with_object({}) do |agent, out|
          own_key = key(agent)
          out[own_key] = build(
            agent,
            skills: skills_by_agent[agent.id] || [],
            domains: Array(domains_by_agent[agent.id]),
            siblings: profiles.reject { |profile| profile[:key] == own_key }
          )
        end
      end

      # @param skills   [Array<#name, #tags>]
      # @param domains  [Array<String>]
      # @param siblings [Array<Hash>] { key:, name:, domains:, agent_type: }
      def build(agent, skills:, domains:, siblings:)
        exclusion = exclusion_clause(agent, Array(skills), Array(domains), Array(siblings))
        budget = MAX_CHARS - exclusion.length - 1
        "#{trigger_clause(agent, Array(skills), Array(domains), budget)} #{exclusion}"
      end

      def key(agent)
        ::Ai::Routing::RoutableAgents.key(agent)
      end

      def trigger_clause(agent, skills, domains, budget)
        parts = []
        parts.concat(domains.map { |domain| domain.to_s.tr("_", " ") })
        parts.concat(skills.first(MAX_SKILL_TRIGGERS).map { |skill| skill.name.to_s.strip })
        parts.concat(skills.flat_map { |skill| Array(skill.tags) }.map(&:to_s).uniq.first(MAX_TAG_TRIGGERS))
        parts = parts.map(&:strip).reject(&:blank?).uniq
        compact = compact_description(agent.description)
        parts << compact if compact.present?
        parts = [ fallback_trigger(agent) ] if parts.empty?

        fit_triggers(parts, budget)
      end

      def fit_triggers(parts, budget)
        text = render_triggers(parts)
        while text.length > budget && parts.size > 1
          parts = parts[0...-1]
          text = render_triggers(parts)
        end
        return text if text.length <= budget

        room = budget - TRIGGER_PREFIX.length - 1 - ELLIPSIS.length
        room = 1 if room < 1
        render_triggers([ "#{parts.first[0, room]}#{ELLIPSIS}" ])
      end

      def render_triggers(parts)
        "#{TRIGGER_PREFIX}#{parts.join('; ')}."
      end

      def compact_description(description)
        text = description.to_s.strip.gsub(/\s+/, " ")
        return nil if text.empty?

        first = text.split(/(?<=[.!?])\s+/).first.to_s.sub(/[.!?]+\z/, "")
        first = "#{first[0, MAX_DESCRIPTION_CHARS - ELLIPSIS.length]}#{ELLIPSIS}" if first.length > MAX_DESCRIPTION_CHARS
        # Lower-case a sentence-initial capital so the clause reads mid-sentence,
        # but leave an acronym ("SDWAN reconciler", "CVE triage") intact.
        first.sub(/\A[A-Z](?=[a-z])/) { |c| c.downcase }
      end

      def fallback_trigger(agent)
        "#{agent.name.to_s.strip.presence || 'this agent'} (#{agent.agent_type}) work"
      end

      def exclusion_clause(agent, skills, domains, siblings)
        sibling, foreign = adjacent_sibling(agent, skills, domains, siblings)
        if sibling && foreign.any?
          "#{EXCLUSION_PREFIX}#{foreign.first(2).join(' or ')} work — use `#{sibling[:key]}` (#{sibling[:name]}) instead."
        elsif sibling
          "#{EXCLUSION_PREFIX}#{sibling[:name].to_s.downcase} work — use `#{sibling[:key]}` (#{sibling[:name]}) instead."
        else
          "#{EXCLUSION_PREFIX}work outside this scope — prefer the general-purpose agent instead."
        end
      end

      # ADJACENCY, not raw foreign-topic count. "Adjacent" is the sibling whose
      # subject matter this agent's own subject matter most OVERLAPS while still
      # owning topics this agent does not: the neighbour a caller could plausibly
      # confuse with this agent (SDWAN Manager vs Fleet Autonomy), which is what
      # the exclusion has to disambiguate.
      #
      # Scoring on foreign-topic count alone made this degenerate: the globally
      # topic-richest agent won for EVERY agent, so 22 of 23 canonical
      # descriptions excluded the same sibling — no routing signal at all, and a
      # standing bias in Claude Code's automatic delegation toward one agent.
      # Overlap is agent-specific, so the winner varies; the tie-break stays the
      # key, so the render is still deterministic.
      #
      # Ranking: shared-vocabulary size desc, then foreign-topic count desc,
      # then key. Siblings with no shared vocabulary rank after every sibling
      # that has some. With no topic signal anywhere, a sibling of a different
      # agent type, else the first sibling.
      def adjacent_sibling(agent, skills, domains, siblings)
        mine_topics = topics_of(agent, skills, domains)
        mine_vocab = vocabulary_of(agent, skills, domains)

        scored = siblings.filter_map do |sibling|
          foreign = sibling_topics(sibling) - mine_topics
          next if foreign.empty?

          shared = (sibling_vocabulary(sibling) & mine_vocab).size
          [ sibling, foreign, shared ]
        end.sort_by { |(sibling, foreign, shared)| [ -shared, -foreign.size, sibling[:key].to_s ] }
        return scored.first.first(2) if scored.any?

        ordered = siblings.sort_by { |sibling| sibling[:key].to_s }
        fallback = ordered.find { |sibling| sibling[:agent_type].to_s != agent.agent_type.to_s } || ordered.first
        fallback ? [ fallback, [] ] : [ nil, [] ]
      end

      # A sibling profile from #build_all carries :topics/:vocabulary; one
      # handed straight to #build (a caller, a spec) may carry only :domains and
      # :name, so both are derived from what is there.
      def sibling_topics(sibling)
        topics = Array(sibling[:topics]).map { |topic| topic.to_s.strip.downcase }.reject(&:blank?)
        return topics if topics.any?

        Array(sibling[:domains]).map { |domain| domain.to_s.tr("_", " ").strip.downcase }.reject(&:blank?).uniq
      end

      def sibling_vocabulary(sibling)
        vocabulary = Array(sibling[:vocabulary]).map(&:to_s)
        return vocabulary.to_set if vocabulary.any?

        text = [ sibling[:name], Array(sibling[:domains]).join(" ") ].compact.join(" ").downcase
        text.scan(/[a-z0-9][a-z0-9_-]*/).select { |word| word.length >= MIN_VOCABULARY_WORD }.to_set
      end

      # Readable subject phrases (what "do not use for X work" names): policy
      # domains first, then bound skill names. Downcased and deduplicated so two
      # agents naming the same subject differently still compare equal.
      def topics_of(agent, skills, domains)
        (Array(domains).map { |domain| domain.to_s.tr("_", " ") } +
          Array(skills).map { |skill| skill.name.to_s }).map { |topic| topic.strip.downcase }
                                                        .reject(&:blank?).uniq
      end

      # Comparison tokens (what "adjacent" means): every word of the agent's
      # name, description, domains, and its bound skills' names and tags, minus
      # very short words. A Set — overlap size is the adjacency score.
      def vocabulary_of(agent, skills, domains)
        text = [
          agent.name, agent.description, Array(domains).join(" "),
          Array(skills).map { |skill| [ skill.name, Array(skill.tags).join(" ") ].join(" ") }.join(" ")
        ].compact.join(" ").downcase
        text.scan(/[a-z0-9][a-z0-9_-]*/).select { |word| word.length >= MIN_VOCABULARY_WORD }.to_set
      end
    end
  end
end
