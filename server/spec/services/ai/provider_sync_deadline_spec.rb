# frozen_string_literal: true

require "rails_helper"

# A sync is bounded by a DEADLINE the HTTP calls honour, never by interrupting
# the thread (Timeout.timeout could land in the middle of a DB write).
RSpec.describe "model sync deadline" do
  let(:account) { create(:account) }
  let(:provider) do
    create(:ai_provider, account: account, provider_type: "ollama", is_active: true,
                         api_base_url: "http://localhost:11434", api_endpoint: "http://localhost:11434")
  end

  def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  describe "Ai::Provider#with_sync_options" do
    it "carries the credential and the deadline, and restores both afterwards" do
      credential = create(:ai_provider_credential, account: account, provider: provider)

      provider.with_sync_options(credential: credential, deadline: now + 3) do
        expect(provider.credential_for_sync).to eq(credential)
        expect(provider.sync_http_timeout(15)).to be_between(0.5, 3)
      end

      expect(provider.sync_http_timeout(15)).to eq(15)
    end

    it "never goes below the half-second floor once the deadline has passed" do
      provider.with_sync_options(deadline: now - 5) do
        expect(provider.sync_http_timeout(15)).to eq(0.5)
        expect(provider.sync_deadline_passed?).to be(true)
      end
    end
  end

  it "skips the remaining Ollama fallback endpoints once past the deadline" do
    stub_request(:get, %r{localhost:11434}).to_timeout

    provider.with_sync_options(deadline: now - 1) do
      Ai::ProviderManagementService.sync_provider_models(provider, force_refresh: true)
    end

    expect(a_request(:get, %r{localhost:11434})).to have_been_made.once
  end

  describe Ai::Providers::ModelSyncAndActivate do
    it "does not use Timeout.timeout (it could interrupt a DB write)" do
      expect(Timeout).not_to receive(:timeout)
      allow(Ai::ProviderManagementService).to receive(:sync_provider_models).and_return(false)

      described_class.call(provider, activate: false, preserve_on_failure: true, budget: true)
    end

    it "lets a slow sync finish, then reports it deferred because the budget is spent" do
      stub_const("Ai::Providers::ModelSyncAndActivate::CREATE_BUDGET_SECONDS", 0.05)
      finished = false
      allow(Ai::ProviderManagementService).to receive(:sync_provider_models) { sleep 0.2; finished = true; false }

      result = described_class.call(provider, activate: false, preserve_on_failure: true, budget: true)

      expect(finished).to be(true)
      expect(result.deferred).to be(true)
      expect(provider.reload.is_active).to be(true)
    end
  end

  describe "credential create" do
    let(:openai) do
      create(:ai_provider, account: account, provider_type: "openai", is_active: false, supported_models: [])
    end

    it "shares the deadline with the connection test: a spent budget skips the test" do
      stub_const("Ai::Providers::ModelSyncAndActivate::CREATE_BUDGET_SECONDS", 0.05)
      allow(Ai::ProviderManagementService).to receive(:sync_provider_models) do
        sleep 0.2
        openai.update_columns(supported_models: [ { "id" => "m1", "name" => "m1" } ])
        true
      end
      test_service = instance_double(Ai::ProviderManagementService)
      allow(Ai::ProviderManagementService).to receive(:new).and_return(test_service)
      allow(test_service).to receive(:test_with_details_simple).and_return({ success: true })

      credential = Ai::ProviderManagementService.create_provider_credential(
        openai, account, { "api_key" => "sk-fake-placeholder-not-real-0001" }
      )

      expect(credential).to be_persisted
      expect(test_service).not_to have_received(:test_with_details_simple)
    end
  end
end
