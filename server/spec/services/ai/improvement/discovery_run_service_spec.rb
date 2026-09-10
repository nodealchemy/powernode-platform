# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

# D1 — the discovery clock. Audit 2026-09-10 §6.2: improvement discovery had no
# scheduled driver and `discover_improvements` is guidance text, not an analyzer.
#
# BOTH ARMS everywhere: a gate that only ever refuses and a gate that only ever
# allows are the same defect. Each gate below is asserted refusing AND passing.
RSpec.describe Ai::Improvement::DiscoveryRunService, type: :service do
  let(:account) { create(:account) }
  let(:local_path) { Dir.mktmpdir("d1-repo") }
  let!(:repository) do
    create(:git_repository, account: account, name: "core", metadata: { "local_path" => local_path })
  end

  after { FileUtils.remove_entry(local_path) if Dir.exist?(local_path) }

  # The one external boundary: a subprocess (rubocop/tsc/eslint). Everything
  # inside the service runs for real. One example below runs the REAL analyzer.
  def stub_analysis(diagnostics, linters: { "RuboCop" => { status: "completed" } })
    allow_any_instance_of(Ai::Codebase::StaticAnalysisService).to receive(:analyze).and_return(
      success: true,
      diagnostics: diagnostics,
      summary: { total: diagnostics.size, errors: 0, warnings: 0, linters: linters }
    )
  end

  def diagnostic(file: "app/models/thing.rb", rule: "Style/StringLiterals", severity: "info", line: 3)
    { file: file, line: line, column: 1, severity: severity,
      message: "Prefer double-quoted strings", rule: rule, linter: "RuboCop" }
  end

  def offers
    Ai::ImprovementRecommendation.where(account: account, recommendation_type: "code_lint")
  end

  describe "the D1 oracle: one tick files one offer, a second tick files none" do
    before { stub_analysis([ diagnostic ]) }

    it "files exactly one offer for a seeded lint violation" do
      result = described_class.new(account: account).run!

      expect(result[:status]).to eq("completed")
      expect(result[:offers_created]).to eq(1)
      expect(offers.count).to eq(1)
      expect(offers.first.evidence["fingerprint"]).to eq("code_lint|app/models/thing.rb|Style/StringLiterals")
    end

    it "files zero NEW offers on a second tick and reports the dedupe" do
      described_class.new(account: account).run!
      second = described_class.new(account: account).run!

      expect(offers.count).to eq(1)
      expect(second[:offers_created]).to eq(0)
      expect(second[:offers_deduped]).to eq(1)
    end
  end

  describe "kill switch" do
    before { stub_analysis([ diagnostic ]) }

    it "files nothing and says why when the account is suspended" do
      account.update!(ai_suspended: true)

      result = described_class.new(account: account).run!

      expect(result).to include(status: "skipped", skipped_reason: "ai_suspended")
      expect(offers.count).to eq(0)
    end

    it "files when the account is NOT suspended" do
      expect(described_class.new(account: account).run!).to include(status: "completed")
      expect(offers.count).to eq(1)
    end
  end

  describe "environment ceiling" do
    before { stub_analysis([ diagnostic ]) }

    # Accounts are seeded with the DEFAULTS ladder, `dev` (tier 0) default.
    it "runs in the default dev plane (tier 0, at the default ceiling)" do
      result = described_class.new(account: account).run!

      expect(result).to include(status: "completed", environment: "dev", environment_tier: 0)
      expect(offers.count).to eq(1)
    end

    it "refuses when the account's default plane sits above the ceiling" do
      Ai::Environment.where(account: account).update_all(is_default: false)
      Ai::Environment.find_by!(account: account, slug: "prod").update!(is_default: true)

      result = described_class.new(account: account).run!

      expect(result).to include(status: "skipped", skipped_reason: "environment_tier_above_ceiling",
                                environment: "prod", environment_tier: 3,
                                environment_tier_ceiling: 0)
      expect(offers.count).to eq(0)
    end

    it "runs in a higher plane once the SiteSetting ceiling is raised" do
      Ai::Environment.where(account: account).update_all(is_default: false)
      Ai::Environment.find_by!(account: account, slug: "prod").update!(is_default: true)
      SiteSetting.set(described_class::MAX_TIER_SETTING, 3, setting_type: "integer")

      expect(described_class.new(account: account).run!).to include(status: "completed", environment: "prod")
      expect(offers.count).to eq(1)
    end
  end

  describe "repository availability" do
    before { stub_analysis([ diagnostic ]) }

    it "skips a repository with no local working copy WITH a reason, not silently" do
      repository.update!(metadata: {})

      result = described_class.new(account: account).run!

      expect(result[:status]).to eq("completed")
      expect(result[:repositories]).to contain_exactly(
        hash_including(repository: "core", status: "skipped", reason: "no_local_path")
      )
      expect(offers.count).to eq(0)
    end

    it "skips a local_path that does not exist on this node" do
      repository.update!(metadata: { "local_path" => "/nonexistent/#{SecureRandom.hex(6)}" })

      result = described_class.new(account: account).run!

      expect(result[:repositories].first).to include(status: "skipped", reason: "no_local_path")
      expect(offers.count).to eq(0)
    end
  end

  # The audit's §4.2 finding for code_static_analysis: the headline `errors: 0`
  # discards a `no_gemfile | no_output` status, so "nothing ran" reads exactly
  # like "nothing found". This service must not repeat that.
  describe "a linter that did not run is not a clean sweep" do
    it "reports a degraded analyzer rather than an empty, healthy-looking run" do
      stub_analysis([], linters: { "RuboCop" => { status: "no_gemfile" } })

      result = described_class.new(account: account).run!

      expect(result[:findings]).to eq(0)
      expect(result[:analyzers_degraded]).to contain_exactly(
        hash_including(repository: "core", analyzer: "RuboCop", status: "no_gemfile")
      )
    end

    it "reports NO degraded analyzer when the linter genuinely completed clean" do
      stub_analysis([], linters: { "RuboCop" => { status: "completed" } })

      result = described_class.new(account: account).run!

      expect(result[:findings]).to eq(0)
      expect(result[:analyzers_degraded]).to be_empty
    end
  end

  describe "grouping and bounding" do
    it "files one offer per (file, rule), carrying the occurrence count" do
      stub_analysis([
        diagnostic(line: 3), diagnostic(line: 9), diagnostic(line: 14),
        diagnostic(rule: "Layout/LineLength", line: 20)
      ])

      result = described_class.new(account: account).run!

      expect(result[:offers_created]).to eq(2)
      offer = offers.find { |o| o.evidence["fingerprint"].end_with?("Style/StringLiterals") }
      expect(offer.evidence["verifier_evidence"]["occurrences"]).to eq(3)
      expect(offer.evidence["verifier_evidence"]["lines"]).to eq([ 3, 9, 14 ])
    end

    it "caps offers per run at the SiteSetting bound, keeping the most severe" do
      SiteSetting.set(described_class::MAX_OFFERS_SETTING, 2, setting_type: "integer")
      stub_analysis([
        diagnostic(rule: "Info/One", severity: "info"),
        diagnostic(rule: "Err/One", severity: "error"),
        diagnostic(rule: "Warn/One", severity: "warning")
      ])

      result = described_class.new(account: account).run!

      expect(result[:findings]).to eq(3)
      expect(result[:offers_created]).to eq(2)
      expect(offers.map { |o| o.evidence["fingerprint"].split("|").last })
        .to contain_exactly("Err/One", "Warn/One")
    end
  end

  # VERIFY BY EXECUTION, not by name: the examples above stub the subprocess, so
  # on their own they prove the wiring is "plumbed" and nothing more. This one
  # runs the REAL StaticAnalysisService against a real file with a real,
  # named violation and asserts on THAT rule reaching the offer queue.
  describe "end to end against the real analyzer", :slow do
    # The offending file lives under the repo's own tmp/ and the analyzer is
    # pointed at the FILE, not its directory: rubocop's default AllCops/Exclude
    # drops tmp/**/* when a directory is expanded, but honours an explicitly
    # named file. Verified by running both forms before writing this.
    #
    # The cops asserted below are the ones this repo's omakase config actually
    # enables, established by running rubocop rather than assumed — most of its
    # enabled cops emit `convention`, which StaticAnalysisService maps to
    # `info`. That is precisely why the service files findings at every
    # severity: an error/warning-only floor would leave a discovery loop that
    # mechanically cannot find anything in this codebase.
    it "turns actual rubocop offences into offers naming those cops" do
      probe_dir = Rails.root.join("tmp", "d1-analyzer-#{SecureRandom.hex(4)}")
      FileUtils.mkdir_p(probe_dir)
      offender = probe_dir.join("offender.rb")
      File.write(offender, "x = [1,2]\nputs x\n")
      repository.update!(metadata: { "local_path" => Rails.root.to_s })

      begin
        relative = offender.relative_path_from(Rails.root).to_s
        allow_any_instance_of(Ai::Codebase::StaticAnalysisService)
          .to receive(:analyze).and_wrap_original { |m, **| m.call(path: relative, linters: [ "ruby" ]) }

        result = described_class.new(account: account).run!

        expect(result[:status]).to eq("completed")
        rules = offers.map { |o| o.evidence["verifier_evidence"]["rule"] }
        expect(rules).to contain_exactly("Layout/SpaceInsideArrayLiteralBrackets", "Layout/SpaceAfterComma")
        expect(offers.first.evidence["files"].first).to include("offender.rb")

        # Two offences of the same cop in one file are ONE offer, counted.
        grouped = offers.find { |o| o.evidence["verifier_evidence"]["rule"] == "Layout/SpaceInsideArrayLiteralBrackets" }
        expect(grouped.evidence["verifier_evidence"]["occurrences"]).to eq(2)
      ensure
        FileUtils.remove_entry(probe_dir) if Dir.exist?(probe_dir)
      end
    end
  end
end
