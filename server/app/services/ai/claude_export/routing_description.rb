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
    # (PolicyDomains over its intervention-policy categories in ACCOUNT scope;
    # in CANONICAL scope the exporter derives them from the action categories
    # its GLOBAL bound skills carry — see AgentSkeletonSync#domains_by_agent),
    # its bound skills' names and tags, then a compacted first sentence of its
    # own description — the DERIVED triggers — and last the SEED'S OWN ROUTING
    # SENTENCE: a "Use when …" sentence hand-authored in the agent description
    # (the wave-2 seeds write one because this export is what Claude Code
    # routes on). That sentence is PINNED (HIER-P2G): it is the most specific
    # trigger the agent has, so it is never dropped for the budget and never
    # truncated — derived triggers give way first, then derived text.
    #
    # The exclusion names the ADJACENT sibling. A description that itself
    # points at a sibling ("Do not use for placement (use Capacity Manager)")
    # has named its neighbour, and that sibling wins outright. Otherwise the
    # one whose vocabulary — name, description, policy domains, skills — most
    # overlaps this agent's while still owning topics this agent does not: the
    # neighbour a caller could confuse with it. Ranking on foreign topics alone
    # made every agent exclude the single topic-richest sibling, which is not a
    # routing signal but a standing bias. With no such sibling it names one of a
    # different type, and with no sibling at all it points at the general-purpose
    # agent — so every description carries exactly one exclusion by construction.
    # The description's own "Do not use …" sentence is not repeated: the
    # rendered exclusion carries the sibling's subagent_type key, which is what
    # the Agent tool needs.
    #
    # Bounded at MAX_CHARS. The exclusion is built first and always kept whole;
    # derived triggers are dropped from the least specific end until the text
    # fits, then the last derived part is truncated; the pinned sentence stays.
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
      # The seed's own routing sentence, and the exclusion sentence it may
      # also carry (which names the sibling — see #named_sibling_rank).
      ROUTING_SENTENCE = /\AUse (?:this agent )?when\b/i
      EXCLUSION_SENTENCE = /\ADo not use\b/i

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
        parts = derived_triggers(agent, skills, domains)
        pinned = routing_sentence(agent.description)
        parts = [ fallback_trigger(agent) ] if parts.empty? && pinned.nil?

        fit_triggers(parts, budget, pinned: pinned)
      end

      # Least specific LAST, because #fit_triggers drops from the end.
      def derived_triggers(agent, skills, domains)
        parts = []
        parts.concat(domains.map { |domain| domain.to_s.tr("_", " ") })
        parts.concat(skills.first(MAX_SKILL_TRIGGERS).map { |skill| skill.name.to_s.strip })
        parts.concat(skills.flat_map { |skill| Array(skill.tags) }.map(&:to_s).uniq.first(MAX_TAG_TRIGGERS))
        parts = parts.map(&:strip).reject(&:blank?).uniq
        compact = compact_description(agent.description)
        parts << compact if compact.present?
        parts
      end

      # Fit the derived `parts` plus the `pinned` routing sentence into
      # `budget`: drop derived parts from the least specific end down to one,
      # then truncate that last derived part; with a pinned sentence, the last
      # derived part is dropped too when not even a truncated character of it
      # fits beside the sentence. The pinned sentence is never dropped or
      # truncated — if it alone exceeds the budget it is rendered whole regardless.
      def fit_triggers(parts, budget, pinned: nil)
        text = render_triggers(parts, pinned)
        while text.length > budget && parts.size > 1
          parts = parts[0...-1]
          text = render_triggers(parts, pinned)
        end
        return text if text.length <= budget || parts.empty?

        room = budget - TRIGGER_PREFIX.length - 1 - ELLIPSIS.length
        room -= pinned.length + 1 if pinned
        return pinned if pinned && room < 1

        room = 1 if room < 1
        render_triggers([ "#{parts.first[0, room]}#{ELLIPSIS}" ], pinned)
      end

      def render_triggers(parts, pinned = nil)
        derived = parts.any? ? "#{TRIGGER_PREFIX}#{parts.join('; ')}." : nil
        [ derived, pinned ].compact.join(" ")
      end

      def sentences_of(description)
        text = description.to_s.strip.gsub(/\s+/, " ")
        return [] if text.empty?

        text.split(/(?<=[.!?])\s+/).map(&:strip).reject(&:blank?)
      end

      # The seed's own "Use when …" sentence(s), verbatim, each closed with a
      # period; nil when the description carries none.
      def routing_sentence(description)
        own = sentences_of(description).select { |sentence| sentence.match?(ROUTING_SENTENCE) }
        return nil if own.empty?

        own.map { |sentence| sentence.match?(/[.!?]\z/) ? sentence : "#{sentence}." }.join(" ")
      end

      # The first sentence that is neither the routing sentence (pinned
      # separately, never doubled) nor the description's own exclusion.
      def compact_description(description)
        first = sentences_of(description).find do |sentence|
          !sentence.match?(ROUTING_SENTENCE) && !sentence.match?(EXCLUSION_SENTENCE)
        end
        return nil if first.nil?

        first = first.sub(/[.!?]+\z/, "")
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
      # Ranking: a sibling the agent's own description NAMES first (in the
      # order named — "use Capacity Manager" is the seed author's answer, and
      # it outranks any score; HIER-P2G), then shared-vocabulary SIMILARITY
      # desc (Jaccard, not a raw overlap count — see #vocabulary_similarity),
      # then foreign-topic count desc, then key. Siblings with no shared
      # vocabulary rank after every sibling that has some; an unnamed sibling
      # owning no foreign topic is not a candidate. With no topic signal
      # anywhere, a sibling of a different agent type, else the first sibling.
      def adjacent_sibling(agent, skills, domains, siblings)
        mine_topics = topics_of(agent, skills, domains)
        mine_vocab = vocabulary_of(agent, skills, domains)
        named = named_sibling_rank(agent, siblings)

        scored = siblings.filter_map do |sibling|
          foreign = sibling_topics(sibling) - mine_topics
          rank = named[sibling[:key].to_s]
          next if foreign.empty? && rank.nil?

          shared = vocabulary_similarity(mine_vocab, sibling_vocabulary(sibling))
          [ sibling, foreign, shared, rank ]
        end.sort_by { |(sibling, foreign, shared, rank)| [ rank || Float::INFINITY, -shared, -foreign.size, sibling[:key].to_s ] }
        return scored.first.first(2) if scored.any?

        ordered = siblings.sort_by { |sibling| sibling[:key].to_s }
        fallback = ordered.find { |sibling| sibling[:agent_type].to_s != agent.agent_type.to_s } || ordered.first
        fallback ? [ fallback, [] ] : [ nil, [] ]
      end

      # Adjacency score: shared vocabulary NORMALISED by the union (Jaccard),
      # never the raw intersection size. A HUB agent (System Concierge binds
      # nearly every system skill, so its vocabulary is the union of everyone
      # else's) shares more words with every specialist by sheer size — a raw
      # count made it the exclusion for six unrelated agents, which is the same
      # standing bias the foreign-topic ranking had, one level down. Dividing
      # by the union charges a sibling for the vocabulary it does NOT share, so
      # the winner is the genuinely adjacent neighbour. Ties still break on
      # foreign-topic count then key, so the render stays deterministic.
      def vocabulary_similarity(mine, theirs)
        union = (mine | theirs).size
        return 0.0 if union.zero?

        (mine & theirs).size.to_f / union
      end

      # key => position of the sibling's NAME in the agent's own description,
      # for the siblings it names ("… (use Capacity Manager)"). Whole-name,
      # case-insensitive; blank names never match.
      def named_sibling_rank(agent, siblings)
        text = agent.description.to_s.downcase
        return {} if text.empty?

        siblings.each_with_object({}) do |sibling, out|
          name = sibling[:name].to_s.strip.downcase
          next if name.empty?

          position = text.index(name)
          out[sibling[:key].to_s] = position if position
        end
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
