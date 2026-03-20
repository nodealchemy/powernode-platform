# frozen_string_literal: true

require "spec_helper"

RSpec.describe TradingOverseerCycleJob, type: :job do
  include_examples "a base job", TradingOverseerCycleJob

  describe "#execute" do
    let(:job) { described_class.new }

    before do
      mock_powernode_worker_config
      allow_logging_methods
    end

    it "fetches active portfolios and runs decision cycle per account" do
      api_client = double("BackendApiClient")
      allow(BackendApiClient).to receive(:new).and_return(api_client)

      allow(api_client).to receive(:get).with("/api/v1/internal/trading/active_portfolios").and_return({
        "data" => {
          "items" => [
            { "account_id" => "acct-1", "id" => "port-1" },
            { "account_id" => "acct-2", "id" => "port-2" }
          ]
        }
      })

      allow(api_client).to receive(:post).with("/api/v1/internal/trading/overseer_decision_cycle", anything)
        .and_return({ "data" => { "decisions_made" => 0 } })

      job.execute

      expect(api_client).to have_received(:post).with(
        "/api/v1/internal/trading/overseer_decision_cycle",
        hash_including(account_id: "acct-1")
      )
      expect(api_client).to have_received(:post).with(
        "/api/v1/internal/trading/overseer_decision_cycle",
        hash_including(account_id: "acct-2")
      )
    end

    it "deduplicates account IDs" do
      api_client = double("BackendApiClient")
      allow(BackendApiClient).to receive(:new).and_return(api_client)

      allow(api_client).to receive(:get).and_return({
        "data" => {
          "items" => [
            { "account_id" => "acct-1", "id" => "port-1" },
            { "account_id" => "acct-1", "id" => "port-2" }
          ]
        }
      })

      allow(api_client).to receive(:post).and_return({ "data" => { "decisions_made" => 0 } })

      job.execute

      expect(api_client).to have_received(:post).with(
        "/api/v1/internal/trading/overseer_decision_cycle", anything
      ).once
    end

    it "handles empty portfolio list" do
      api_client = double("BackendApiClient")
      allow(BackendApiClient).to receive(:new).and_return(api_client)
      allow(api_client).to receive(:get).and_return({ "data" => { "items" => [] } })

      expect { job.execute }.not_to raise_error
    end

    it "handles nil response" do
      api_client = double("BackendApiClient")
      allow(BackendApiClient).to receive(:new).and_return(api_client)
      allow(api_client).to receive(:get).and_return(nil)

      expect { job.execute }.not_to raise_error
    end

    it "isolates errors between account cycles" do
      api_client = double("BackendApiClient")
      allow(BackendApiClient).to receive(:new).and_return(api_client)

      allow(api_client).to receive(:get).and_return({
        "data" => {
          "items" => [
            { "account_id" => "acct-1" },
            { "account_id" => "acct-2" }
          ]
        }
      })

      call_count = 0
      allow(api_client).to receive(:post) do
        call_count += 1
        raise StandardError, "boom" if call_count == 1
        { "data" => { "decisions_made" => 0 } }
      end

      expect { job.execute }.not_to raise_error
      expect(call_count).to eq(2) # both accounts attempted
    end

    it "handles skipped response" do
      api_client = double("BackendApiClient")
      allow(BackendApiClient).to receive(:new).and_return(api_client)

      allow(api_client).to receive(:get).and_return({
        "data" => { "items" => [{ "account_id" => "acct-1" }] }
      })
      allow(api_client).to receive(:post).and_return({
        "data" => { "skipped" => true, "reason" => "cooldown" }
      })

      expect { job.execute }.not_to raise_error
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
