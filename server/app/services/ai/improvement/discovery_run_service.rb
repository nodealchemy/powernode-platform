# frozen_string_literal: true

module Ai
  module Improvement
    # D1 — THE DISCOVERY CLOCK. D1b — WHERE ITS LINTERS RUN.
    #
    # The audit's finding (2026-09-10, §6.2): "Improvement discovery — Scheduled:
    # No". `platform.discover_improvements` returns GUIDANCE TEXT telling a caller
    # which analyzers to run (`improvement_tool.rb:163-183`); no cron references it
    # or the code-analysis verbs. So every code-quality offer on this platform was
    # filed by a human-driven session. This service is the analyzer that verb
    # only describes.
    #
    # ── THIS PROCESS NEVER RUNS A REPOSITORY'S CODE (D1b) ───────────────────────
    # A linter executes code from the directory it runs in: a Gemfile, a
    # .rubocop.yml `require:`, an eslint config. D1 ran the linters here, in the
    # Rails process, against a working copy fenced by an operator root. D1b
    # deleted that path. The linters run where the repository's own bundle is
    # installed, through the behaviour provider registered under EXECUTOR_KEY:
    #
    #   dispatch!(account:, repositories:) -> {
    #     status: "dispatched" | "skipped" | "failed", reason:, run_ref:,
    #     repositories: [{ id:, status: "dispatched" | "skipped", reason: }] }
    #
    # The provider hands each repository's RAW linter output back through
    # #ingest!, which parses it here with the parser the MCP verb uses
    # (`StaticAnalysisService.parse_output`). So core decides what a finding is,
    # and files it. Core names no extension.
    #
    # With no provider registered (core mode) nothing runs, and every unit says
    # so: `no_discovery_executor`. Core cannot run a repository's code safely,
    # so it does not claim to have looked.
    #
    # ── WHAT IT ANALYSES, AND WHAT IT DELIBERATELY DOES NOT ─────────────────────
    # The linters (rubocop/tsc/eslint) are the only analyzers in the tree that
    # produce `{file, line, severity, message, rule}` rows mechanically. The
    # other three the audit's remedy names are NOT wired here, on purpose:
    #
    #   * `code_dead_code` (`code_analysis_tool.rb:186`) and `code_find_duplicates`
    #     (`:217`) do not analyse anything — they dispatch to the worker and return
    #     a fixed `{success: true, status: "enqueued"}`. That IS the audit's own
    #     §4.2 defect for those two verbs. Calling them from here would add two
    #     analyzer names to a run summary and zero findings to the offer queue.
    #   * `scripts/pattern-validation.sh` emits human-formatted PASS/FAIL lines
    #     with no file:line, so it cannot be turned into fingerprinted offers
    #     without a parser that would be the least reliable part of this seam.
    #
    # `ANALYZERS` is the registry those three join once they can hand back a
    # finding with a file, a line and a rule. The gap is named, not hidden.
    #
    # ── A LINTER THAT DID NOT RUN IS NOT A CLEAN SWEEP ──────────────────────────
    # A linter summary carries a status. Only `completed` and `clean` mean the
    # code was inspected; `unavailable`, `timeout`, `no_gemfile`, `no_output`,
    # `parse_error` and the rest did not, and must never read as zero findings.
    # The per-linter status stays in the run summary, and `analyzers_degraded`
    # lists every one that did not measure.
    #
    # ── GATES ───────────────────────────────────────────────────────────────────
    #   1. Account kill switch (`ai_suspended?`) — same predicate the other
    #      internal crons use.
    #   2. Environment ceiling. The account's DEFAULT environment
    #      (`Ai::Environment.default_for`) must sit at or below a SiteSetting tier
    #      ceiling, default 0 — dev and ci only. `ai_ralph_loops` carries no
    #      `environment_id`, so the account's default plane is the anchor.
    #   3. A registered executor. Its own gates (the account's own runner pool,
    #      one run per account at a time) are its business, and it answers each
    #      refusal with a reason.
    #   4. A per-repository offer cap, so a first run against a repo with
    #      thousands of offences files a bounded number of the most severe.
    #
    # #ingest! re-checks 1 and 2: a result arrives after its dispatch, and a kill
    # switch thrown in between must stop the filing.
    #
    # Filing goes through `Ai::Tools::ImprovementTool` `create_improvement`
    # ITSELF, invoked as the tool. A re-implementation here would share none of
    # its fingerprint dedupe, its private-extension tagging or its halt check —
    # and would share every blind spot it has.
    class DiscoveryRunService
      MAX_TIER_SETTING = "ai.improvement_discovery_max_environment_tier"
      DEFAULT_MAX_TIER = 0

      MAX_OFFERS_SETTING = "ai.improvement_discovery_max_offers_per_run"
      DEFAULT_MAX_OFFERS = 25

      # The behaviour-provider key an extension registers its executor under.
      EXECUTOR_KEY = :lint_discovery_executor

      # What an executor may answer for a whole dispatch, and per repository.
      DISPATCH_STATUSES = %w[dispatched skipped failed].freeze
      REPOSITORY_DISPATCH_STATUSES = %w[dispatched skipped].freeze

      # A linter summary in one of these states actually inspected the code.
      # Anything else (timeout, unavailable, no_output, parse_error, ...) did
      # not, and must never read as clean.
      MEASURED_STATUSES = %w[completed clean].freeze

      # The one report status that carries output to parse. Every other status
      # an executor reports is recorded verbatim as a did-not-measure status.
      RAN_STATUS = "ran"

      # The analyzers that can hand back a finding with a file, a line and a
      # rule. See the class comment for the three that cannot, yet.
      ANALYZERS = %w[lint].freeze

      # A linter offence is a mechanical fact, not an estimate. The column is
      # NOT NULL, so a number has to go in it; a per-severity weighting would be
      # exactly the invented scoring the audit faulted `attribute_failure` for.
      LINT_CONFIDENCE = 0.9

      # Worst first, so the per-run cap keeps what matters. `info` is where
      # rubocop's `convention` and `refactor` offences land. Under this repo's
      # omakase config most offences are conventions, so excluding `info` would
      # file only the few Lint warnings and errors, and miss most of what the
      # linter reports.
      SEVERITY_RANK = { "error" => 0, "warning" => 1, "info" => 2 }.freeze

      def self.max_environment_tier
        configured = ::SiteSetting.get(MAX_TIER_SETTING)
        configured.nil? ? DEFAULT_MAX_TIER : configured.to_i
      end

      def self.max_offers_per_run
        configured = ::SiteSetting.get(MAX_OFFERS_SETTING).to_i
        configured.positive? ? configured : DEFAULT_MAX_OFFERS
      end

      # The registered executor, or nil in core mode.
      def self.executor
        ::Powernode::ExtensionRegistry.provider(EXECUTOR_KEY)
      end

      # ONE TICK AS UNITS: one per ACTIVE ACCOUNT (D1b ruling: one lease per
      # account per tick). A unit dispatches; it does not run the linters. So it
      # no longer has to be one repository to keep a call bounded, which was D1
      # review H2's concern about a POST that ran the linters itself.
      #
      # Stable order: `find_each` walks accounts by id.
      #
      # @param scope [ActiveRecord::Relation] the accounts the walk may reach.
      #   The internal door passes the calling worker's own account, so a
      #   worker never reaches another account's unit.
      def self.units(scope = ::Account.all)
        ids = []
        scope.find_each { |account| ids << account.id if account.active? }
        ids
      end

      def initialize(account:)
        @account = account
      end

      # Dispatch this account's repositories to the executor.
      #
      # @return [Hash] the run summary (phase "dispatch"). Always a summary,
      #   never nil: a skipped run says why it was skipped.
      def run!
        @started_at = Time.current

        refusal = gate("dispatch")
        return refusal if refusal

        repositories = candidate_repositories.to_a
        return skipped("no_repositories", phase: "dispatch", **environment_details) if repositories.empty?

        executor = self.class.executor
        if executor.nil?
          return skipped("no_discovery_executor", phase: "dispatch", **environment_details,
                         repositories: repositories.map { |repo| repository_row(repo, "skipped", "no_discovery_executor") })
        end

        dispatch(executor, repositories)
      end

      # ONE REPOSITORY'S RESULT, handed back by the executor.
      #
      # @param repository [Devops::GitRepository] must belong to this account
      # @param linters [Hash] keyed by linter (`ruby`, `typescript`,
      #   `javascript_lint`), each `{ "status" => "ran", "exitstatus" => 0,
      #   "output" => "..." }` or a did-not-run status such as
      #   `{ "status" => "unavailable" }`
      # @param base_path [String] the directory the linters ran in, on the
      #   runner, so reported paths come back relative to the repository root
      # @param run_ref [String, nil] the executor's reference for the dispatch
      # @param must_not_contain [Array<String>] values that must appear nowhere
      #   in the handed-back output, such as the credential the executor gave
      #   the runner. A hit files nothing and is recorded as the FACT only.
      # @return [Hash] the run summary (phase "ingest"), also written as the
      #   account's audit row
      def ingest!(repository:, linters:, base_path:, run_ref: nil, must_not_contain: [])
        @started_at = Time.current
        unless repository.account_id == account.id
          raise ArgumentError, "repository #{repository.id} does not belong to account #{account.id}"
        end

        summary = gate("ingest", run_ref: run_ref) ||
                  (credential_refusal(repository, linters, base_path, must_not_contain, run_ref) ||
                   file_result(repository, linters, base_path, run_ref))
        ::Ai::Improvement::DiscoveryRun.record!(account: account, summary: summary)
        summary
      end

      private

      attr_reader :account

      # Gates 1 and 2. nil when both pass; otherwise the skipped summary.
      def gate(phase, **details)
        return skipped("ai_suspended", phase: phase, **details) if account.ai_suspended?

        @environment = ::Ai::Environment.default_for(account)
        return skipped("no_environment", phase: phase, **details) if @environment.blank?

        @ceiling = self.class.max_environment_tier
        return nil if @environment.tier.to_i <= @ceiling

        skipped("environment_tier_above_ceiling", phase: phase, **details, **environment_details)
      end

      def environment_details
        { environment: @environment.slug, environment_tier: @environment.tier,
          environment_tier_ceiling: @ceiling }
      end

      def dispatch(executor, repositories)
        outcome = executor.dispatch!(account: account, repositories: repositories)
        outcome = outcome.is_a?(Hash) ? outcome.symbolize_keys : {}
        status = outcome[:status].to_s
        reason = outcome[:reason].presence&.to_s

        unless DISPATCH_STATUSES.include?(status)
          status = "failed"
          reason = "unrecognised_executor_answer"
        end

        rows = dispatch_rows(repositories, outcome[:repositories], status, reason)
        summary_spine.merge(
          phase: "dispatch",
          status: status,
          run_ref: outcome[:run_ref].presence&.to_s,
          repositories: rows,
          repository_ids: rows.filter_map { |row| row[:id] if row[:status] == "dispatched" }
        ).merge(reason_key(status, reason)).merge(environment_details).merge(timing)
      rescue StandardError => e
        Rails.logger.error("[ImprovementDiscovery] dispatch failed for account #{account.id}: #{e.class}: #{e.message}")
        # The class only: this lands in an audit row, and a message can carry
        # paths or output (D1 review L4).
        summary_spine.merge(phase: "dispatch", status: "failed", failure: e.class.name,
                            repositories: repositories.map { |repo| repository_row(repo, "failed", "executor_raised") })
                     .merge(environment_details).merge(timing)
      end

      # One row per candidate repository. A repository the executor did not
      # answer for is not silently counted as dispatched.
      def dispatch_rows(repositories, reported, status, reason)
        by_id = Array(reported).each_with_object({}) do |row, acc|
          next unless row.is_a?(Hash)

          row = row.symbolize_keys
          acc[row[:id].to_s] = row
        end

        repositories.map do |repo|
          row = by_id[repo.id.to_s]
          if status != "dispatched"
            repository_row(repo, status == "failed" ? "failed" : "skipped", reason)
          elsif row.nil?
            repository_row(repo, "skipped", "not_reported_by_executor")
          elsif REPOSITORY_DISPATCH_STATUSES.include?(row[:status].to_s)
            repository_row(repo, row[:status].to_s, row[:reason].presence&.to_s)
          else
            repository_row(repo, "skipped", "unrecognised_executor_answer")
          end
        end
      end

      def repository_row(repo, status, reason)
        { repository: repo.name, id: repo.id, status: status, reason: reason }.compact
      end

      def reason_key(status, reason)
        case status
        when "skipped" then { skipped_reason: reason || "unspecified" }
        when "failed" then { failure: reason || "unspecified" }
        else {}
        end
      end

      # The executor gave the runner a credential. If any of it came back in
      # the output, something on the runner printed it: file nothing, and
      # record that it happened — never the value.
      def credential_refusal(repository, linters, base_path, must_not_contain, run_ref)
        needles = Array(must_not_contain).map(&:to_s).reject { |value| value.length < 8 }
        return nil if needles.empty?

        haystack = [ base_path.to_s, linters.to_json ].join("\n")
        return nil unless needles.any? { |needle| haystack.include?(needle) }

        Rails.logger.error("[ImprovementDiscovery] credential found in handed-back output for repository #{repository.id}; nothing filed")
        summary_spine.merge(phase: "ingest", status: "failed", failure: "credential_in_payload", run_ref: run_ref,
                            repositories: [ repository_row(repository, "failed", "credential_in_payload") ])
                     .merge(environment_details).merge(timing)
      end

      def file_result(repo, linters, base_path, run_ref)
        summaries, diagnostics = parse_reports(linters, base_path)
        row = { repository: repo.name, id: repo.id }
        degraded = []
        findings = []

        if summaries.empty?
          # NOT MEASURED IS NOT CLEAN (D1 review H3): no linter reported at all.
          row.merge!(status: "not_measured", reason: "no_linter_detected", linters: {})
          degraded << { repository: repo.name, analyzer: "lint", status: "no_linter_detected" }
        else
          degraded.concat(degraded_linters(repo, summaries))
          if summaries.values.none? { |summary| measured?(summary) }
            row.merge!(status: "not_measured", reason: "no_linter_ran", linters: summaries)
          else
            findings = group_findings(diagnostics)
            row.merge!(status: "analyzed", findings: findings.size, linters: summaries)
          end
        end

        counts = file_offers(repo, findings)
        summary_spine.merge(
          phase: "ingest",
          status: run_status(row[:status]),
          run_ref: run_ref,
          repositories: [ row ],
          repository_ids: row[:status] == "analyzed" ? [ repo.id ] : [],
          findings: findings.size,
          analyzers_degraded: degraded,
          linter_statuses: linter_statuses(row)
        ).merge(counts).merge(environment_details).merge(timing)
      end

      # @return [Array(Hash, Array)] per-linter summaries keyed by the linter's
      #   display name, and every diagnostic parsed from the ones that ran
      def parse_reports(linters, base_path)
        summaries = {}
        diagnostics = []
        (linters.is_a?(Hash) ? linters : {}).each do |key, report|
          report = report.is_a?(Hash) ? report.stringify_keys : {}
          name = linter_name(key)
          status = report["status"].to_s

          if status == RAN_STATUS
            parsed = ::Ai::Codebase::StaticAnalysisService.parse_output(
              key, output: report["output"], exitstatus: report["exitstatus"], base_path: base_path.to_s
            )
            summaries[name] = parsed[:summary]
            diagnostics.concat(Array(parsed[:diagnostics]))
          else
            summaries[name] = { status: status.presence || "unknown" }
          end
        end
        [ summaries, diagnostics ]
      end

      def linter_name(key)
        config = ::Ai::Codebase::StaticAnalysisService::LINTER_CONFIGS[key.to_s.to_sym]
        config ? config[:name] : key.to_s
      end

      def file_offers(repo, findings)
        counts = { offers_created: 0, offers_deduped: 0, offers_parked: 0 }
        budget = self.class.max_offers_per_run

        findings.first(budget).each do |finding|
          case file_offer(repo, finding)
          when :created then counts[:offers_created] += 1
          when :deduped then counts[:offers_deduped] += 1
          when :parked  then counts[:offers_parked] += 1
          end
        end
        counts
      end

      # analyzed: the linters inspected the code. not_measured: they reported,
      # but none inspected it.
      def run_status(row_status)
        row_status == "analyzed" ? "completed" : "not_measured"
      end

      # Every run summary carries the same spine, so a skipped run is queryable
      # alongside a completed one instead of being a differently-shaped hash.
      def summary_spine
        { account_id: account.id, analyzers: ANALYZERS, repositories: [], repository_ids: [],
          offers_created: 0, offers_deduped: 0, offers_parked: 0, findings: 0,
          analyzers_degraded: [], linter_statuses: {} }
      end

      def skipped(reason, **details)
        summary_spine.merge(status: "skipped", skipped_reason: reason).merge(details).merge(timing)
      end

      def timing
        finished = Time.current
        {
          started_at: @started_at&.iso8601,
          finished_at: finished.iso8601,
          duration_ms: @started_at ? ((finished - @started_at) * 1000).round : nil
        }
      end

      def linter_statuses(row)
        return {} if row[:linters].blank?

        { row[:repository] => row[:linters].transform_values { |summary| status_of(summary) } }
      end

      def status_of(summary)
        summary.is_a?(Hash) ? (summary[:status] || summary["status"]).to_s : summary.to_s
      end

      # Repositories belonging to this account.
      def candidate_repositories
        ::Devops::GitRepository.where(account_id: account.id).order(:name, :id)
      end

      def measured?(summary)
        MEASURED_STATUSES.include?(status_of(summary))
      end

      # A linter whose status is anything but `completed`/`clean` did not
      # actually inspect the code.
      def degraded_linters(repo, summaries)
        summaries.filter_map do |name, summary|
          next if measured?(summary)

          { repository: repo.name, analyzer: name.to_s, status: status_of(summary).presence || "unknown" }
        end
      end

      # One offer per (file, rule) rather than per offence: a rule broken forty
      # times in one file is one thing to fix, and forty offers would bury the
      # queue it is supposed to inform. The count rides along as evidence.
      def group_findings(diagnostics)
        diagnostics
          .group_by { |d| [ d[:file].to_s, d[:rule].to_s ] }
          .map do |(file, rule), group|
            worst = group.min_by { |d| SEVERITY_RANK.fetch(d[:severity].to_s, 3) }
            {
              file: file,
              rule: rule,
              severity: worst[:severity].to_s,
              linter: worst[:linter].to_s,
              message: worst[:message].to_s,
              lines: group.map { |d| d[:line] }.compact.sort.first(20),
              occurrences: group.size
            }
          end
          .sort_by { |f| [ SEVERITY_RANK.fetch(f[:severity], 3), -f[:occurrences], f[:file], f[:rule] ] }
      end

      def file_offer(repo, finding)
        result = improvement_tool.execute(params: {
          action: "create_improvement",
          recommendation_type: "code_lint",
          fingerprint: "code_lint|#{finding[:file]}|#{finding[:rule]}",
          title: "#{finding[:linter]} #{finding[:rule]} in #{finding[:file]}",
          description: "#{finding[:message]} (#{finding[:occurrences]} occurrence(s), " \
                       "severity #{finding[:severity]})",
          files: [ finding[:file] ],
          repository: repo.name,
          confidence_score: LINT_CONFIDENCE,
          verifier_evidence: {
            "analyzer" => "lint",
            "linter" => finding[:linter],
            "rule" => finding[:rule],
            "severity" => finding[:severity],
            "occurrences" => finding[:occurrences],
            "lines" => finding[:lines]
          }
        })

        # `execute` can answer three ways, and only one of them filed anything.
        # A parked (autonomy-gated) call and a refusal must not be counted as a
        # created offer — that is how a loop comes to report work it never did.
        # The flags live under `data`: BaseTool#success_result wraps its argument
        # as `{ success:, data: }` (`base_tool.rb:979-981`).
        data = result[:data] || {}
        return :parked if data[:pending] || data[:halted]
        return :failed unless result[:success]

        data[:deduped] ? :deduped : :created
      end

      # A system-initiated caller, declared as one. Built with only an account,
      # the tool records the call as "unattributed" (BaseTool#
      # caller_principal_descriptor), and a per-action gate added later would
      # refuse it on every run with nothing to show for it, the way an
      # extension's auto-evolve trigger once went silent.
      def improvement_tool
        @improvement_tool ||= ::Ai::Tools::ImprovementTool.new(account: account, internal: true)
      end
    end
  end
end
