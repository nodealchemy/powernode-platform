# frozen_string_literal: true

require "rails_helper"

# Component status plane, increment A3 — the `ai_provider` core contributor.
RSpec.describe Platform::Status::Contributors::AiProvider do
  subject(:contributor) { described_class.new }

  let(:account) { create(:account) }

  def conditions_for(provider) = contributor.conditions_for(provider)

  def condition_of(conditions, type) = conditions.find { |c| c["type"] == type }

  def reasons(conditions) = conditions.map { |c| c["reason"] }

  # The set of values `Ai::Provider::HealthCheckable#health_status` can actually
  # return, extracted from the method's own source rather than restated here.
  #
  # A restated list is a list that goes stale silently: the day someone adds a
  # fifth health status, a hand-written copy would still pass while the screen
  # started rendering `UnknownStatus` for real providers. Reading the source
  # means that day turns THIS spec red.
  #
  # The extractor is itself asserted (the count check below): if a refactor
  # changes the method's shape so the scan finds nothing, the spec fails loudly
  # instead of passing over an empty set.
  def source_health_statuses
    source = Rails.root.join("app/models/concerns/ai/provider/health_checkable.rb").read
    body = source[/def health_status\b(.*?)^      end$/m]
    raise "could not locate #health_status in health_checkable.rb" if body.nil?

    explicit = body.scan(/return\s+"(\w+)"/).flatten
    implicit = body.scan(/^\s*"(\w+)"\s*$/).flatten
    (explicit + implicit).uniq.sort
  end

  describe "the contract" do
    it "answers the registry key and is account scoped" do
      expect(described_class::KIND).to eq("ai_provider")
      expect(contributor.kind).to eq("ai_provider")
      expect(contributor.account_scoped?).to be(true)
    end

    it "presents a string icon name, a label and a group order" do
      expect(contributor.presentation).to eq(
        "icon" => "Plug", "label" => "AI Provider", "group_order" => 10
      )
    end

    it "links to the provider settings page for that provider" do
      provider = create(:ai_provider, account: account)

      expect(contributor.links_for(provider))
        .to eq([ { "label" => "Provider settings", "path" => "/app/ai/infrastructure/providers/#{provider.id}" } ])
    end

    it "declares no dependencies and no A3 actions" do
      provider = create(:ai_provider, account: account)

      expect(contributor.dependencies_for(provider)).to eq([])
      expect(contributor.actions_for(provider)).to eq([])
    end
  end

  describe "health_status coverage" do
    it "maps every value the source method can return" do
      extracted = source_health_statuses

      # Both arms: the extractor found something AND the table covers it.
      expect(extracted.size).to eq(4), "health_status source scan found #{extracted.inspect}"
      expect(contributor.mapped_values(described_class::HEALTH_CONDITIONS)).to eq(extracted)
    end

    it "gives every mapped value a reason that is not UnknownStatus" do
      provider = create(:ai_provider, account: account)

      described_class::HEALTH_CONDITIONS.each_key do |value|
        allow(provider).to receive(:health_status).and_return(value)
        health = condition_of(conditions_for(provider), "Healthy")

        expect(health).not_to be_nil, "no Healthy condition for health_status=#{value}"
        expect(health["reason"]).not_to eq(Platform::Status::Contributors::EnumConditions::UNKNOWN_REASON),
                                        "health_status=#{value} fell through to UnknownStatus"
      end
    end

    it "reports an out-of-band health status as unknown/UnknownStatus, never ok" do
      provider = create(:ai_provider, account: account)
      allow(provider).to receive(:health_status).and_return("quantum")

      health = condition_of(conditions_for(provider), "Healthy")

      expect(health["status"]).to eq(Platform::Status::Condition::UNKNOWN)
      expect(health["reason"]).to eq("UnknownStatus")
      expect(health["evidence"]["unmapped_value"]).to eq("quantum")
      expect(Platform::Status::Condition.verdict_for(health)).to eq(Platform::ComponentStatus::NOT_MEASURED)
    end

    it "derives ok from a healthy provider and degraded from an unhealthy one" do
      provider = create(:ai_provider, account: account)
      create(:ai_provider_credential, provider: provider, account: account)

      allow(provider).to receive(:health_status).and_return("healthy")
      expect(Platform::Status::Condition.verdict_for_set(conditions_for(provider)))
        .to eq(Platform::ComponentStatus::OK)

      allow(provider).to receive(:health_status).and_return("unhealthy")
      expect(Platform::Status::Condition.verdict_for_set(conditions_for(provider)))
        .to eq(Platform::ComponentStatus::DEGRADED)
    end
  end

  describe "a deactivated provider" do
    let(:provider) { create(:ai_provider, :inactive, account: account) }

    before { create(:ai_provider_credential, provider: provider, account: account) }

    it "is held, and makes no health claim it cannot back" do
      conditions = conditions_for(provider)

      held = condition_of(conditions, "Held")
      expect(held["status"]).to be(true)
      expect(held["reason"]).to eq("Deactivated")
      expect(condition_of(conditions, "Healthy")).to be_nil
      expect(Platform::Status::Condition.verdict_for_set(conditions))
        .to eq(Platform::ComponentStatus::HELD)
    end

    it "is still enumerated — deactivation is intent, not deletion" do
      provider

      expect(enumerate(account).map(&:id)).to include(provider.id)
    end
  end

  describe "credentials" do
    it "is degraded when a provider that requires auth has no active credential" do
      provider = create(:ai_provider, account: account, requires_auth: true)
      allow(provider).to receive(:health_status).and_return("healthy")

      credentialed = condition_of(conditions_for(provider), "Credentialed")

      expect(credentialed["status"]).to be(false)
      expect(credentialed["reason"]).to eq("CredentialMissing")
      expect(Platform::Status::Condition.verdict_for_set(conditions_for(provider)))
        .to eq(Platform::ComponentStatus::DEGRADED)
    end

    it "is ok when the credential exists, and never carries the secret" do
      provider = create(:ai_provider, account: account, requires_auth: true)
      credential = create(:ai_provider_credential, provider: provider, account: account)
      provider.reload

      credentialed = condition_of(conditions_for(provider), "Credentialed")

      expect(credentialed["status"]).to be(true)
      expect(credentialed["reason"]).to eq("CredentialPresent")
      expect(credentialed["evidence"]).to eq("active_credential_count" => 1)
      # The condition must not contain key material in any field.
      expect(credentialed.to_json).not_to include(credential.credentials["api_key"])
    end

    it "is ok with no credential when the provider requires no auth" do
      provider = create(:ai_provider, account: account, requires_auth: false)

      credentialed = condition_of(conditions_for(provider), "Credentialed")

      expect(credentialed["status"]).to be(true)
      expect(credentialed["reason"]).to eq("AuthNotRequired")
    end
  end

  describe "#each_component" do
    it "yields only this account's providers" do
      mine = create(:ai_provider, account: account)
      theirs = create(:ai_provider, account: create(:account))

      expect(enumerate(account).map(&:id)).to eq([ mine.id ])
      expect(enumerate(account).map(&:id)).not_to include(theirs.id)
    end

    it "excludes the synthetic Claude Code recording scope" do
      real = create(:ai_provider, account: account)
      synthetic = create(:ai_provider, account: account)
      synthetic.update_column(
        :metadata,
        (synthetic.metadata || {}).merge("execution_source" => ::Ai::AgentExecution::CLAUDE_CODE_SOURCE)
      )

      ids = enumerate(account).map(&:id)

      expect(ids).to include(real.id)
      expect(ids).not_to include(synthetic.id)
    end

    it "yields nothing without an account" do
      create(:ai_provider, account: account)

      expect(enumerate(nil)).to eq([])
    end
  end

  describe "#observed_at_for" do
    it "reports the source's own check time, not the sweep's" do
      checked_at = 42.minutes.ago.change(usec: 0)
      provider = create(:ai_provider, account: account, health_status: "healthy",
                                      last_health_check: checked_at)
      provider.reload

      expect(contributor.observed_at_for(provider)).to be_within(1.second).of(checked_at)
    end

    it "reports nothing when no check has ever run" do
      provider = create(:ai_provider, account: account)
      provider.update_column(:metadata, {})

      expect(contributor.observed_at_for(provider.reload)).to be_nil
    end
  end

  # Shared by the two describe blocks above that enumerate.
  def enumerate(for_account)
    [].tap { |acc| contributor.each_component(for_account) { |record| acc << record } }
  end
end
