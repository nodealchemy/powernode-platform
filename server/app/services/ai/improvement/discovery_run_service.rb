# frozen_string_literal: true

module Ai
  module Improvement
    # D1 — THE DISCOVERY CLOCK.
    #
    # The audit's finding (2026-09-10, §6.2): "Improvement discovery — Scheduled:
    # No". `platform.discover_improvements` returns GUIDANCE TEXT telling a caller
    # which analyzers to run (`improvement_tool.rb:163-183`); no cron references it
    # or the code-analysis verbs. So every code-quality offer on this platform was
    # filed by a human-driven session, and the platform could not improve itself
    # without one. This service is the analyzer that verb only describes.
    #
    # ── WHAT IT ACTUALLY RUNS, AND WHAT IT DELIBERATELY DOES NOT ────────────────
    # `Ai::Codebase::StaticAnalysisService` is the ONLY analyzer in the tree that
    # produces findings mechanically and synchronously: it shells out to
    # rubocop/tsc/eslint and returns `{file, line, severity, message, rule}` rows.
    # The other three the audit's remedy names are NOT wired here, on purpose:
    #
    #   * `code_dead_code` (`code_analysis_tool.rb:186`) and `code_find_duplicates`
    #     (`:217`) do not analyse anything — they dispatch to the worker and return
    #     a fixed `{success: true, status: "enqueued"}`. That IS the audit's own
    #     §4.2 defect for those two verbs. Calling them from here would add two
    #     analyzer names to a run summary and zero findings to the offer queue —
    #     a deferral to an unbuilt component wearing the costume of a closed loop.
    #   * `scripts/pattern-validation.sh` emits human-formatted PASS/FAIL lines
    #     with no file:line, so it cannot be turned into fingerprinted offers
    #     without a parser that would be the least reliable part of this seam.
    #
    # `ANALYZERS` is the registry those three join once they can hand back a
    # finding with a file, a line and a rule. The gap is named, not hidden.
    #
    # ── A LINTER THAT DID NOT RUN IS NOT A CLEAN SWEEP ──────────────────────────
    # `StaticAnalysisService` reports a per-linter `summary.status` of
    # `no_gemfile` / `no_output` / `parse_error` / `error`, and its caller in
    # `code_analysis_tool.rb` throws that away behind a headline `errors: 0` —
    # the audit's §4.2 finding for `code_static_analysis`. This service keeps the
    # per-linter status in the run summary and reports `analyzers_degraded`, so
    # "no findings" and "nothing ran" can never read the same.
    #
    # ── GATES, IN ORDER ─────────────────────────────────────────────────────────
    #   1. Account kill switch (`ai_suspended?`) — same predicate the other
    #      internal crons use.
    #   2. Environment ceiling. The account's DEFAULT environment
    #      (`Ai::Environment.default_for`) must sit at or below a SiteSetting tier
    #      ceiling, default 0 — dev and ci only. NOTE: `ai_ralph_loops` carries no
    #      `environment_id`, so there is no dev-improve loop environment to
    #      inherit; the account's default plane is the anchor, and one rule
    #      decides, not a second rival threshold.
    #   3. A repository must have a working copy ON THIS NODE
    #      (`metadata["local_path"]`, the same key `CodebaseContextResolvable`
    #      resolves), and that copy must resolve, symlinks followed, inside the
    #      operator's discovery root (SiteSetting ALLOWED_ROOT_SETTING; D1
    #      review M3). The linters execute code from the directory they run in
    #      (a Gemfile, a .rubocop.yml `require:`, an eslint config), so a tenant
    #      must not be able to point this at an arbitrary path, or at another
    #      tenant's copy. The root may carry `%{account_id}`, and a multi-tenant
    #      deployment must use it; absent, discovery is off for every
    #      repository and says so. Repositories that fail this are counted as
    #      skipped WITH a reason, never silently dropped.
    #   4. A per-run offer cap, so a first run against a repo with thousands of
    #      offences files a bounded number of the most severe.
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

      ALLOWED_ROOT_SETTING = "ai.improvement_discovery_allowed_root"
      ACCOUNT_PLACEHOLDER = "%{account_id}"

      # A linter summary in one of these states actually inspected the code.
      # Anything else (timeout, unavailable, no_output, parse_error, ...) did
      # not, and must never read as clean.
      MEASURED_STATUSES = %w[completed clean].freeze

      # The analyzers that can hand back a finding with a file, a line and a
      # rule. See the class comment for the three that cannot, yet.
      ANALYZERS = %w[lint].freeze

      # A linter offence is a mechanical fact, not an estimate. The column is
      # NOT NULL, so a number has to go in it; a per-severity weighting would be
      # exactly the invented scoring the audit faulted `attribute_failure` for.
      LINT_CONFIDENCE = 0.9

      # Worst first, so the per-run cap keeps what matters. `info` is where
      # rubocop's `convention` and `refactor` offences land
      # (`static_analysis_service.rb:207-213`) — under this repo's omakase
      # config that is most of them, so excluding it would leave a discovery
      # loop that mechanically cannot find anything in Ruby.
      SEVERITY_RANK = { "error" => 0, "warning" => 1, "info" => 2 }.freeze

      def self.max_environment_tier
        configured = ::SiteSetting.get(MAX_TIER_SETTING)
        configured.nil? ? DEFAULT_MAX_TIER : configured.to_i
      end

      def self.max_offers_per_run
        configured = ::SiteSetting.get(MAX_OFFERS_SETTING).to_i
        configured.positive? ? configured : DEFAULT_MAX_OFFERS
      end

      # The discovery root for one account, or nil when none is configured.
      def self.allowed_root_for(account)
        raw = ::SiteSetting.get(ALLOWED_ROOT_SETTING).to_s.strip
        return nil if raw.empty?

        raw.gsub(ACCOUNT_PLACEHOLDER, account.id.to_s)
      end

      # ONE TICK AS UNITS (D1 review H2). The worker walks these one POST at a
      # time, so each call does one repository's work and no call can fan out
      # into a whole-fleet sweep. A unit is [account_id, repository_id], or
      # [account_id, nil] for an active account with no repositories, so the
      # account still gets a run record saying why nothing was analysed.
      #
      # Stable order (account id, then repository name and id). Two queries plus
      # the account batches, not one per account.
      def self.units
        repos = ::Devops::GitRepository.order(:name, :id).pluck(:account_id, :id).group_by(&:first)
        units = []
        ::Account.find_each do |account|
          next unless account.active?

          ids = Array(repos[account.id]).map(&:last)
          ids.empty? ? units << [ account.id, nil ] : ids.each { |id| units << [ account.id, id ] }
        end
        units
      end

      def initialize(account:)
        @account = account
      end

      # @return [Hash] the run summary. Always a summary, never nil: a skipped
      #   run says why it was skipped.
      # @param repository_id [String, nil] one repository (a door unit), or
      #   nil for every repository of the account
      def run!(repository_id: nil)
        @started_at = Time.current

        return skipped("ai_suspended") if @account.ai_suspended?

        environment = ::Ai::Environment.default_for(@account)
        return skipped("no_environment") if environment.blank?

        ceiling = self.class.max_environment_tier
        if environment.tier.to_i > ceiling
          return skipped("environment_tier_above_ceiling",
                         environment: environment.slug, environment_tier: environment.tier,
                         environment_tier_ceiling: ceiling)
        end

        repositories = candidate_repositories
        repositories = repositories.where(id: repository_id) if repository_id
        return skipped("no_repositories") unless repositories.exists?

        sweep(environment, ceiling, repositories)
      end

      private

      attr_reader :account

      def sweep(environment, ceiling, candidates)
        offers_created = 0
        offers_deduped = 0
        offers_parked = 0
        findings = 0
        repositories = []
        degraded = []

        budget = self.class.max_offers_per_run

        candidates.each do |repo|
          row = { repository: repo.name, id: repo.id }
          path, reason = working_copy_for(repo)

          if reason
            repositories << row.merge(status: "skipped", reason: reason)
            next
          end

          result = analyze(path)
          if result[:error]
            repositories << row.merge(status: "failed", reason: result[:error])
            degraded << { repository: repo.name, analyzer: "lint", status: "error" }
            next
          end

          # NOT MEASURED IS NOT CLEAN (D1 review H3). No linter detected for
          # the project root, or none of the detected ones actually inspected
          # the code: either way this repository was not analysed, and a zero
          # finding count from it would be a lie.
          linters = result[:linters] || {}
          if linters.empty?
            repositories << row.merge(status: "not_measured", reason: "no_linter_detected", linters: {})
            degraded << { repository: repo.name, analyzer: "lint", status: "no_linter_detected" }
            next
          end

          degraded.concat(degraded_linters(repo, linters))
          unless linters.values.any? { |summary| measured?(summary) }
            repositories << row.merge(status: "not_measured", reason: "no_linter_ran", linters: linters)
            next
          end

          repo_findings = group_findings(result[:diagnostics])
          findings += repo_findings.size

          repo_findings.first(budget).each do |finding|
            outcome = file_offer(repo, finding)
            case outcome
            when :created then offers_created += 1; budget -= 1
            when :deduped then offers_deduped += 1; budget -= 1
            when :parked  then offers_parked += 1
            end
          end

          repositories << row.merge(status: "analyzed", findings: repo_findings.size,
                                    linters: result[:linters])
        end

        {
          status: run_status(repositories),
          account_id: account.id,
          environment: environment.slug,
          environment_tier: environment.tier,
          environment_tier_ceiling: ceiling,
          analyzers: ANALYZERS,
          repositories: repositories,
          # Every repository this run actually analysed, so a reader can tell
          # WHICH working copy a finding came from without re-deriving it.
          repository_ids: repositories.filter_map { |r| r[:id] if r[:status] == "analyzed" },
          findings: findings,
          offers_created: offers_created,
          offers_deduped: offers_deduped,
          offers_parked: offers_parked,
          # NOT the same as "found nothing": a linter that never ran is listed
          # here so a caller can tell an empty queue from an empty sweep.
          analyzers_degraded: degraded,
          # Per-linter status per repository, verbatim from the analyzer —
          # `completed` / `clean` / `no_gemfile` / `no_output` / `parse_error`.
          linter_statuses: linter_statuses(repositories)
        }.merge(skip_reason_for(repositories)).merge(timing)
      end

      # completed: at least one repository was analysed. not_measured: some
      # working copy was reachable but no linter inspected it. skipped: nothing
      # was reachable at all.
      def run_status(repositories)
        statuses = repositories.map { |r| r[:status] }
        return "completed" if statuses.include?("analyzed")
        return "not_measured" if statuses.include?("not_measured")
        return "failed" if statuses.include?("failed")

        "skipped"
      end

      def skip_reason_for(repositories)
        return {} if repositories.any? { |r| %w[analyzed not_measured failed].include?(r[:status]) }

        reasons = repositories.map { |r| r[:reason] }.uniq
        { skipped_reason: reasons.one? ? reasons.first : "no_repository_analyzable" }
      end

      # Every run summary carries the same spine, so a skipped run is queryable
      # alongside a completed one instead of being a differently-shaped hash.
      def skipped(reason, **details)
        { status: "skipped", skipped_reason: reason, account_id: account.id,
          analyzers: ANALYZERS, repositories: [], repository_ids: [],
          offers_created: 0, offers_deduped: 0, offers_parked: 0, findings: 0,
          analyzers_degraded: [], linter_statuses: {} }.merge(details).merge(timing)
      end

      def timing
        finished = Time.current
        {
          started_at: @started_at&.iso8601,
          finished_at: finished.iso8601,
          duration_ms: @started_at ? ((finished - @started_at) * 1000).round : nil
        }
      end

      def linter_statuses(repositories)
        repositories.each_with_object({}) do |row, acc|
          next if row[:linters].blank?

          acc[row[:repository]] = row[:linters].transform_values do |summary|
            summary.is_a?(Hash) ? (summary[:status] || summary["status"]).to_s : summary.to_s
          end
        end
      end

      # Repositories belonging to this account. `find_each` rather than `.all`
      # so a large fleet does not load every row at once.
      def candidate_repositories
        ::Devops::GitRepository.where(account_id: account.id).order(:name)
      end

      # @return [Array(String, nil)] [real_path, nil] or [nil, reason]
      def working_copy_for(repo)
        raw = repo.metadata&.dig("local_path").to_s
        return [ nil, "no_local_path" ] if raw.blank?

        root = self.class.allowed_root_for(account)
        return [ nil, "discovery_root_not_configured" ] if root.nil?

        real_root = real_directory(root)
        return [ nil, "discovery_root_missing" ] if real_root.nil?

        # realpath, not the raw string: a symlink or `..` inside the root must
        # not reach outside it.
        real = real_directory(raw)
        return [ nil, "no_local_path" ] if real.nil?
        return [ nil, "local_path_outside_discovery_root" ] unless real == real_root || real.start_with?("#{real_root}/")

        [ real, nil ]
      end

      def real_directory(path)
        real = File.realpath(path)
        File.directory?(real) ? real : nil
      rescue SystemCallError
        nil
      end

      def measured?(summary)
        status = summary.is_a?(Hash) ? (summary[:status] || summary["status"]).to_s : ""
        MEASURED_STATUSES.include?(status)
      end

      def analyze(path)
        result = ::Ai::Codebase::StaticAnalysisService.new(base_path: path).analyze
        {
          diagnostics: Array(result[:diagnostics]),
          linters: result.dig(:summary, :linters) || {}
        }
      rescue StandardError => e
        Rails.logger.error("[ImprovementDiscovery] analysis failed for #{path}: #{e.class}: #{e.message}")
        # The class only: this lands in an audit row, and a message can carry
        # paths or output from the working copy (D1 review L4).
        { error: e.class.name }
      end

      # A linter whose status is anything but `completed`/`clean` did not
      # actually inspect the code. `no_gemfile`, `no_output`, `parse_error` and
      # `error` all read as "0 findings" downstream unless they are surfaced.
      def degraded_linters(repo, linters)
        Array(linters).filter_map do |name, summary|
          status = summary.is_a?(Hash) ? (summary[:status] || summary["status"]).to_s : ""
          next if MEASURED_STATUSES.include?(status)

          { repository: repo.name, analyzer: name.to_s, status: status.presence || "unknown" }
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

      def improvement_tool
        @improvement_tool ||= ::Ai::Tools::ImprovementTool.new(account: account)
      end
    end
  end
end
