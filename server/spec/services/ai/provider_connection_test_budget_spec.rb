# frozen_string_literal: true

require "rails_helper"

# limit_test_timeout used to write a setting nothing read. The connection test's
# HTTP calls must really be bounded by the time left, however long their own
# per-call limits (15 s tags, 30 s chat) are.
RSpec.describe Ai::ProviderManagementService, "connection test budget" do
  let(:account) { create(:account) }
  let(:provider) do
    create(:ai_provider, account: account, provider_type: "ollama", is_active: true,
                         api_base_url: "http://localhost:11434", api_endpoint: "http://localhost:11434",
                         supported_models: [ { "id" => "local-model:1b", "name" => "local-model:1b" } ])
  end
  let(:credential) do
    create(:ai_provider_credential, account: account, provider: provider,
                                    credentials: { "base_url" => "http://localhost:11434" })
  end

  # Records every read timeout the test's HTTP client is configured with.
  def capture_timeouts
    seen = []
    allow_any_instance_of(Net::HTTP).to receive(:read_timeout=).and_wrap_original do |original, value|
      seen << value
      original.call(value)
    end
    seen
  end

  before do
    stub_request(:get, "http://localhost:11434/api/tags").to_return { sleep 0.2; { status: 404, body: "" } }
    stub_request(:post, "http://localhost:11434/api/chat").to_timeout
  end

  it "keeps every probe within the remaining time when a budget is set" do
    seen = capture_timeouts
    service = described_class.new(credential)
    service.limit_test_timeout(1.5)

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = service.test_with_details_simple
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    expect(result[:success]).to be(false)
    expect(seen).not_to be_empty
    expect(seen.max).to be <= 1.5
    expect(seen.last).to be < seen.first # the chat probe got only what the tags probe left
    expect(elapsed).to be < 3
  end

  it "leaves the per-call limits alone when no budget is set" do
    seen = capture_timeouts

    described_class.new(credential).test_with_details_simple

    expect(seen).to include(15, 30)
  end
end
