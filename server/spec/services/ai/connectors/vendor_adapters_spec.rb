# frozen_string_literal: true

require "rails_helper"

# Thin scaffolding adapters for the named vendors. Full vendor API clients
# (auth + REST) are the documented G8 follow-up — here we only assert the
# interface is present and that they delegate to the generic webhook proxy when
# configured, or raise a clear not-configured error otherwise.
RSpec.describe "Ai::Connectors vendor tracker adapters" do
  shared_examples "a vendor tracker adapter" do |klass, key, label|
    subject(:adapter) { klass.new }

    it "exposes its registry key and the tracker interface" do
      expect(adapter.name).to eq(key)
      expect(adapter).to respond_to(:create_issue)
      expect(adapter).to respond_to(:report_error)
    end

    it "raises a clear not-configured error (pointing at the follow-up) when no proxy URL is set" do
      allow(Ai::Connectors::TrackerConfig).to receive(:endpoint).and_return(nil)

      expect { adapter.create_issue(title: "x", body: "y") }
        .to raise_error(NotImplementedError, /#{label}.*follow-up/m)
    end

    it "delegates to the generic webhook POST when a proxy URL is configured" do
      url = "https://hooks.example.test/#{key}"
      configured = klass.new(url: url)
      stub = stub_request(:post, url).to_return(status: 201, body: { id: "X-1" }.to_json)

      result = configured.create_issue(title: "t", body: "b", severity: "warning", metadata: {})

      expect(result[:ok]).to be(true)
      expect(result[:external_id]).to eq("X-1")
      expect(stub).to have_been_requested
    end
  end

  it_behaves_like "a vendor tracker adapter", Ai::Connectors::LinearAdapter, :linear, "Linear"
  it_behaves_like "a vendor tracker adapter", Ai::Connectors::JiraAdapter, :jira, "Jira"
  it_behaves_like "a vendor tracker adapter", Ai::Connectors::SentryAdapter, :sentry, "Sentry"
end
