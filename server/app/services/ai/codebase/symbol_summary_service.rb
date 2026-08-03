# frozen_string_literal: true

module Ai
  module Codebase
    # Rewrites the code index's embedded corpus into QUERY-SHAPED prose.
    #
    # Measured 2026-08-03 (docs/operations/code-index-retrieval-quality.md): retrieval
    # succeeds when a query shares distinctive vocabulary with the target and fails when
    # it does not — regardless of ranking. `emergency_halt!` documents itself as
    # "Coordinated emergency stop — halts ALL agentic activity"; the query "immediately
    # stop a runaway autonomous agent from taking any further action" shares only "stop"
    # and "agent" (one common, one ubiquitous here). The lexical arm cannot reach it and
    # the embedding model does not bridge it, so hybrid RRF did not close the gap either.
    #
    # No ranking change spans genuinely disjoint vocabulary. The corpus has to become the
    # same KIND of text as the query, which is what this service produces: one plain
    # sentence per symbol, phrased the way a developer would ASK for the code without
    # knowing its name, deliberately carrying synonyms the identifier itself lacks.
    #
    # The summary lands in properties["llm_summary"] and the node's vector is cleared so
    # the next embed pass picks it up. The display `description` is left alone — humans
    # reading results still get the signature.
    class SymbolSummaryService
      include LlmTriagePipeline

      # Symbols per LLM call. Each carries a body snippet, so this is the term that
      # decides prompt size: 20 * (~1.5k body + ~200 signature) stays well inside a
      # normal context while keeping the per-call overhead amortised.
      SUMMARY_BATCH = 20
      TRIAGE_BATCH  = SUMMARY_BATCH # LlmTriagePipeline contract
      CMD_BYTE_CAP  = 1_000_000     # LlmTriagePipeline contract (no shell-out here)

      # ONLY symbols with their own executable behaviour.
      #
      # `constant` (22% of the index) and `file` are excluded because their value and
      # path already ARE their meaning — summarising them spends money for no gain.
      #
      # `class` and `module` are excluded for a sharper reason, measured on a 414-node
      # pilot 2026-08-03. A container's summary necessarily describes everything it
      # contains, so it matches every term of any query aimed at any of its members —
      # while its own description stays ~30 chars and takes almost no length damping.
      # That combination is structurally unbeatable: summarising containers sent
      # `emergency_halt!` from rank 2 to off the list on its own identifier query, with
      # `module Autonomy` and `class KillSwitchService` taking the top slots. Removing
      # the module wrappers alone was not enough — the class nodes simply became the
      # decoys one level up.
      #
      # A container's retrieval value is its NAME, which the identifier already
      # supplies. Behaviour lives in methods, so that is what gets described.
      SUMMARIZABLE_TYPES = %w[method function interface type_definition].freeze

      BODY_MAX_LINES  = 40
      BODY_MAX_CHARS  = 1_500
      SUMMARY_MAX_CHARS = 400
      FILE_MAX_BYTES  = 2_000_000 # don't slurp a generated megafile for one snippet
      MAX_RETRIES     = 3

      attr_reader :account, :knowledge_base, :base_path, :stats

      def initialize(account:, knowledge_base:, base_path: nil, model: nil)
        @account = account
        @knowledge_base = knowledge_base
        @base_path = base_path && File.expand_path(base_path)
        @model = model
        @file_cache = {}
        @stats = { candidates: 0, summarized: 0, failures: 0, batches: 0, skipped_no_body: 0 }
      end

      # @param limit [Integer, nil] cap on symbols processed this run (nil = all pending)
      # @param entity_types [Array<String>] override SUMMARIZABLE_TYPES
      # @param dry_run [Boolean] count and price the work without calling the LLM
      # @param pace [Float] seconds to sleep between batches (provider rate-limit relief)
      # @return [Hash] stats
      def summarize!(limit: nil, entity_types: SUMMARIZABLE_TYPES, dry_run: false, pace: 0.0)
        scope = pending_scope(entity_types)
        total = scope.count
        @stats[:candidates] = limit ? [ limit, total ].min : total
        @stats[:pending_total] = total

        return @stats.merge(dry_run: true, estimated_calls: estimated_calls) if dry_run
        return @stats if @stats[:candidates].zero?

        client = Ai::Llm::Client.for_account(@account)
        resolved = @model.presence || default_model(client)
        if client.nil? || resolved.blank?
          @stats[:status] = "skipped (no LLM credential)"
          return @stats
        end
        @stats[:model] = resolved

        Rails.logger.info "[SymbolSummary] Summarising #{@stats[:candidates]} of #{total} " \
                          "pending symbols in batches of #{SUMMARY_BATCH} (#{resolved})"

        processed = 0
        # Ordered by id so a run that dies mid-way resumes deterministically; the scope
        # itself shrinks as summaries land, so there is no cursor to carry.
        scope.find_in_batches(batch_size: SUMMARY_BATCH) do |nodes|
          nodes = nodes.first(@stats[:candidates] - processed) if limit
          break if nodes.empty?

          summarize_batch(client, resolved, nodes)
          processed += nodes.size
          @stats[:batches] += 1
          break if limit && processed >= @stats[:candidates]

          sleep(pace) if pace.positive?
        end

        log_outcome
        @stats
      end

      # Apply summaries produced OUTSIDE the metered platform LLM — flat-rate CLI
      # subagents (Claude Code, Grok, Codex, …) generating them and handing back
      # records. Same write path as summarize!, different producer, no provider spend.
      #
      # Kept deliberately separate from summarize! so the two cost models never mix:
      # per flatrate-cli-vs-metered-platform-loops, a flat-rate producer should be run
      # aggressively while a metered one needs budget guards.
      #
      # @param records [Array<Hash>] {"name" => qualified_name, "summary" => text}
      # @param source [String] recorded as llm_summary_model for provenance
      # @return [Hash] stats
      def import!(records, source:, dry_run: false)
        @stats[:candidates] = records.size
        return @stats.merge(dry_run: true) if dry_run

        records.each do |record|
          name    = record["name"].presence || record[:name].presence
          summary = (record["summary"] || record[:summary]).to_s.strip
          if name.blank? || summary.blank?
            @stats[:failures] += 1
            next
          end

          node = knowledge_base.knowledge_graph_nodes
                               .where(account: account, name: name, node_type: "code_entity", status: "active")
                               .first
          if node.nil?
            # A stale name means the producer worked from a different checkout than the
            # index — counted, because silently dropping these would look like success.
            @stats[:missing] = @stats.fetch(:missing, 0) + 1
            next
          end

          apply_summary!(node, summary.first(SUMMARY_MAX_CHARS), source)
          @stats[:summarized] += 1
        end

        log_outcome
        @stats
      end

      private

      # Nodes that are summarisable and do not yet carry a summary. `->>` yields NULL
      # both when the key is absent and when its value is JSON null, so this covers
      # never-summarised and explicitly-cleared alike.
      def pending_scope(entity_types)
        knowledge_base.knowledge_graph_nodes
                      .where(account: account, node_type: "code_entity", status: "active")
                      .where(entity_type: entity_types)
                      .where("properties->>'llm_summary' IS NULL OR properties->>'llm_summary' = ''")
      end

      def estimated_calls
        (@stats[:candidates].to_f / SUMMARY_BATCH).ceil
      end

      def summarize_batch(client, model, nodes)
        results = with_retries { request_summaries(client, model, nodes) }
        by_index = results.index_by { |r| r["index"].to_i }

        nodes.each_with_index do |node, i|
          summary = by_index[i]&.dig("summary").to_s.strip
          if summary.blank?
            @stats[:failures] += 1
            next
          end
          apply_summary!(node, summary.first(SUMMARY_MAX_CHARS), model)
          @stats[:summarized] += 1
        end
      rescue => e
        # Best-effort per batch: one bad batch must not abort a 60k-node run. Failures
        # are COUNTED, not just warned — the 2026-08-02 embed phase silently completed
        # at 8% because nothing above warn level tracked them.
        @stats[:failures] += nodes.size
        Rails.logger.warn "[SymbolSummary] batch of #{nodes.size} failed: #{e.class}: #{e.message}"
      end

      def with_retries
        attempts = 0
        begin
          attempts += 1
          yield
        rescue => e
          raise if attempts >= MAX_RETRIES

          sleep(2**attempts * 0.5)
          Rails.logger.debug "[SymbolSummary] retry #{attempts} after #{e.class}: #{e.message}"
          retry
        end
      end

      def request_summaries(client, model, nodes)
        listing = nodes.each_with_index.map { |node, i| symbol_listing(node, i) }.join("\n\n")

        resp = client.complete(
          messages: [ { role: "user", content: user_prompt(listing) } ],
          model: model,
          system_prompt: system_prompt,
          max_tokens: 4000,
          temperature: 0
        )
        extract_results(resp.content)
      end

      def user_prompt(listing)
        "Summarise each symbol below. Reply with ONLY a JSON object (no prose, no markdown fences):\n" \
        "{\"results\":[{\"index\":<int>,\"summary\":\"<one sentence>\"}]}\n\n" \
        "Symbols:\n#{listing}"
      end

      # The retrieval goal is explicit here: the summary is the text a SEARCH will be
      # matched against, so it must read like the question, not like the signature.
      def system_prompt
        "You write one-sentence search descriptions for code symbols. Each will be embedded " \
        "and matched against natural-language questions from developers who do NOT know the " \
        "symbol's name.\n" \
        "Rules:\n" \
        "- Describe what the code DOES and WHEN someone would reach for it — never restate the signature.\n" \
        "- Write the sentence the way a developer would ASK for this code (\"stops all running agents " \
        "immediately\", not \"emergency halt method\").\n" \
        "- Include obvious synonyms a searcher might use instead of the identifier's own words.\n" \
        "- Plain language. No markdown, no identifier back-ticks, no 'This method...' preamble.\n" \
        "- One sentence, under 40 words.\n" \
        "- If the body is too trivial or opaque to describe, summarise from the name and signature anyway."
      end

      def symbol_listing(node, index)
        props = node.properties || {}
        header = [
          "#{index}: #{props['kind'] || node.entity_type} #{node.name}",
          props["parent"].presence && "in #{props['parent']}",
          props["params"].presence && "params #{props['params']}",
          props["return_type"].presence && "returns #{props['return_type']}"
        ].compact_blank.join(" — ")

        parts = [ header ]
        parts << "doc: #{props['doc']}" if props["doc"].present?
        body = body_snippet(props)
        if body.present?
          parts << "body:\n#{body}"
        else
          @stats[:skipped_no_body] += 1
        end
        parts.join("\n")
      end

      # The body is the only place behavioural meaning exists for the 61% of symbols
      # that carry no doc comment — those are exactly the ones retrieval loses today.
      def body_snippet(props)
        return nil if base_path.blank?

        rel   = props["file_path"].presence
        start = props["line_start"].to_i
        return nil if rel.blank? || start <= 0

        lines = file_lines(rel)
        return nil if lines.blank?

        # Inclusive line numbers: start..start+BODY_MAX_LINES-1 is BODY_MAX_LINES lines.
        last_allowed = start + BODY_MAX_LINES - 1
        finish = props["line_end"].to_i
        finish = last_allowed if finish <= start
        finish = [ finish, last_allowed ].min

        # properties line numbers are 1-indexed; Array is 0-indexed.
        lines[(start - 1)...finish]&.join.to_s.first(BODY_MAX_CHARS).presence
      end

      def file_lines(relative)
        return @file_cache[relative] if @file_cache.key?(relative)

        # Bounded memo: symbols arrive id-ordered, which clusters by file, so a tiny
        # cache removes almost all re-reads without letting the map grow unbounded.
        @file_cache.clear if @file_cache.size > 32

        full = File.expand_path(File.join(base_path, relative))
        @file_cache[relative] =
          if full.start_with?(base_path) && File.file?(full) && File.size(full) <= FILE_MAX_BYTES
            File.readlines(full, encoding: "utf-8")
          end
      rescue SystemCallError, ArgumentError => e
        Rails.logger.debug "[SymbolSummary] unreadable #{relative}: #{e.message}"
        @file_cache[relative] = nil
      end

      # Clearing the vector is what actually puts the summary into search — the embed
      # phase only ever selects `embedding: nil`, so a summary written without this
      # would sit in properties and never reach the index.
      def apply_summary!(node, summary, model)
        node.update!(
          properties: node.properties.merge(
            "llm_summary" => summary,
            "llm_summary_model" => model,
            "llm_summary_at" => Time.current.iso8601
          ),
          embedding: nil
        )
      end

      def log_outcome
        if @stats[:failures].positive?
          Rails.logger.error "[SymbolSummary] Summarised #{@stats[:summarized]}/#{@stats[:candidates]} — " \
                             "#{@stats[:failures]} FAILED; re-run to retry (the scope skips finished nodes)"
        else
          Rails.logger.info "[SymbolSummary] Summarised #{@stats[:summarized]}/#{@stats[:candidates]} symbols"
        end
      end
    end
  end
end
