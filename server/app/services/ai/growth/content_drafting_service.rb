# frozen_string_literal: true

module Ai
  module Growth
    class ContentDraftingError < StandardError; end

    # Content drafting (D1): generates a reviewable Ai::ContentDraft targeting
    # ONE connected data source, from knowledge-base content + a brand-voice
    # profile, via the platform LLM. The model/provider/credential are always
    # AGENT-RESOLVED (Ai::Agent#resolved_model/#resolved_provider/#resolved_credential)
    # — never a hardcoded model name.
    #
    # Sits beside Ai::Growth::CrossPostService (G2): that service fans an
    # ALREADY-WRITTEN piece of content out to N providers' publish endpoints;
    # this one WRITES the content in the first place, for exactly one provider,
    # and never dispatches anything — the result is persisted with
    # status "draft" for a human (or D2's approval-gated pipeline) to review.
    #
    # Provider constraints (max length / thread-splitting) are read GENERICALLY
    # off the target's publish endpoint metadata (see
    # Ai::DataSources::TemplateLibrary's "max_content_length"/"thread_splittable"
    # keys) — a new provider template needs zero code change here.
    # FALLBACK_CONSTRAINTS only backstops sources installed before that metadata
    # existed; the endpoint's own metadata always wins when present.
    class ContentDraftingService
      SETTINGS_KEY = "content_drafting"
      DEFAULT_TOP_K = 5
      # Keyword (Postgres full-text) search needs no embedding provider, so
      # drafting stays deterministic/network-free by default; callers with a
      # configured embedding backend can opt into "hybrid"/"vector"/"graph".
      DEFAULT_SEARCH_MODE = "keyword"
      # Worst-case width of a " (NN/NN)" thread-position suffix (up to 99
      # segments), reserved from each segment's budget BEFORE greedy word-wrap
      # so appending the suffix afterward never pushes a segment over the limit.
      SUFFIX_RESERVE = 8

      FALLBACK_CONSTRAINTS = {
        "x_com" => { "max_content_length" => 280, "thread_splittable" => true },
        "bluesky" => { "max_content_length" => 300, "thread_splittable" => true },
        "mastodon" => { "max_content_length" => 500, "thread_splittable" => true },
        "linkedin" => { "max_content_length" => 3000, "thread_splittable" => false },
        "reddit" => { "max_content_length" => 40_000, "thread_splittable" => false }
      }.freeze

      # @param account [Account] tenant scope
      # @param user [User, nil] attributed as the draft's created_by
      # @param agent [Ai::Agent, nil] the content_generator agent to draft
      #   WITH (its resolved model/provider/credential does the generation).
      #   Defaults to the account's first active content_generator agent.
      def initialize(account:, user: nil, agent: nil)
        @account = account
        @user = user
        @agent = agent
      end

      # @param data_source_id [String] slug or id of the target connected provider
      # @param brief [String] the topic/goal to draft content about
      # @param knowledge_base_id [String, nil] specific KB (defaults to the
      #   account's most recently created active knowledge base, if any)
      # @param brand_voice [Hash, nil] tone/voice profile; defaults to
      #   account.settings["content_drafting"]["brand_voice"] (or {})
      # @param search_mode [String] KB retrieval mode (see DEFAULT_SEARCH_MODE)
      # @param top_k [Integer] max KB chunks to retrieve as context
      # @return [Ai::ContentDraft] the persisted, reviewable draft
      def draft(data_source_id:, brief:, knowledge_base_id: nil, brand_voice: nil,
                search_mode: DEFAULT_SEARCH_MODE, top_k: DEFAULT_TOP_K)
        raise ArgumentError, "brief is required" if brief.blank?

        data_source = resolve_data_source(data_source_id)
        endpoint = publish_endpoint(data_source)
        constraints = provider_constraints(data_source, endpoint)
        voice = resolve_brand_voice(brand_voice)
        knowledge_base, kb_context, chunk_ids = retrieve_kb_context(knowledge_base_id, brief, search_mode, top_k)
        drafting_agent = resolve_agent

        raw_text = generate_text(agent: drafting_agent, brief: brief, brand_voice: voice,
                                  kb_context: kb_context, constraints: constraints)
        content, segments, truncated = shape_for_provider(raw_text, constraints)

        Ai::ContentDraft.create!(
          account: @account,
          data_source: data_source,
          knowledge_base: knowledge_base,
          requesting_agent: drafting_agent,
          created_by: @user,
          status: "draft",
          source_type: data_source.source_type,
          content: content,
          segments: segments,
          brand_voice: voice,
          metadata: {
            "brief" => brief,
            "kb_chunk_ids" => chunk_ids,
            "raw_char_count" => raw_text.to_s.length,
            "max_content_length" => constraints[:max_content_length],
            "truncated" => truncated
          }.compact
        )
      end

      private

      # Excludes retired (is_active: false) sources, and raises when the
      # source is otherwise misconfigured (no publish endpoint, or requires
      # auth but has no attached credential) — there is no point drafting
      # content for a provider that can never receive it.
      def resolve_data_source(identifier)
        data_source = Ai::DataSource.for_account(@account).active.find_by(slug: identifier) ||
          Ai::DataSource.for_account(@account).active.find_by(id: identifier)
        raise ContentDraftingError, "data source not found or retired: #{identifier}" unless data_source

        if data_source.requires_auth? && data_source.active_credential.nil?
          raise ContentDraftingError, "data source '#{data_source.slug}' is misconfigured: requires auth but has no active credential"
        end

        data_source
      end

      def publish_endpoint(data_source)
        endpoint = data_source.endpoints.detect(&:write_endpoint?)
        raise ContentDraftingError, "data source '#{data_source.slug}' is misconfigured: no publish endpoint configured" unless endpoint

        endpoint
      end

      # Primary path: the endpoint's OWN metadata (see TemplateLibrary) — zero
      # code change for a new provider. Falls back to FALLBACK_CONSTRAINTS
      # (keyed by source_type) only for sources installed before that metadata
      # existed. Absent both, there is no length limit (no splitting/truncation).
      def provider_constraints(data_source, endpoint)
        meta = endpoint.metadata.is_a?(Hash) ? endpoint.metadata.stringify_keys : {}
        fallback = FALLBACK_CONSTRAINTS[data_source.source_type] || {}

        max_length = meta["max_content_length"] || fallback["max_content_length"]
        splittable = meta.key?("thread_splittable") ? meta["thread_splittable"] : fallback["thread_splittable"]

        {
          max_content_length: max_length&.to_i,
          thread_splittable: ActiveModel::Type::Boolean.new.cast(splittable)
        }
      end

      def resolve_brand_voice(explicit)
        return explicit.to_h.stringify_keys if explicit.present?

        (@account.settings&.dig(SETTINGS_KEY, "brand_voice") || {}).to_h
      end

      def resolve_knowledge_base(kb_id)
        if kb_id.present?
          @account.ai_knowledge_bases.active.find_by(id: kb_id)
        else
          @account.ai_knowledge_bases.active.order(created_at: :desc).first
        end
      end

      # Returns [knowledge_base_or_nil, joined_chunk_text, chunk_ids] — drafting
      # proceeds even with no KB (context falls back to the brief alone) rather
      # than hard-failing an account with nothing indexed yet.
      def retrieve_kb_context(kb_id, brief, search_mode, top_k)
        knowledge_base = resolve_knowledge_base(kb_id)
        return [knowledge_base, "", []] unless knowledge_base

        result = Ai::Rag::HybridSearchService.new(@account).search(
          query: brief, mode: search_mode, top_k: top_k, knowledge_base_id: knowledge_base.id
        )
        chunks = result[:results] || []
        [knowledge_base, chunks.map { |c| c[:content] }.join("\n\n"), chunks.map { |c| c[:id] }]
      end

      def resolve_agent
        return @agent if @agent

        @account.ai_agents.active.by_type("content_generator").order(:created_at).first ||
          raise(ContentDraftingError, "no active content_generator agent available to draft with")
      end

      def generate_text(agent:, brief:, brand_voice:, kb_context:, constraints:)
        provider = agent.using_account(@account).resolved_provider
        credential = agent.resolved_credential
        model = agent.resolved_model
        if provider.nil? || credential.nil? || model.nil?
          raise ContentDraftingError, "agent '#{agent.name}' has no resolvable model/provider/credential"
        end

        client = Ai::Llm::Client.new(provider: provider, credential: credential)
        response = client.complete(
          messages: build_messages(brief, brand_voice, kb_context, constraints),
          model: model,
          temperature: 0.7
        )
        raise ContentDraftingError, "content generation failed (#{response.finish_reason})" unless response.success?

        response.content.to_s.strip
      end

      def build_messages(brief, brand_voice, kb_context, constraints)
        limit_note = if constraints[:max_content_length]
          note = "Keep the post under #{constraints[:max_content_length]} characters."
          note += " If the topic needs more room, that is fine — it will be split into a numbered thread." if constraints[:thread_splittable]
          note
        else
          "No strict character limit."
        end

        system_prompt = <<~PROMPT
          You are drafting social content in this brand voice: #{brand_voice.presence || 'neutral, clear, professional'}.
          #{limit_note}
          Base the post on this knowledge base context (may be empty):
          #{kb_context.presence || '(no knowledge base context available)'}
          Return ONLY the post text — no preamble, quotes, or markdown.
        PROMPT

        [
          { role: "system", content: system_prompt },
          { role: "user", content: brief }
        ]
      end

      # Returns [content, segments, truncated] where segments is the ordered
      # array persisted on the draft ([content] when not split).
      def shape_for_provider(text, constraints)
        max_length = constraints[:max_content_length]
        return [text, [text], false] if max_length.nil? || text.length <= max_length

        if constraints[:thread_splittable]
          segments = split_into_thread(text, max_length)
          [segments.first, segments, false]
        else
          truncated = "#{text[0, max_length - 1]}…"
          [truncated, [truncated], true]
        end
      end

      def split_into_thread(text, max_length)
        effective_width = [max_length - SUFFIX_RESERVE, 1].max
        raw_segments = greedy_word_wrap(text, effective_width)
        return raw_segments if raw_segments.size <= 1

        total = raw_segments.size
        raw_segments.each_with_index.map { |segment, i| "#{segment} (#{i + 1}/#{total})" }
      end

      # Greedy word-wrap: packs whole words into each segment up to +width+;
      # a single word longer than +width+ is hard-broken (rare, but keeps the
      # algorithm total — no unbounded segment is ever produced).
      def greedy_word_wrap(text, width)
        segments = []
        current = +""

        text.to_s.split(/\s+/).each do |word|
          if word.length > width
            segments << current unless current.empty?
            current = ""
            word.scan(/.{1,#{width}}/).each { |chunk| segments << chunk }
            next
          end

          candidate = current.empty? ? word : "#{current} #{word}"
          if candidate.length > width
            segments << current
            current = word
          else
            current = candidate
          end
        end

        segments << current unless current.empty?
        segments
      end
    end
  end
end
