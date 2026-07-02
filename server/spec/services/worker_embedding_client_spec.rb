# frozen_string_literal: true

require "rails_helper"

RSpec.describe WorkerEmbeddingClient do
  subject(:client) { described_class.new }

  let(:worker_url) { Rails.application.config.worker_url.chomp("/") }

  before do
    allow(WorkerJobService).to receive(:system_worker_jwt).and_return("test-jwt")
  end

  describe "#generate" do
    it "returns the embedding from the worker" do
      stub_request(:post, "#{worker_url}/api/v1/embeddings/generate")
        .to_return(status: 200, body: { "embedding" => [0.1, 0.2] }.to_json)

      expect(client.generate("hello", account_id: "acct-1")).to eq([0.1, 0.2])
    end

    it "returns nil on a non-2xx response" do
      stub_request(:post, "#{worker_url}/api/v1/embeddings/generate")
        .to_return(status: 500, body: "boom")
      allow(Rails.logger).to receive(:error)

      expect(client.generate("hello", account_id: "acct-1")).to be_nil
      expect(Rails.logger).to have_received(:error).with(/Request failed \(500\)/)
    end

    it "returns nil when the worker is unreachable" do
      stub_request(:post, "#{worker_url}/api/v1/embeddings/generate").to_raise(Errno::ECONNREFUSED)
      allow(Rails.logger).to receive(:error)

      expect(client.generate("hello", account_id: "acct-1")).to be_nil
    end
  end

  describe "#generate_batch" do
    it "returns the embeddings array, defaulting to [] on failure" do
      stub_request(:post, "#{worker_url}/api/v1/embeddings/batch")
        .to_return(status: 200, body: { "embeddings" => [[0.1], [0.2]] }.to_json)

      expect(client.generate_batch(%w[a b], account_id: "acct-1")).to eq([[0.1], [0.2]])
    end

    it "returns [] on a non-2xx response" do
      stub_request(:post, "#{worker_url}/api/v1/embeddings/batch").to_return(status: 502, body: "")
      allow(Rails.logger).to receive(:error)

      expect(client.generate_batch(%w[a b], account_id: "acct-1")).to eq([])
    end
  end
end
