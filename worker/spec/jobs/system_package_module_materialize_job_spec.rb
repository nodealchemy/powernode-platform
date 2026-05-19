# frozen_string_literal: true

require "rails_helper"

# Audit plan P0.2 — worker job spec.
RSpec.describe SystemPackageModuleMaterializeJob, type: :job do
  subject { described_class }

  it_behaves_like "a base job", described_class
  it_behaves_like "a job with API communication"
  it_behaves_like "a job with logging"

  let(:job) { described_class.new }
  let(:account_id) { "acct-#{SecureRandom.hex(4)}" }
  let(:repository_id) { "repo-#{SecureRandom.hex(4)}" }
  let(:package_name) { "nginx" }
  let(:architectures) { %w[amd64 arm64] }
  let(:recommends) { [] }
  let(:user_id) { "user-#{SecureRandom.hex(4)}" }
  let(:job_args) do
    [account_id, repository_id, package_name, architectures, recommends, user_id, nil]
  end
  let(:api_client) { instance_double(BackendApiClient) }

  before { allow(job).to receive(:api_client).and_return(api_client) }

  describe "#execute" do
    let(:endpoint) { "/api/v1/system/worker_api/package_modules/materialize" }

    context "successful materialization" do
      let(:response) do
        { "data" => { "success" => true, "top_level_module_id" => "mod-1",
                      "dependency_count" => 4, "build_dispatches" => ["disp-1"] } }
      end

      before do
        allow(api_client).to receive(:post)
          .with(endpoint, hash_including(account_id: account_id, repository_id: repository_id,
                                          package_name: package_name))
          .and_return(response)
      end

      it "POSTs the materialize endpoint with all 7 positional args mapped to body" do
        job.execute(*job_args)
        expect(api_client).to have_received(:post).with(
          endpoint,
          hash_including(account_id: account_id, repository_id: repository_id,
                         package_name: package_name, architectures: architectures,
                         recommends_selected: recommends, requested_by_user_id: user_id,
                         category_id: nil)
        )
      end

      it "returns the response data hash" do
        result = job.execute(*job_args)
        expect(result).to include("success" => true)
      end
    end

    context "API error" do
      before do
        allow(api_client).to receive(:post)
          .with(endpoint, anything)
          .and_raise(BackendApiClient::ApiError.new("server down"))
      end

      it "re-raises so Sidekiq retries" do
        expect { job.execute(*job_args) }.to raise_error(BackendApiClient::ApiError, /server down/)
      end
    end
  end
end
