# frozen_string_literal: true

require "spec_helper"

RSpec.describe TradingTrainingSessionRunnerJob, type: :job do
  include_examples "a base job", TradingTrainingSessionRunnerJob

  describe "#execute" do
    let(:job) { described_class.new }
    let(:redis_double) { double("Redis") }

    before do
      mock_powernode_worker_config
      allow_logging_methods
      allow(Sidekiq).to receive(:redis).and_yield(redis_double)
      allow(redis_double).to receive(:keys).and_return([])
      allow(redis_double).to receive(:get).and_return(nil)
      allow(redis_double).to receive(:set).and_return(true)
      allow(redis_double).to receive(:del)
      allow(redis_double).to receive(:call).and_return(0)
      allow(redis_double).to receive(:ttl).and_return(-1)
      stub_const("TradingTrainingSessionJob", Class.new { def self.perform_async(*); end })
      stub_const("TradingTrainingSessionJob::LOCK_TTL", 1800)
      allow(TradingTrainingSessionJob).to receive(:perform_async)
    end

    it "fetches pending training sessions from API" do
      api_client = double("BackendApiClient")
      allow(BackendApiClient).to receive(:new).and_return(api_client)
      allow(api_client).to receive(:get).and_return({ "data" => { "items" => [] } })

      job.execute

      expect(api_client).to have_received(:get).with("/api/v1/internal/trading/pending_training_sessions")
    end

    it "dispatches sessions without locks" do
      api_client = double("BackendApiClient")
      allow(BackendApiClient).to receive(:new).and_return(api_client)
      allow(api_client).to receive(:get).and_return({
        "data" => {
          "items" => [
            { "id" => "sess-1", "status" => "pending", "name" => "Test", "completed_ticks" => 0, "created_at" => 10.minutes.ago.iso8601 }
          ]
        }
      })

      result = job.execute

      expect(TradingTrainingSessionJob).to have_received(:perform_async).with("sess-1")
      expect(result[:dispatched]).to include("sess-1")
    end

    it "skips sessions with active locks" do
      api_client = double("BackendApiClient")
      allow(BackendApiClient).to receive(:new).and_return(api_client)
      allow(api_client).to receive(:get).and_return({
        "data" => {
          "items" => [
            { "id" => "sess-1", "status" => "pending", "created_at" => 10.minutes.ago.iso8601 }
          ]
        }
      })

      # Lock exists with dispatching value
      allow(redis_double).to receive(:get).with("training_session_lock:sess-1").and_return("dispatching")

      result = job.execute

      expect(TradingTrainingSessionJob).not_to have_received(:perform_async)
    end

    it "skips recently-created pending sessions with active locks" do
      api_client = double("BackendApiClient")
      allow(BackendApiClient).to receive(:new).and_return(api_client)
      allow(api_client).to receive(:get).and_return({
        "data" => {
          "items" => [
            { "id" => "sess-1", "status" => "pending", "created_at" => 30.seconds.ago.iso8601 }
          ]
        }
      })

      # Redis EXISTS returns 1 (lock exists)
      allow(redis_double).to receive(:call).with("EXISTS", "training_session_lock:sess-1").and_return(1)

      result = job.execute

      expect(TradingTrainingSessionJob).not_to have_received(:perform_async)
    end

    it "dispatches recently-created sessions without locks (worker restart recovery)" do
      api_client = double("BackendApiClient")
      allow(BackendApiClient).to receive(:new).and_return(api_client)
      allow(api_client).to receive(:get).and_return({
        "data" => {
          "items" => [
            { "id" => "sess-1", "status" => "pending", "name" => "Test", "completed_ticks" => 0, "created_at" => 30.seconds.ago.iso8601 }
          ]
        }
      })

      # No lock exists
      allow(redis_double).to receive(:call).with("EXISTS", "training_session_lock:sess-1").and_return(0)

      result = job.execute

      expect(TradingTrainingSessionJob).to have_received(:perform_async).with("sess-1")
    end

    it "handles lock race condition" do
      api_client = double("BackendApiClient")
      allow(BackendApiClient).to receive(:new).and_return(api_client)
      allow(api_client).to receive(:get).and_return({
        "data" => {
          "items" => [
            { "id" => "sess-1", "status" => "pending", "created_at" => 10.minutes.ago.iso8601 }
          ]
        }
      })

      # First get returns nil, but set NX fails (race)
      allow(redis_double).to receive(:set).with("training_session_lock:sess-1", anything, anything).and_return(false)

      result = job.execute

      expect(TradingTrainingSessionJob).not_to have_received(:perform_async)
    end

    it "handles empty session list" do
      api_client = double("BackendApiClient")
      allow(BackendApiClient).to receive(:new).and_return(api_client)
      allow(api_client).to receive(:get).and_return({ "data" => { "items" => [] } })

      result = job.execute

      expect(result[:pending_count]).to eq(0)
      expect(result[:dispatched]).to be_empty
    end

    it "handles connection failure gracefully" do
      api_client = double("BackendApiClient")
      allow(BackendApiClient).to receive(:new).and_return(api_client)
      allow(api_client).to receive(:get).and_raise(Faraday::ConnectionFailed.new("refused"))

      expect { job.execute }.not_to raise_error
    end

    it "handles API error gracefully" do
      api_client = double("BackendApiClient")
      allow(BackendApiClient).to receive(:new).and_return(api_client)
      allow(api_client).to receive(:get).and_raise(BackendApiClient::ApiError.new("Error", 500))

      expect { job.execute }.not_to raise_error
    end
  end
end
