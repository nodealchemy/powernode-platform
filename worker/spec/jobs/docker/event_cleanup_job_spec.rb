# frozen_string_literal: true

require "spec_helper"

RSpec.describe Docker::EventCleanupJob do
  it_behaves_like "a base job", described_class

  let(:job) { described_class.new }
  let(:api_client) { instance_double(BackendApiClient) }

  before do
    allow(job).to receive(:api_client).and_return(api_client)
    allow(job).to receive(:logger).and_return(Logger.new(nil))
  end

  describe "#execute" do
    context "when cleanup is successful" do
      before do
        allow(api_client).to receive(:post)
          .with("/api/v1/internal/docker/events", { action_type: "cleanup", older_than_days: 30 })
          .and_return({ "data" => { "deleted_count" => 42 } })
      end

      it "calls the internal API with cleanup action_type" do
        job.execute

        expect(api_client).to have_received(:post)
          .with("/api/v1/internal/docker/events", { action_type: "cleanup", older_than_days: 30 })
      end
    end

    context "when no events to clean up" do
      before do
        allow(api_client).to receive(:post)
          .with("/api/v1/internal/docker/events", { action_type: "cleanup", older_than_days: 30 })
          .and_return({ "data" => { "deleted_count" => 0 } })
      end

      it "completes without error" do
        expect { job.execute }.not_to raise_error
      end
    end
  end

  describe "job configuration" do
    it "uses the maintenance queue" do
      expect(described_class.sidekiq_options["queue"]).to eq("maintenance")
    end

    it "retries up to 1 time" do
      expect(described_class.sidekiq_options["retry"]).to eq(1)
    end
  end
end
