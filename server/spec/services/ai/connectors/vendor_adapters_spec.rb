# frozen_string_literal: true

require "rails_helper"

# Shared-interface contract for the native vendor tracker adapters (Linear / Jira
# / Sentry). Per-vendor HTTP shape + auth is covered in the dedicated specs
# (linear_adapter_spec / jira_adapter_spec / sentry_adapter_spec). Here we assert
# every adapter honours the registry contract and degrades GRACEFULLY (returns
# { ok: false }, never raises) when its required config is absent.
RSpec.describe "Ai::Connectors native vendor tracker adapters" do
  shared_examples "a native vendor tracker adapter" do |klass, key|
    subject(:adapter) { klass.new }

    it "exposes its registry key and the tracker interface" do
      expect(adapter.name).to eq(key)
      expect(adapter).to respond_to(:create_issue)
      expect(adapter).to respond_to(:report_error)
    end

    it "returns ok:false (never raises) when no vendor config is present" do
      # Force every per-vendor credential to be absent.
      %i[
        linear_api_key linear_team_id
        jira_base_url jira_email jira_api_token jira_project_key
        sentry_dsn
      ].each { |m| allow(Ai::Connectors::TrackerConfig).to receive(m).and_return(nil) }

      result = nil
      expect { result = adapter.create_issue(title: "x", body: "y") }.not_to raise_error
      expect(result[:ok]).to be(false)
    end
  end

  it_behaves_like "a native vendor tracker adapter", Ai::Connectors::LinearAdapter, :linear
  it_behaves_like "a native vendor tracker adapter", Ai::Connectors::JiraAdapter, :jira
  it_behaves_like "a native vendor tracker adapter", Ai::Connectors::SentryAdapter, :sentry
end
