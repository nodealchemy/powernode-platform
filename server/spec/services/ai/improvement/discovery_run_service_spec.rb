# frozen_string_literal: true

require "rails_helper"
require "open3"

# D1 — the discovery clock. D1b — where its linters run.
#
# The Rails process no longer runs a repository's linters. A registered
# executor dispatches them to a runner and hands each repository's RAW output
# back through #ingest!. The executor is the one external boundary, so it is
# the one thing faked here; the parser, the gates, the grouping and the filing
# all run for real. One example feeds #ingest! the output of a REAL rubocop.
#
# BOTH ARMS everywhere: a gate that only ever refuses and a gate that only ever
# allows are the same defect.
RSpec.describe Ai::Improvement::DiscoveryRunService, type: :service do
  let(:account) { create(:account) }
  let!(:repository) { create(:git_repository, account: account, name: "core") }
  let(:base_path) { "/runner/work/core" }

  # A stand-in with the provider contract, recording each call.
  let(:executor_class) do
    Class.new do
      attr_reader :calls
      attr_accessor :answer

      def initialize
        @calls = []
      end

      def dispatch!(account:, repositories:)
        @calls << { account: account, repositories: repositories }
        answer.respond_to?(:call) ? answer.call(account, repositories) : answer
      end
    end
  end

  let(:executor) do
    executor_class.new.tap do |stand_in|
      stand_in.answer = lambda do |_account, repos|
        { status: "dispatched", run_ref: "lease-1",
          repositories: repos.map { |repo| { id: repo.id, status: "dispatched" } } }
      end
    end
  end

  def register(executor)
    allow(Powernode::ExtensionRegistry).to receive(:provider).and_call_original
    allow(Powernode::ExtensionRegistry).to receive(:provider)
      .with(described_class::EXECUTOR_KEY).and_return(executor)
  end

  def service = described_class.new(account: account)

  def rubocop_json(offenses, path: "app/models/thing.rb")
    {
      "files" => [ { "path" => path, "offenses" => offenses } ],
      "summary" => { "inspected_file_count" => 1, "offense_count" => offenses.size }
    }.to_json
  end

  def offense(cop: "Style/StringLiterals", severity: "convention", line: 3)
    { "severity" => severity, "message" => "Prefer double-quoted strings", "cop_name" => cop,
      "location" => { "start_line" => line, "start_column" => 1 } }
  end

  def ran(output, exitstatus: 0) = { "status" => "ran", "exitstatus" => exitstatus, "output" => output }

  def ingest(linters = { "ruby" => ran(rubocop_json([ offense ])) }, repo: repository, **options)
    service.ingest!(repository: repo, linters: linters, base_path: base_path, **options)
  end

  def offers
    Ai::ImprovementRecommendation.where(account: account, recommendation_type: "code_lint")
  end

  def audit_rows
    AuditLog.where(action: Ai::Improvement::DiscoveryRun::ACTION, account_id: account.id)
  end

  describe "core mode: no executor registered" do
    before { register(nil) }

    it "runs nothing, and skips the unit and every repository as no_discovery_executor" do
      result = service.run!

      expect(result).to include(phase: "dispatch", status: "skipped", skipped_reason: "no_discovery_executor")
      expect(result[:repositories]).to contain_exactly(
        hash_including(repository: "core", status: "skipped", reason: "no_discovery_executor")
      )
      expect(result[:repository_ids]).to be_empty
    end
  end

  describe "dispatch" do
    before { register(executor) }

    it "hands the account's repositories, and no other account's, to the executor once" do
      second = create(:git_repository, account: account, name: "docs")
      create(:git_repository, account: create(:account), name: "theirs")

      result = service.run!

      expect(executor.calls.size).to eq(1)
      expect(executor.calls.first[:account]).to eq(account)
      expect(executor.calls.first[:repositories]).to contain_exactly(repository, second)
      expect(result).to include(phase: "dispatch", status: "dispatched", run_ref: "lease-1")
      expect(result[:repository_ids]).to contain_exactly(repository.id, second.id)
      expect(result).not_to have_key(:skipped_reason)
    end

    it "does not count a repository the executor never answered for as dispatched" do
      create(:git_repository, account: account, name: "docs")
      executor.answer = { status: "dispatched", run_ref: "lease-1",
                          repositories: [ { id: repository.id, status: "dispatched" } ] }

      result = service.run!

      expect(result[:repositories]).to contain_exactly(
        hash_including(repository: "core", status: "dispatched"),
        hash_including(repository: "docs", status: "skipped", reason: "not_reported_by_executor")
      )
      expect(result[:repository_ids]).to eq([ repository.id ])
    end

    it "records an executor's refusal, with its reason, on every repository" do
      executor.answer = { status: "skipped", reason: "no_ci_runner_pool" }

      result = service.run!

      expect(result).to include(status: "skipped", skipped_reason: "no_ci_runner_pool")
      expect(result[:repositories]).to contain_exactly(
        hash_including(repository: "core", status: "skipped", reason: "no_ci_runner_pool")
      )
      expect(result[:repository_ids]).to be_empty
    end

    it "calls an answer outside the contract a failure, never a dispatch" do
      executor.answer = { status: "queued" }

      result = service.run!

      expect(result).to include(status: "failed", failure: "unrecognised_executor_answer")
      expect(result[:repository_ids]).to be_empty
    end

    it "records an executor that raises by exception class only" do
      executor.answer = ->(*) { raise "planted /srv/secret path" }

      result = service.run!

      expect(result).to include(status: "failed", failure: "RuntimeError")
      expect(result.to_json).not_to include("planted")
    end
  end

  describe "kill switch" do
    before { register(executor) }

    it "dispatches nothing, and says why, when the account is suspended" do
      account.update!(ai_suspended: true)

      expect(service.run!).to include(status: "skipped", skipped_reason: "ai_suspended")
      expect(executor.calls).to be_empty
    end

    it "dispatches when the account is not suspended" do
      expect(service.run!).to include(status: "dispatched")
      expect(executor.calls.size).to eq(1)
    end

    it "files nothing from a result that arrives after the switch was thrown" do
      account.update!(ai_suspended: true)

      expect(ingest).to include(phase: "ingest", status: "skipped", skipped_reason: "ai_suspended")
      expect(offers.count).to eq(0)
    end
  end

  describe "environment ceiling" do
    before { register(executor) }

    def make_prod_default!
      Ai::Environment.where(account: account).update_all(is_default: false)
      Ai::Environment.find_by!(account: account, slug: "prod").update!(is_default: true)
    end

    # Accounts are seeded with the DEFAULTS ladder, `dev` (tier 0) default.
    it "dispatches in the default dev plane (tier 0, at the default ceiling)" do
      expect(service.run!).to include(status: "dispatched", environment: "dev", environment_tier: 0)
    end

    it "refuses, before calling the executor, when the default plane sits above the ceiling" do
      make_prod_default!

      expect(service.run!).to include(status: "skipped", skipped_reason: "environment_tier_above_ceiling",
                                      environment: "prod", environment_tier: 3, environment_tier_ceiling: 0)
      expect(executor.calls).to be_empty
    end

    it "dispatches in a higher plane once the SiteSetting ceiling is raised" do
      make_prod_default!
      SiteSetting.set(described_class::MAX_TIER_SETTING, 3, setting_type: "integer")

      expect(service.run!).to include(status: "dispatched", environment: "prod")
    end

    it "files nothing from a result for an account now above the ceiling" do
      make_prod_default!

      expect(ingest).to include(status: "skipped", skipped_reason: "environment_tier_above_ceiling")
      expect(offers.count).to eq(0)
    end
  end

  # D1b ruling (c): one lease per account per tick, so one unit per account.
  describe ".units" do
    it "lists each active account once, and no inactive one" do
      create(:git_repository, account: account, name: "docs")
      empty = create(:account)
      gone = create(:account)
      gone.update!(status: "cancelled")

      units = described_class.units(Account.all)

      expect(units.count(account.id)).to eq(1)
      expect(units).to include(empty.id)
      expect(units).not_to include(gone.id)
    end

    it "says why, without calling the executor, when an account has no repository" do
      register(executor)

      expect(described_class.new(account: create(:account)).run!)
        .to include(status: "skipped", skipped_reason: "no_repositories")
      expect(executor.calls).to be_empty
    end
  end

  describe "the D1 oracle through #ingest!: one result files one offer, a second files none" do
    it "files exactly one offer for a seeded lint violation" do
      result = ingest

      expect(result).to include(phase: "ingest", status: "completed", offers_created: 1)
      expect(offers.count).to eq(1)
      expect(offers.first.evidence["fingerprint"]).to eq("code_lint|app/models/thing.rb|Style/StringLiterals")
    end

    it "files zero NEW offers from a second result and reports the dedupe" do
      ingest
      second = ingest

      expect(offers.count).to eq(1)
      expect(second).to include(offers_created: 0, offers_deduped: 1)
    end

    it "writes one audit row per result, carrying the whole summary" do
      expect { ingest(run_ref: "lease-9") }.to change { audit_rows.count }.by(1)

      expect(audit_rows.last.metadata).to include(
        "phase" => "ingest", "status" => "completed", "run_ref" => "lease-9", "findings" => 1,
        "offers_created" => 1, "repository_ids" => [ repository.id ],
        "linter_statuses" => { "core" => { "RuboCop" => "completed" } }
      )
    end
  end

  # The audit's §4.2 finding for code_static_analysis: the headline `errors: 0`
  # discards a did-not-run status, so "nothing ran" reads like "nothing found".
  describe "a linter that did not run is not a clean sweep" do
    it "reads a linter the runner could not run as not measured, and lists it degraded" do
      result = ingest({ "ruby" => { "status" => "unavailable" } })

      expect(result).to include(status: "not_measured", findings: 0)
      expect(result[:repositories].first).to include(status: "not_measured", reason: "no_linter_ran")
      expect(result[:analyzers_degraded]).to contain_exactly(
        hash_including(repository: "core", analyzer: "RuboCop", status: "unavailable")
      )
      expect(offers.count).to eq(0)
    end

    it "reads output that is not rubocop's JSON as a parse error, not as zero findings" do
      result = ingest({ "ruby" => ran("Could not find gem 'rubocop'") })

      expect(result[:status]).to eq("not_measured")
      expect(result[:linter_statuses]).to eq({ "core" => { "RuboCop" => "parse_error" } })
    end

    it "calls a result that reports no linter at all not measured" do
      result = ingest({})

      expect(result[:status]).to eq("not_measured")
      expect(result[:repositories].first).to include(status: "not_measured", reason: "no_linter_detected")
      expect(result[:analyzers_degraded]).to contain_exactly(
        hash_including(repository: "core", analyzer: "lint", status: "no_linter_detected")
      )
    end

    it "reports a genuinely clean run as completed with nothing degraded" do
      result = ingest({ "ruby" => ran(rubocop_json([])) })

      expect(result).to include(status: "completed", findings: 0)
      expect(result[:analyzers_degraded]).to be_empty
    end

    # D1 re-verify M2: output over the limit files nothing and reads as not
    # measured, never as a parse error and never as a partial "completed".
    it "reads output over the limit as not measured, output_truncated, and files nothing" do
      json = rubocop_json([ offense ])
      SiteSetting.set(Ai::Codebase::StaticAnalysisService::OUTPUT_LIMIT_SETTING, json.bytesize - 1,
                      setting_type: "integer")

      result = ingest({ "ruby" => ran(json) })

      expect(result[:status]).to eq("not_measured")
      expect(result[:linter_statuses]).to eq({ "core" => { "RuboCop" => "output_truncated" } })
      expect(result[:analyzers_degraded]).to contain_exactly(
        hash_including(analyzer: "RuboCop", status: "output_truncated")
      )
      expect(offers.count).to eq(0)
    end

    it "reads a runner that reports its own output as truncated the same way" do
      result = ingest({ "ruby" => { "status" => "output_truncated" } })

      expect(result[:status]).to eq("not_measured")
      expect(result[:linter_statuses]).to eq({ "core" => { "RuboCop" => "output_truncated" } })
    end
  end

  describe "paths" do
    it "reports an eslint finding relative to the directory the linters ran in" do
      eslint = [ { "filePath" => "#{base_path}/src/app.js",
                   "messages" => [ { "line" => 2, "column" => 1, "severity" => 2,
                                     "message" => "x is unused", "ruleId" => "no-unused-vars" } ] } ].to_json

      ingest({ "javascript_lint" => ran(eslint) })

      expect(offers.first.evidence["fingerprint"]).to eq("code_lint|src/app.js|no-unused-vars")
    end
  end

  describe "tenancy" do
    it "refuses a repository of another account, and files nothing" do
      theirs = create(:git_repository, account: create(:account), name: "theirs")

      expect { ingest(repo: theirs) }.to raise_error(ArgumentError, /does not belong/)
      expect(Ai::ImprovementRecommendation.where(recommendation_type: "code_lint").count).to eq(0)
    end

    it "files for the account's own repository" do
      expect(ingest).to include(status: "completed", offers_created: 1)
    end
  end

  # D1b ruling (a): the callback payload must carry no credential.
  describe "the credential the runner was given" do
    let(:credential) { "gta_#{SecureRandom.hex(20)}" }

    it "files nothing when the handed-back output carries it, and records only the fact" do
      output = rubocop_json([ offense ]).sub("Prefer double-quoted strings", "token=#{credential}")

      result = ingest({ "ruby" => ran(output) }, must_not_contain: [ credential ])

      expect(result).to include(status: "failed", failure: "credential_in_payload")
      expect(offers.count).to eq(0)
      expect(audit_rows.last.metadata.to_json).not_to include(credential)
    end

    it "files normally when the output does not carry it" do
      expect(ingest(must_not_contain: [ credential ])).to include(status: "completed", offers_created: 1)
    end
  end

  # Lane 3's finding: discovery built the tool with an account and no
  # principal, which BaseTool records as "unattributed". The stand-in gate
  # below refuses a call with no principal, as a per-action gate would; the
  # REAL tool runs behind it and must still file.
  describe "the principal discovery files under" do
    it "files through the real tool as an explicit internal caller, past a gate that refuses no principal" do
      allow_any_instance_of(Ai::Tools::ImprovementTool).to receive(:execute).and_wrap_original do |original, **kwargs|
        next { success: false, error: "permission denied: no principal" } if original.receiver.send(:principal_kind) == "none"

        original.call(**kwargs)
      end

      expect(ingest).to include(status: "completed", offers_created: 1)
      expect(offers.count).to eq(1)
    end
  end

  describe "grouping and bounding" do
    it "files one offer per (file, rule), carrying the occurrence count" do
      ingest({ "ruby" => ran(rubocop_json([ offense(line: 3), offense(line: 9), offense(line: 14),
                                            offense(cop: "Layout/LineLength", line: 20) ])) })

      expect(offers.count).to eq(2)
      grouped = offers.find { |o| o.evidence["fingerprint"].end_with?("Style/StringLiterals") }
      expect(grouped.evidence["verifier_evidence"]).to include("occurrences" => 3, "lines" => [ 3, 9, 14 ])
    end

    it "caps offers per result at the SiteSetting bound, keeping the most severe" do
      SiteSetting.set(described_class::MAX_OFFERS_SETTING, 2, setting_type: "integer")

      result = ingest({ "ruby" => ran(rubocop_json([ offense(cop: "Info/One", severity: "convention"),
                                                     offense(cop: "Err/One", severity: "error"),
                                                     offense(cop: "Warn/One", severity: "warning") ])) })

      expect(result).to include(findings: 3, offers_created: 2)
      expect(offers.map { |o| o.evidence["fingerprint"].split("|").last }).to contain_exactly("Err/One", "Warn/One")
    end
  end

  # VERIFY BY EXECUTION: the examples above hand #ingest! synthetic JSON. This
  # one hands it the output of a REAL rubocop run on a real file with named
  # violations, as a runner would, and asserts on those cops reaching the queue.
  describe "end to end with a real rubocop's output", :slow do
    # The offending file lives under the repo's own tmp/ and rubocop is pointed
    # at the FILE: its default AllCops/Exclude drops tmp/**/* when a directory
    # is expanded, but honours an explicitly named file. The asserted cops are
    # the ones this repo's omakase config enables.
    it "turns actual rubocop offences into offers naming those cops" do
      probe_dir = Rails.root.join("tmp", "d1b-analyzer-#{SecureRandom.hex(4)}")
      FileUtils.mkdir_p(probe_dir)
      offender = probe_dir.join("offender.rb")
      File.write(offender, "x = [1,2]\nputs x\n")
      relative = offender.relative_path_from(Rails.root).to_s

      begin
        output, status = Open3.capture2("bundle", "exec", "rubocop", "--format", "json", relative,
                                        chdir: Rails.root.to_s)
        result = service.ingest!(repository: repository, base_path: Rails.root.to_s,
                                 linters: { "ruby" => ran(output, exitstatus: status.exitstatus) })

        expect(result[:status]).to eq("completed")
        rules = offers.map { |o| o.evidence["verifier_evidence"]["rule"] }
        expect(rules).to contain_exactly("Layout/SpaceInsideArrayLiteralBrackets", "Layout/SpaceAfterComma")
        expect(offers.first.evidence["files"]).to eq([ relative ])

        # Two offences of the same cop in one file are ONE offer, counted.
        grouped = offers.find { |o| o.evidence["verifier_evidence"]["rule"] == "Layout/SpaceInsideArrayLiteralBrackets" }
        expect(grouped.evidence["verifier_evidence"]["occurrences"]).to eq(2)
      ensure
        FileUtils.remove_entry(probe_dir) if Dir.exist?(probe_dir)
      end
    end
  end
end
