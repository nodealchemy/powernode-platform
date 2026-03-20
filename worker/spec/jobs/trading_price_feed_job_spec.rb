# frozen_string_literal: true

require "spec_helper"

RSpec.describe TradingPriceFeedJob, type: :job do
  include_examples "a base job", TradingPriceFeedJob

  describe "#execute" do
    let(:job) { described_class.new }
    let(:api_client) { mock_api_client_success(:post) }

    before do
      mock_powernode_worker_config
      allow_logging_methods
    end

    it "uses default pairs when none provided" do
      api_client = mock_api_client_success(:post, { "success" => true, "data" => { "BTC/USDC" => 50000 } })

      job.execute

      expect(api_client).to have_received(:post).with(
        "/api/v1/internal/trading/fetch_prices",
        hash_including(pairs: TradingPriceFeedJob::DEFAULT_PAIRS)
      )
    end

    it "uses custom pairs when provided" do
      api_client = mock_api_client_success(:post, { "success" => true, "data" => {} })

      job.execute(%w[SOL/USDC])

      expect(api_client).to have_received(:post).with(
        "/api/v1/internal/trading/fetch_prices",
        hash_including(pairs: %w[SOL/USDC])
      )
    end

    it "uses default source coingecko when none provided" do
      api_client = mock_api_client_success(:post, { "success" => true, "data" => {} })

      job.execute

      expect(api_client).to have_received(:post).with(
        "/api/v1/internal/trading/fetch_prices",
        hash_including(source: "coingecko")
      )
    end

    it "uses custom source when provided" do
      api_client = mock_api_client_success(:post, { "success" => true, "data" => {} })

      job.execute(nil, "defillama")

      expect(api_client).to have_received(:post).with(
        "/api/v1/internal/trading/fetch_prices",
        hash_including(source: "defillama")
      )
    end

    it "handles successful response" do
      mock_api_client_success(:post, { "success" => true, "data" => { "BTC/USDC" => 50000 } })

      result = job.execute
      expect(result["success"]).to be true
    end

    it "handles failure response" do
      mock_api_client_success(:post, { "success" => false, "error" => "rate limited" })

      result = job.execute
      expect(result["success"]).to be false
    end

    it "handles connection failure gracefully" do
      api_client = double("BackendApiClient")
      allow(api_client).to receive(:post).and_raise(Faraday::ConnectionFailed.new("Connection refused"))
      allow(BackendApiClient).to receive(:new).and_return(api_client)

      result = job.execute
      expect(result).to be_nil
    end

    it "handles API errors gracefully" do
      api_client = double("BackendApiClient")
      allow(api_client).to receive(:post).and_raise(BackendApiClient::ApiError.new("Server Error", 500))
      allow(BackendApiClient).to receive(:new).and_return(api_client)

      result = job.execute
      expect(result).to be_nil
    end
  end
end
