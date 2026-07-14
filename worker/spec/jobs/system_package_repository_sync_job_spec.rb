# frozen_string_literal: true

require "rails_helper"

# Audit plan P0.2 — worker job spec.
RSpec.describe SystemPackageRepositorySyncJob, type: :job do
  subject { described_class }

  it_behaves_like "a base job", described_class
  it_behaves_like "a job with API communication"
  it_behaves_like "a job with logging"

  let(:job) { described_class.new }
  let(:job_args) { nil }
  let(:api_client) { instance_double(BackendApiClient) }

  before { allow(job).to receive(:api_client).and_return(api_client) }

  describe "#execute" do
    let(:endpoint) { "/api/v1/system/worker_api/package_repositories/sync" }

    context "happy path" do
      let(:response) { { "data" => { "repositories_synced" => 4, "packages_added" => 12 } } }

      before { allow(api_client).to receive(:post).with(endpoint, {}).and_return(response) }

      it "POSTs the repository sync endpoint" do
        result = job.execute
        expect(result).to be_a(Hash)
        expect(result).not_to include(:error)
        expect(api_client).to have_received(:post).with(endpoint, {})
      end
    end

    context "API error" do
      before do
        allow(api_client).to receive(:post).with(endpoint, {})
          .and_raise(BackendApiClient::ApiError.new("apt mirror down"))
      end

      it "returns ok: false" do
        expect(job.execute).to include(ok: false)
      end
    end

    context "on-demand single-repo sync (repo id arg from the Sync-now button)" do
      let(:repo_id) { "019f6000-0000-7000-8000-000000000000" }
      let(:response) { { "data" => { "tick_count" => 1, "results" => [ { "ok" => true, "upserted" => 3 } ] } } }

      before { allow(api_client).to receive(:post).with(endpoint, { repository_id: repo_id, force: false }).and_return(response) }

      it "POSTs only that repository id and does NOT take the global daily lock" do
        expect(job).not_to receive(:acquire_lock)
        result = job.execute(repo_id)
        expect(api_client).to have_received(:post).with(endpoint, { repository_id: repo_id, force: false })
        expect(result).to include(on_demand: true, repository_id: repo_id)
      end

      it "forwards force from the opts hash" do
        allow(api_client).to receive(:post).with(endpoint, { repository_id: repo_id, force: true }).and_return(response)
        job.execute(repo_id, { "force" => true })
        expect(api_client).to have_received(:post).with(endpoint, { repository_id: repo_id, force: true })
      end
    end
  end
end
