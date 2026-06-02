# frozen_string_literal: true

require "shellwords"

module Ai
  module Codebase
    # Analyzer-driven dead-code detection with AI triage.
    #
    # Replaces the graph-based heuristic (DeadCodeDetectionService), which was
    # blind in this codebase because the knowledge graph has no call/reference
    # edges — so it could only ever surface false positives. Pipeline:
    #
    #   ① DETECT — language-native analyzers run at base_path:
    #              ts-prune (frontend TS unused exports) + debride (Ruby uncalled methods)
    #   ② VERIFY — grep each candidate for ZERO external references (mechanical
    #              false-positive filter; conservative — under-reports rather than
    #              over-reports). This is the pass that took ts-prune's 2,500 → 211.
    #   ③ TRIAGE — an LLM classifies each verified candidate:
    #              real_dead | public_api | dynamic_dispatch | test_only | uncertain
    #
    # Long-running (shells out + LLM calls) → invoked from the worker via
    # /internal/codebase/analyze. Triage is best-effort: with no LLM credential
    # configured, verified candidates are returned untriaged.
    class DeadCodeAnalysisService
      MAX_CANDIDATES = 400      # cap analyzer output we bother to verify
      MAX_TRIAGE     = 200      # cap verified candidates sent to the LLM
      TRIAGE_BATCH   = 25       # candidates per LLM call
      CMD_BYTE_CAP   = 4_000_000

      TRIAGE_CATEGORIES = %w[real_dead public_api dynamic_dispatch test_only uncertain].freeze
      VERIFY_ROOTS      = %w[frontend/src server/app worker/app extensions].freeze

      def initialize(account:, base_path:)
        @account   = account
        @base_path = File.expand_path(base_path)
      end

      # @param languages [Array<String>] subset of %w[typescript ruby]
      # @param triage [Boolean] run the LLM triage stage (default true)
      # @param model [String, nil] override the triage model
      # @return [Hash] success/summary/candidates
      def detect(languages: %w[typescript ruby], triage: true, model: nil)
        return { success: false, error: "base_path does not exist: #{@base_path}" } unless File.directory?(@base_path)

        candidates = []
        candidates.concat(ts_prune_candidates) if languages.include?("typescript")
        candidates.concat(debride_candidates)  if languages.include?("ruby")

        verified = verify(candidates.first(MAX_CANDIDATES))
        triaged, triage_status =
          if triage && verified.any?
            run_triage(verified.first(MAX_TRIAGE), model: model)
          else
            [verified, triage ? "no_candidates" : "skipped"]
          end

        {
          success: true,
          summary: {
            languages: languages,
            detected: candidates.size,
            verified: verified.size,
            triaged: triaged.count { |c| c[:triage] },
            likely_dead: triaged.count { |c| c[:triage] == "real_dead" },
            triage_status: triage_status
          },
          candidates: triaged.sort_by { |c| TRIAGE_CATEGORIES.index(c[:triage]) || 99 }
        }
      end

      private

      # ── ① analyzers (shell-out, mirrors StaticAnalysisService) ──────────────

      # ts-prune over the frontend; drops barrel re-exports + default exports +
      # internally-used exports (the known false-positive classes).
      def ts_prune_candidates
        fe = File.join(@base_path, "frontend")
        return [] unless File.directory?(fe) && File.exist?(File.join(fe, "tsconfig.json"))

        out = run("cd #{Shellwords.escape(fe)} && npx --yes ts-prune 2>/dev/null")
        return [] if out.blank?

        out.each_line.filter_map do |line|
          next if line.include?("(used in module)")
          m = line.match(/\A(\S+):(\d+) - (\S+)/)
          next unless m

          file, ln, sym = m[1], m[2].to_i, m[3]
          next if sym == "default" || file =~ %r{/index\.tsx?\z}

          { language: "typescript", kind: "export", symbol: sym, file: "frontend/#{file}", line: ln }
        end
      end

      # debride --rails over server/app; uncalled Ruby methods (high FP rate —
      # the verify + triage stages do the filtering).
      def debride_candidates
        srv = File.join(@base_path, "server")
        return [] unless File.directory?(File.join(srv, "app")) && File.exist?(File.join(srv, "Gemfile"))

        out = run("cd #{Shellwords.escape(srv)} && bundle exec debride --rails app/ 2>/dev/null")
        return [] if out.blank?

        out.each_line.filter_map do |line|
          m = line.match(/\A\s+([A-Za-z_][A-Za-z0-9_?!]*)\s+(app\/\S+\.rb):(\d+)/)
          next unless m

          { language: "ruby", kind: "method", symbol: m[1], file: "server/#{m[2]}", line: m[3].to_i }
        end
      end

      # ── ② verification (mechanical false-positive filter) ───────────────────

      # Keep only candidates whose symbol is referenced in NO file other than its
      # own definition. Conservative by design: a common-named symbol matches many
      # files and is dropped (under-report > over-report).
      def verify(candidates)
        roots = VERIFY_ROOTS.map { |r| File.join(@base_path, r) }.select { |d| File.directory?(d) }
        return candidates if roots.empty?

        roots_arg = roots.map { |r| Shellwords.escape(r) }.join(" ")
        candidates.select do |c|
          files = run("grep -rwlI #{Shellwords.escape(c[:symbol])} #{roots_arg} 2>/dev/null").to_s
                    .split("\n").map { |f| f.sub("#{@base_path}/", "") }
          files.reject { |f| f == c[:file] }.empty?
        end
      end

      # ── ③ AI triage ─────────────────────────────────────────────────────────

      def run_triage(candidates, model:)
        client = Ai::Llm::Client.for_account(@account)
        resolved = model.presence || default_model(client)
        return [candidates, "skipped (no LLM credential)"] if client.nil? || resolved.blank?

        triaged = []
        candidates.each_slice(TRIAGE_BATCH) do |batch|
          triaged.concat(triage_batch(client, resolved, batch))
        rescue => e
          Rails.logger.warn "[DeadCodeAnalysis] triage batch failed: #{e.message}"
          triaged.concat(batch)
        end
        [triaged, "completed (#{resolved})"]
      end

      def triage_batch(client, model, batch)
        listing = batch.each_with_index
                       .map { |c, i| "#{i}: #{c[:language]} #{c[:kind]} `#{c[:symbol]}` — #{c[:file]}:#{c[:line]}" }
                       .join("\n")

        prompt = "Each candidate below is grep-verified to have ZERO references in the repo (an internal app). Classify each. Reply with ONLY a JSON object (no prose, no markdown fences):\n" \
                 "{\"results\":[{\"index\":<int>,\"category\":\"#{TRIAGE_CATEGORIES.join('|')}\",\"reason\":\"<short>\"}]}\n\n" \
                 "Candidates:\n#{listing}"

        # Plain completion + tolerant JSON extraction — portable across providers
        # and avoids the provider-specific structured-output (output_config) path,
        # which errors on the current Anthropic adapter.
        resp = client.complete(
          messages: [{ role: "user", content: prompt }],
          model: model,
          system_prompt: triage_system_prompt,
          max_tokens: 2000,
          temperature: 0
        )

        by_index = extract_results(resp.content).index_by { |r| r["index"] }
        batch.each_with_index.map do |c, i|
          r = by_index[i] || {}
          c.merge(triage: r["category"], triage_reason: r["reason"])
        end
      end

      # Robustly pull the {"results":[...]} array from an LLM text response,
      # tolerating markdown fences / surrounding prose.
      def extract_results(content)
        return [] if content.blank?

        text = content.to_s.gsub(/```(?:json)?/i, "")
        first = text.index("{")
        last  = text.rindex("}")
        return [] unless first && last && last > first

        parsed = JSON.parse(text[first..last]) rescue nil
        parsed.is_a?(Hash) ? Array(parsed["results"]) : []
      end

      def triage_system_prompt
        "You triage dead-code candidates for an INTERNAL application (NOT a published library). Each candidate has been GREP-VERIFIED to have ZERO references anywhere in the repository, outside its own definition. For an internal app a zero-reference symbol is dead BY DEFAULT — classify real_dead unless there is SPECIFIC evidence otherwise:\n" \
        "- real_dead: zero references and no specific reason to keep — safe to remove. THIS IS THE DEFAULT.\n" \
        "- public_api: a genuine external/plugin/framework boundary intentionally exposed to out-of-repo consumers. 'Exported' ALONE is NOT public_api when nothing references it — do not over-use this.\n" \
        "- dynamic_dispatch: invoked via send/metaprogramming/reflection/Rails associations/string keys (common for Ruby model + association methods).\n" \
        "- test_only: a helper/fixture used only by tests.\n" \
        "- uncertain: plausibly reached in a way grep can't see (lazy/dynamic import, string-keyed route component, conditional render).\n" \
        "Reserve the non-real_dead categories for specific evidence; do NOT default everything to public_api."
      end

      # ── helpers ─────────────────────────────────────────────────────────────

      def default_model(client)
        return nil unless client

        models = client.provider&.available_models rescue nil
        first = models.is_a?(Array) ? models.first : nil
        first.is_a?(Hash) ? (first["id"] || first["name"] || first[:id] || first[:name]) : first
      end

      def run(command)
        IO.popen(command, err: [:child, :out]) { |io| io.read(CMD_BYTE_CAP) }
      rescue Errno::ENOENT, Errno::EPIPE => e
        Rails.logger.warn "[DeadCodeAnalysis] command failed: #{e.message}"
        nil
      end
    end
  end
end
