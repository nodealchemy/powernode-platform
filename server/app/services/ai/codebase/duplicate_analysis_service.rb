# frozen_string_literal: true

require "shellwords"
require "json"
require "fileutils"
require "tmpdir"

module Ai
  module Codebase
    # Copy-paste / clone detection via jscpd (token-based, fast, deterministic)
    # + AI triage. Replaces the removed embedding-based DuplicateDetectionService,
    # which was pathologically O(N^2) (a per-node filtered pgvector loop that
    # ran ~6h at 100% CPU). Same analyzer-detects + AI-judges pattern as
    # DeadCodeAnalysisService:
    #
    #   ① DETECT — jscpd over the scope(s) → clone groups (file:line spans + fragment)
    #   ② FILTER — drop trivial (line floor) + generated/vendored/test paths
    #   ③ TRIAGE — an LLM classifies each group:
    #              extract_candidate / acceptable / generated / coincidental (+ suggested action)
    #
    # Long-running (jscpd + LLM) → invoked from the worker via
    # /internal/codebase/analyze. Triage is best-effort (returns untriaged clones
    # if no LLM credential is configured).
    class DuplicateAnalysisService
      include LlmTriagePipeline

      DEFAULT_SCOPES = %w[frontend/src server/app worker/app].freeze
      MIN_TOKENS     = 50
      MIN_LINES      = 5
      MAX_GROUPS     = 200
      MAX_TRIAGE     = 120
      TRIAGE_BATCH   = 20
      CMD_BYTE_CAP   = 2_000_000

      TRIAGE_CATEGORIES = %w[extract_candidate acceptable generated coincidental].freeze
      IGNORE_GLOBS = "**/node_modules/**,**/dist/**,**/build/**,**/coverage/**,**/vendor/**,**/*.min.*,**/*.test.*,**/*.spec.*,**/*_spec.rb,**/*.d.ts".freeze

      def initialize(account:, base_path:)
        @account   = account
        @base_path = File.expand_path(base_path)
      end

      # @param scope_paths [Array<String>,nil] subdirs (rel to base_path); default frontend/src + server/app + worker/app
      # @param min_tokens [Integer] jscpd clone size floor (default 50)
      # @param triage [Boolean] run the LLM triage stage (default true)
      # @param model [String,nil] override the triage model
      def detect(scope_paths: nil, min_tokens: MIN_TOKENS, triage: true, model: nil)
        return { success: false, error: "base_path does not exist: #{@base_path}" } unless File.directory?(@base_path)

        scopes = (scope_paths.presence || DEFAULT_SCOPES)
                 .map { |s| File.join(@base_path, s) }.select { |d| File.directory?(d) }
        return { success: true, summary: { detected: 0, triage_status: "no scope" }, clones: [] } if scopes.empty?

        groups = run_jscpd(scopes, min_tokens).select { |g| g[:lines].to_i >= MIN_LINES }.first(MAX_GROUPS)

        triaged, status =
          if triage && groups.any?
            run_triage(groups.first(MAX_TRIAGE), model: model)
          else
            [groups, triage ? "no_clones" : "skipped"]
          end

        {
          success: true,
          summary: {
            detected: groups.size,
            triaged: triaged.count { |c| c[:triage] },
            extract_candidates: triaged.count { |c| c[:triage] == "extract_candidate" },
            triage_status: status
          },
          clones: triaged.sort_by { |c| TRIAGE_CATEGORIES.index(c[:triage]) || 99 }
        }
      end

      private

      # ── ① jscpd ──────────────────────────────────────────────────────────────

      def run_jscpd(scopes, min_tokens)
        out_dir = File.join(Dir.tmpdir, "jscpd-#{@account.id}")
        FileUtils.rm_rf(out_dir)
        FileUtils.mkdir_p(out_dir)

        scopes_arg = scopes.map { |s| Shellwords.escape(s) }.join(" ")
        run(
          "npx --yes jscpd #{scopes_arg} --min-tokens #{min_tokens.to_i} " \
          "--reporters json --output #{Shellwords.escape(out_dir)} " \
          "--ignore #{Shellwords.escape(IGNORE_GLOBS)} --silent"
        )

        report = File.join(out_dir, "jscpd-report.json")
        return [] unless File.exist?(report)

        data = JSON.parse(File.read(report)) rescue {}
        (data["duplicates"] || []).map do |d|
          {
            format: d["format"],
            lines: d["lines"],
            a: clone_loc(d["firstFile"]),
            b: clone_loc(d["secondFile"]),
            fragment: d["fragment"].to_s[0, 500]
          }
        end
      ensure
        FileUtils.rm_rf(File.join(Dir.tmpdir, "jscpd-#{@account.id}")) rescue nil
      end

      def clone_loc(f)
        return {} unless f.is_a?(Hash)

        { file: f["name"].to_s.sub("#{@base_path}/", ""), start: f["start"], end: f["end"] }
      end

      # ── ② AI triage (shared plumbing in LlmTriagePipeline) ───────────────────

      def triage_log_tag
        "DuplicateAnalysis"
      end

      def triage_batch(client, model, batch)
        listing = batch.each_with_index.map do |g, i|
          "##{i}  #{g[:lines]}-line #{g[:format]} clone:  #{g.dig(:a, :file)}:#{g.dig(:a, :start)}-#{g.dig(:a, :end)}  ==  #{g.dig(:b, :file)}:#{g.dig(:b, :start)}-#{g.dig(:b, :end)}\n" \
          "```\n#{g[:fragment]}\n```"
        end.join("\n\n")

        prompt = "Classify each code clone below. Reply with ONLY a JSON object (no prose, no markdown fences):\n" \
                 "{\"results\":[{\"index\":<int>,\"category\":\"#{TRIAGE_CATEGORIES.join('|')}\",\"reason\":\"<short>\",\"action\":\"<short suggested refactor, or 'none'>\"}]}\n\n" \
                 "Clones:\n#{listing}"

        resp = client.complete(
          messages: [{ role: "user", content: prompt }],
          model: model,
          system_prompt: triage_system_prompt,
          max_tokens: 2200,
          temperature: 0
        )

        by_index = extract_results(resp.content).index_by { |r| r["index"] }
        batch.each_with_index.map do |g, i|
          r = by_index[i] || {}
          g.merge(triage: r["category"], triage_reason: r["reason"], suggested_action: r["action"])
        end
      end

      def triage_system_prompt
        "You triage copy-paste code clones found by a token-based detector, judging refactor value. Classify each:\n" \
        "- extract_candidate: substantive duplicated logic worth extracting into a shared function/module — coupling them is a net win\n" \
        "- acceptable: intentional/idiomatic duplication not worth coupling (independent configs, tiny boilerplate, parallel-but-separate code)\n" \
        "- generated: machine-generated/scaffolded code where duplication is expected\n" \
        "- coincidental: superficially similar tokens but semantically unrelated\n" \
        "Reserve extract_candidate for cases where the shared logic is real and DRYing it genuinely reduces maintenance risk."
      end
    end
  end
end
