# frozen_string_literal: true

require "rails_helper"

RSpec.describe Git::PipelineSyncSchedulerJob, type: :job do
  let(:job) { described_class.new }
  let(:api_client) { instance_double(BackendApiClient) }

  before do
    mock_powernode_worker_config
    allow(job).to receive(:api_client).and_return(api_client)
    allow(job).to receive(:log_info)
    allow(job).to receive(:log_error)
  end

  it "runs on the services queue" do
    expect(described_class.sidekiq_options["queue"].to_s).to eq("services")
  end

  it "triggers the server sync_all_pipelines endpoint and returns the enqueued count" do
    expect(api_client).to receive(:post)
      .with("/api/v1/internal/git/repositories/sync_all_pipelines")
      .and_return("data" => { "enqueued" => 3 })

    expect(job.execute[:enqueued]).to eq(3)
  end
end
