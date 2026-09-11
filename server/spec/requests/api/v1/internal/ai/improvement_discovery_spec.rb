# frozen_string_literal: true

require "rails_helper"

# D1 — the seam the weekly cron drives, after the review's fixes.
#
# H2: one UNIT per call (a repository, or an account with none), walked by
# position through the worker's non-retrying client, so no call sweeps the
# fleet and nothing re-sends a sweep. M1: the answer is aggregate counts only.
# The caller is an account-bound worker and this door runs every account's
# units, so the body names no account, repository, environment or error text.
RSpec.describe "Api::V1::Internal::Ai::ImprovementDiscovery", type: :request do
  let(:account) { create(:account) }
  let(:internal_worker) { create(:worker, account: account) }
  let(:internal_headers) do
    { "X-Forwarded-Tls-Client-Cert-Info" => CGI.escape(%(Subject="CN=#{internal_worker.node_instance_id}")) }
  end
  let(:local_path) { Dir.mktmpdir("d1-req") }
  let!(:repository) do
    create(:git_repository, account: account, name: "core", metadata: { "local_path" => local_path })
  end

  after { FileUtils.remove_entry(local_path) if Dir.exist?(local_path) }

  def run_at!(position)
    post "/api/v1/internal/ai/improvement_discovery/run",
         params: { position: position }, headers: internal_headers, as: :json
  end

  def body = JSON.parse(response.body)["data"]

  def units = Ai::Improvement::DiscoveryRunService.units

  # Other factories create accounts of their own, and the walk covers every
  # active account. So each example runs the unit that belongs to THIS
  # account's repository, found by its position in the walk.
  def run_mine!(repo = repository)
    run_at!(units.index([ account.id, repo.id ]))
  end

  def my_audit_rows
    AuditLog.where(action: "ai.improvement_discovery.run", account_id: account.id)
  end

  before do
    SiteSetting.set(Ai::Improvement::DiscoveryRunService::ALLOWED_ROOT_SETTING, local_path,
                    setting_type: "string", is_public: false)
    allow_any_instance_of(Ai::Codebase::StaticAnalysisService).to receive(:analyze).and_return(
      success: true,
      diagnostics: [ { file: "app/models/thing.rb", line: 3, column: 1, severity: "info",
                       message: "Prefer double-quoted strings", rule: "Style/StringLiterals",
                       linter: "RuboCop" } ],
      summary: { linters: { "RuboCop" => { status: "completed" } } }
    )
  end

  it "files one offer on the first tick and none on the second" do
    expect { run_mine! }.to change { Ai::ImprovementRecommendation.where(account: account).count }.by(1)

    expect(response).to have_http_status(:ok)
    expect(body).to include("ran_unit" => true, "status" => "completed", "offers_created" => 1, "offers_deduped" => 0)

    expect { run_mine! }.not_to change { Ai::ImprovementRecommendation.where(account: account).count }
    expect(body).to include("offers_created" => 0, "offers_deduped" => 1)
  end

  # The record stands IN PLACE OF a run table, so it has to carry what that
  # table's columns would have. Each key is pinned by name.
  it "writes one audit run record per unit, carrying the whole summary" do
    expect { run_mine! }.to change { my_audit_rows.count }.by(1)

    metadata = my_audit_rows.last.metadata
    expect(metadata).to include(
      "status" => "completed", "findings" => 1, "offers_created" => 1, "offers_deduped" => 0,
      "environment" => "dev", "environment_tier" => 0, "environment_tier_ceiling" => 0,
      "analyzers" => [ "lint" ], "analyzers_degraded" => []
    )
    expect(metadata["linter_statuses"]).to eq({ "core" => { "RuboCop" => "completed" } })
    expect(metadata["repository_ids"]).to eq([ repository.id ])
    expect(metadata["started_at"]).to be_present
    expect(metadata["finished_at"]).to be_present
    expect(metadata["duration_ms"]).to be_a(Integer)
  end

  it "records a linter that never ran as not measured, never as a clean sweep" do
    allow_any_instance_of(Ai::Codebase::StaticAnalysisService).to receive(:analyze).and_return(
      success: true, diagnostics: [], summary: { linters: { "RuboCop" => { status: "no_gemfile" } } }
    )

    run_mine!

    expect(body).to include("status" => "not_measured", "analyzers_degraded" => 1)
    metadata = my_audit_rows.last.metadata
    expect(metadata["status"]).to eq("not_measured")
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
      run_mine!
      first = my_audit_rows.last
      run_mine!

      latest = Ai::Improvement::DiscoveryRun.last_for(account)
      expect(latest.id).not_to eq(first.id)
      expect(Ai::Improvement::DiscoveryRun.last_summary_for(account))
        .to include("status" => "completed", "offers_deduped" => 1)
      expect(Ai::Improvement::DiscoveryRun.recent(account, limit: 5).count).to eq(2)
    end

    it "reports WHY the last run declined, not just that it ran" do
      account.update!(ai_suspended: true)
      run_mine!

      expect(Ai::Improvement::DiscoveryRun.last_summary_for(account))
        .to include("status" => "skipped", "skipped_reason" => "ai_suspended")
    end
  end

  it "files nothing while the account kill switch is on, and still records the unit" do
    account.update!(ai_suspended: true)

    expect { run_mine! }.not_to change { Ai::ImprovementRecommendation.count }
    expect(body).to include("status" => "skipped", "offers_created" => 0)
    expect(my_audit_rows.last.metadata).to include("status" => "skipped", "skipped_reason" => "ai_suspended")
  end

  it "reports a skipped repository rather than a silent clean unit" do
    repository.update!(metadata: {})

    expect { run_mine! }.not_to change { Ai::ImprovementRecommendation.count }
    expect(body["status"]).to eq("skipped")
    expect(my_audit_rows.last.metadata["repositories"]).to contain_exactly(
      hash_including("repository" => "core", "status" => "skipped", "reason" => "no_local_path")
    )
  end

  # D1 review M1 and L4. PLANT AND GREP: another tenant's repository name, its
  # account id, and the text of an exception its run raises must reach no
  # response. The failure is recorded in that tenant's audit row by CLASS.
  it "answers aggregate counts only, for every unit, and records a failure by class" do
    other = create(:account)
    create(:git_repository, account: other, name: "acme-secret-repo", metadata: {})
    planted = "planted-exception-text /srv/acme/secret"
    allow_any_instance_of(Ai::Improvement::DiscoveryRunService).to receive(:run!).and_wrap_original do |original, **kwargs|
      raise planted if original.receiver.send(:account).id == other.id

      original.call(**kwargs)
    end

    bodies = units.each_index.map do |position|
      run_at!(position)
      response.body
    end

    bodies.each do |text|
      expect(text).not_to include("acme-secret-repo", planted, other.id, account.id, repository.id)
      expect(JSON.parse(text)["data"].keys).to match_array(
        %w[ran_unit status findings offers_created offers_deduped offers_parked
           analyzers_degraded position next_position remaining done]
      )
    end
    failed = AuditLog.where(action: "ai.improvement_discovery.run", account_id: other.id).last
    expect(failed.metadata).to include("status" => "failed", "failure" => "RuntimeError")
    expect(failed.metadata.to_json).not_to include(planted)
  end

  it "says when the walk is over, on the last unit and past it" do
    last = units.size - 1

    run_at!(last)
    expect(body).to include("ran_unit" => true, "remaining" => 0, "done" => true)

    run_at!(last + 1)
    expect(body).to include("ran_unit" => false, "remaining" => 0, "done" => true)
  end

  it "refuses a position that is not a non-negative integer, and accepts zero" do
    run_at!(-1)
    expect(response).to have_http_status(:unprocessable_content)

    run_at!("abc")
    expect(response).to have_http_status(:unprocessable_content)

    run_at!(0)
    expect(response).to have_http_status(:ok)
  end

  it "rejects an unauthenticated request" do
    post "/api/v1/internal/ai/improvement_discovery/run"

    expect(response).to have_http_status(:unauthorized).or have_http_status(:forbidden)
  end
end
