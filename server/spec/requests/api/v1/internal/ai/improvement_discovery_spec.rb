# frozen_string_literal: true

require "rails_helper"

# D1 / D1b — the seam the weekly cron drives.
#
# H2: one UNIT per call, walked by position through the worker's non-retrying
# client, so nothing re-sends a unit. D1b: a unit is one ACCOUNT, and it hands
# that account's repositories to the registered executor instead of running
# linters in this process. M1: the answer is aggregate counts only. The caller
# is an account-bound worker and this door runs every account's units, so the
# body names no account, repository, environment or error text.
RSpec.describe "Api::V1::Internal::Ai::ImprovementDiscovery", type: :request do
  let(:account) { create(:account) }
  let(:internal_worker) { create(:worker, account: account) }
  let(:internal_headers) do
    { "X-Forwarded-Tls-Client-Cert-Info" => CGI.escape(%(Subject="CN=#{internal_worker.node_instance_id}")) }
  end
  let!(:repository) { create(:git_repository, account: account, name: "core") }

  # The account ids the stand-in executor was handed, in call order.
  let(:dispatched) { [] }
  let(:executor) do
    calls = dispatched
    Object.new.tap do |stand_in|
      stand_in.define_singleton_method(:dispatch!) do |account:, repositories:|
        calls << account.id
        { status: "dispatched", run_ref: "lease-1",
          repositories: repositories.map { |repo| { id: repo.id, status: "dispatched" } } }
      end
    end
  end

  def register(executor)
    allow(Powernode::ExtensionRegistry).to receive(:provider)
      .with(Ai::Improvement::DiscoveryRunService::EXECUTOR_KEY).and_return(executor)
  end

  before do
    allow(Powernode::ExtensionRegistry).to receive(:provider).and_call_original
    register(executor)
  end

  def run_at!(position)
    post "/api/v1/internal/ai/improvement_discovery/run",
         params: { position: position }, headers: internal_headers, as: :json
  end

  def body = JSON.parse(response.body)["data"]

  def units = Ai::Improvement::DiscoveryRunService.units

  # Other factories create accounts of their own, and the walk covers every
  # active account. So each example runs THIS account's unit, found by its
  # position in the walk.
  def run_mine!
    run_at!(units.index(account.id))
  end

  def my_audit_rows
    AuditLog.where(action: "ai.improvement_discovery.run", account_id: account.id)
  end

  it "dispatches this account's repositories on its unit and answers aggregate counts" do
    run_mine!

    expect(response).to have_http_status(:ok)
    expect(body).to include("ran_unit" => true, "status" => "dispatched", "findings" => 0, "offers_created" => 0)
    expect(dispatched).to eq([ account.id ])
  end

  # The record stands IN PLACE OF a run table, so it has to carry what that
  # table's columns would have. Each key is pinned by name.
  it "writes one audit run record per unit, carrying the whole dispatch summary" do
    expect { run_mine! }.to change { my_audit_rows.count }.by(1)

    metadata = my_audit_rows.last.metadata
    expect(metadata).to include(
      "phase" => "dispatch", "status" => "dispatched", "run_ref" => "lease-1",
      "environment" => "dev", "environment_tier" => 0, "environment_tier_ceiling" => 0,
      "analyzers" => [ "lint" ], "repository_ids" => [ repository.id ]
    )
    expect(metadata["started_at"]).to be_present
    expect(metadata["finished_at"]).to be_present
    expect(metadata["duration_ms"]).to be_a(Integer)
  end

  it "records a core-mode unit as skipped with no_discovery_executor" do
    register(nil)

    run_mine!

    expect(body["status"]).to eq("skipped")
    expect(my_audit_rows.last.metadata).to include("status" => "skipped", "skipped_reason" => "no_discovery_executor")
    expect(dispatched).to be_empty
  end

  describe "reading the run history back" do
    it "answers nil for an account discovery has never run for" do
      expect(Ai::Improvement::DiscoveryRun.last_for(create(:account))).to be_nil
      expect(Ai::Improvement::DiscoveryRun.last_summary_for(create(:account))).to eq({})
    end

    it "answers with the NEWEST record, whichever phase wrote it" do
      run_mine!
      first = my_audit_rows.last
      Ai::Improvement::DiscoveryRunService.new(account: account).ingest!(
        repository: repository, base_path: "/runner/work/core",
        linters: { "ruby" => { "status" => "unavailable" } }
      )

      latest = Ai::Improvement::DiscoveryRun.last_for(account)
      expect(latest.id).not_to eq(first.id)
      expect(Ai::Improvement::DiscoveryRun.last_summary_for(account))
        .to include("phase" => "ingest", "status" => "not_measured")
      expect(Ai::Improvement::DiscoveryRun.recent(account, limit: 5).count).to eq(2)
    end

    it "reports WHY the last run declined, not just that it ran" do
      account.update!(ai_suspended: true)
      run_mine!

      expect(Ai::Improvement::DiscoveryRun.last_summary_for(account))
        .to include("status" => "skipped", "skipped_reason" => "ai_suspended")
    end
  end

  it "dispatches nothing while the account kill switch is on, and still records the unit" do
    account.update!(ai_suspended: true)

    run_mine!

    expect(body).to include("status" => "skipped", "offers_created" => 0)
    expect(dispatched).to be_empty
    expect(my_audit_rows.last.metadata).to include("status" => "skipped", "skipped_reason" => "ai_suspended")
  end

  # D1 review M1 and L4. PLANT AND GREP: another tenant's repository name, its
  # account id, and the text of an exception its run raises must reach no
  # response. The failure is recorded in that tenant's audit row by CLASS.
  it "answers aggregate counts only, for every unit, and records a failure by class" do
    other = create(:account)
    create(:git_repository, account: other, name: "acme-secret-repo")
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
