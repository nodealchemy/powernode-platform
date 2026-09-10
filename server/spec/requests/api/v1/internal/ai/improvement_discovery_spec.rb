# frozen_string_literal: true

require "rails_helper"

# D1 — the seam the weekly cron drives. Audit 2026-09-10 §6.2: improvement
# discovery had no scheduled driver at all.
RSpec.describe "Api::V1::Internal::Ai::ImprovementDiscovery", type: :request do
  let(:account) { create(:account) }
  let(:internal_worker) { create(:worker, account: account) }
  let(:internal_headers) do
    { "X-Forwarded-Tls-Client-Cert-Info" => CGI.escape(%(Subject="CN=#{internal_worker.node_instance_id}")) }
  end

  def run!
    post "/api/v1/internal/ai/improvement_discovery/run", headers: internal_headers
  end

  def body
    JSON.parse(response.body)["data"]
  end

  # Other factories (the worker, the repository credential) create accounts of
  # their own, and the endpoint deliberately sweeps every active account. So
  # every assertion below is scoped to THIS account's run rather than to a
  # global tally, which would be a count of the test DB, not of the behaviour.
  def my_run
    body["runs"].find { |r| r["account_id"] == account.id }
  end

  def my_audit_rows
    AuditLog.where(action: "ai.improvement_discovery.run", account_id: account.id)
  end

  before do
    allow_any_instance_of(Ai::Codebase::StaticAnalysisService).to receive(:analyze).and_return(
      success: true,
      diagnostics: [ { file: "app/models/thing.rb", line: 3, column: 1, severity: "info",
                       message: "Prefer double-quoted strings", rule: "Style/StringLiterals",
                       linter: "RuboCop" } ],
      summary: { linters: { "RuboCop" => { status: "completed" } } }
    )
  end

  context "with an analyzable repository" do
    let(:local_path) { Dir.mktmpdir("d1-req") }

    before do
      create(:git_repository, account: account, name: "core", metadata: { "local_path" => local_path })
    end

    after { FileUtils.remove_entry(local_path) if Dir.exist?(local_path) }

    it "files one offer on the first tick and none on the second" do
      expect { run! }.to change { Ai::ImprovementRecommendation.where(account: account).count }.by(1)

      expect(response).to have_http_status(:ok)
      expect(my_run).to include("status" => "completed", "offers_created" => 1, "offers_deduped" => 0)

      expect { run! }.not_to change { Ai::ImprovementRecommendation.where(account: account).count }
      expect(my_run).to include("offers_created" => 0, "offers_deduped" => 1)
    end

    # The record stands IN PLACE OF a run table, so it has to carry what that
    # table's columns would have. Each key is pinned by name: a summary that
    # quietly stopped emitting one would otherwise still "have a record".
    it "writes one audit run record per tick, carrying the whole summary" do
      expect { run! }.to change { my_audit_rows.count }.by(1)

      metadata = my_audit_rows.last.metadata
      expect(metadata).to include(
        "status" => "completed",
        "findings" => 1,
        "offers_created" => 1,
        "offers_deduped" => 0,
        "environment" => "dev",
        "environment_tier" => 0,
        "environment_tier_ceiling" => 0,
        "analyzers" => [ "lint" ],
        "analyzers_degraded" => []
      )
      expect(metadata["linter_statuses"]).to eq({ "core" => { "RuboCop" => "completed" } })
      expect(metadata["repository_ids"]).to eq([ Devops::GitRepository.find_by(name: "core").id ])
      expect(metadata["started_at"]).to be_present
      expect(metadata["finished_at"]).to be_present
      expect(metadata["duration_ms"]).to be_a(Integer)
    end

    it "records a linter that never ran, so an empty sweep is not a clean one" do
      allow_any_instance_of(Ai::Codebase::StaticAnalysisService).to receive(:analyze).and_return(
        success: true, diagnostics: [],
        summary: { linters: { "RuboCop" => { status: "no_gemfile" } } }
      )

      run!

      metadata = my_audit_rows.last.metadata
      expect(metadata["linter_statuses"]).to eq({ "core" => { "RuboCop" => "no_gemfile" } })
      expect(metadata["analyzers_degraded"])
        .to contain_exactly(hash_including("analyzer" => "RuboCop", "status" => "no_gemfile"))
    end

    describe "reading the run history back" do
      it "answers nil for an account discovery has never run for" do
        expect(Ai::Improvement::DiscoveryRun.last_for(create(:account))).to be_nil
        expect(Ai::Improvement::DiscoveryRun.last_summary_for(create(:account))).to eq({})
      end

      it "answers with the NEWEST run for an account that has one" do
        run!
        first = my_audit_rows.last
        run!

        latest = Ai::Improvement::DiscoveryRun.last_for(account)
        expect(latest).to be_present
        expect(latest.id).not_to eq(first.id)
        expect(Ai::Improvement::DiscoveryRun.last_summary_for(account))
          .to include("status" => "completed", "offers_deduped" => 1)
        expect(Ai::Improvement::DiscoveryRun.recent(account, limit: 5).count).to eq(2)
      end

      it "reports WHY the last run declined, not just that it ran" do
        account.update!(ai_suspended: true)
        run!

        expect(Ai::Improvement::DiscoveryRun.last_summary_for(account))
          .to include("status" => "skipped", "skipped_reason" => "ai_suspended")
      end
    end

    it "files nothing while the account kill switch is on" do
      account.update!(ai_suspended: true)

      expect { run! }.not_to change { Ai::ImprovementRecommendation.count }
      expect(response).to have_http_status(:ok)
      expect(my_run).to include("status" => "skipped", "skipped_reason" => "ai_suspended", "offers_created" => 0)
    end

    # A tick that declined still has to leave a record, or "discovery has not
    # run since Tuesday" is indistinguishable from "discovery ran and refused".
    it "still records a run record for an account it skipped" do
      account.update!(ai_suspended: true)

      expect { run! }.to change { my_audit_rows.count }.by(1)
      expect(my_audit_rows.last.metadata).to include("status" => "skipped", "skipped_reason" => "ai_suspended")
    end
  end

  it "reports a skipped repository rather than a silent clean tick" do
    create(:git_repository, account: account, name: "core", metadata: {})

    expect { run! }.not_to change { Ai::ImprovementRecommendation.count }
    expect(my_run["status"]).to eq("completed")
    expect(my_run["repositories"]).to contain_exactly(
      hash_including("repository" => "core", "status" => "skipped", "reason" => "no_local_path")
    )
  end

  it "rejects an unauthenticated request" do
    post "/api/v1/internal/ai/improvement_discovery/run"

    expect(response).to have_http_status(:unauthorized).or have_http_status(:forbidden)
  end
end
