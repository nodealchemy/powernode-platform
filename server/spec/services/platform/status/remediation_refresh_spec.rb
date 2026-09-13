# frozen_string_literal: true

require "rails_helper"

RSpec.describe Platform::Status::RemediationRefresh do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:cs) { Platform::ComponentStatus }

  before do
    Platform::Remediation::Registry.reset!
    Platform::Runbook::Registry.reset!
    Platform::Status::SignalSources.reset!
  end

  after do
    Platform::Remediation::Registry.reset!
    Platform::Runbook::Registry.reset!
    Platform::Status::SignalSources.reset!
  end

  def fact(kind: "instance.silent", **overrides)
    { signal_kind: kind, fingerprint: "fp-1", stuck: false }.merge(overrides)
  end

  # A refresh that cannot see is not a refresh that saw nothing. With no
  # source registered every component would derive `none`, which is
  # indistinguishable from "we looked" and would overwrite whatever the last
  # real source wrote.
  describe "with no signal source registered" do
    it "skips instead of stamping none over the fleet" do
      component = create(:platform_component_status, account: account,
                                                     remediation: { "state" => cs::REMEDIATION_STUCK })

      result = described_class.run!(account)

      expect(result[:skipped]).to be true
      expect(result[:reason]).to eq(described_class::NO_SOURCES)
      expect(result[:refreshed]).to eq(0)
      expect(component.reload.remediation["state"]).to eq(cs::REMEDIATION_STUCK)
    end
  end

  describe "with a signal source registered" do
    it "derives and persists a state for every component in the account" do
      a = create(:platform_component_status, account: account, component_ref: "a")
      b = create(:platform_component_status, account: account, component_ref: "b")
      Platform::Status::SignalSources.register(->(component) { component.component_ref == "a" ? [ fact ] : [] })

      result = described_class.run!(account)

      expect(result[:skipped]).to be false
      expect(result[:refreshed]).to eq(2)
      expect(a.reload.remediation["state"]).to eq(cs::REMEDIATION_NOT_ACTUATABLE)
      expect(b.reload.remediation["state"]).to eq(cs::REMEDIATION_NONE)
      expect(result[:states]).to eq(cs::REMEDIATION_NOT_ACTUATABLE => 1, cs::REMEDIATION_NONE => 1)
    end

    it "includes the shared (null-account) rows" do
      shared = create(:platform_component_status, :shared, component_ref: "shared-thing")
      Platform::Status::SignalSources.register(->(_component) { [ fact ] })

      described_class.run!(account)

      expect(shared.reload.remediation["state"]).to eq(cs::REMEDIATION_NOT_ACTUATABLE)
    end

    # A global scope would re-derive another tenant's components purely
    # because this one was swept.
    it "leaves another account's rows alone" do
      theirs = create(:platform_component_status, account: other_account, component_ref: "theirs")
      Platform::Status::SignalSources.register(->(_component) { [ fact ] })

      described_class.run!(account)

      expect(theirs.reload.remediation).to eq({})
    end

    it "accepts an account id as well as an account" do
      component = create(:platform_component_status, account: account)
      Platform::Status::SignalSources.register(->(_c) { [ fact ] })

      result = described_class.run!(account.id)

      expect(result[:account_id]).to eq(account.id)
      expect(component.reload.remediation["state"]).to eq(cs::REMEDIATION_NOT_ACTUATABLE)
    end
  end

  describe "a partial failure" do
    # A partial refresh must be visible as a partial refresh, not as a
    # smaller fleet.
    it "reports the failing row and still refreshes the rest" do
      good = create(:platform_component_status, account: account, component_ref: "good")
      bad = create(:platform_component_status, account: account, component_ref: "bad")
      Platform::Status::SignalSources.register(->(_c) { [ fact ] })

      allow(Platform::Status::RemediationState).to receive(:derive).and_call_original
      allow(Platform::Status::RemediationState)
        .to receive(:derive).with(having_attributes(component_ref: "bad"), anything)
        .and_raise(ActiveRecord::RecordInvalid.new(bad))

      result = described_class.run!(account)

      expect(result[:refreshed]).to eq(1)
      expect(result[:errors].map { |e| e[:component_ref] }).to eq([ "bad" ])
      expect(good.reload.remediation["state"]).to eq(cs::REMEDIATION_NOT_ACTUATABLE)
    end
  end

  describe "a raising signal source" do
    it "is skipped, and the component derives from the sources that answered" do
      component = create(:platform_component_status, account: account)
      Platform::Status::SignalSources.register(->(_c) { raise "source is down" })
      Platform::Status::SignalSources.register(->(_c) { [ fact(stuck: true) ] })

      allow(Rails.logger).to receive(:error)
      result = described_class.run!(account)

      expect(result[:refreshed]).to eq(1)
      expect(component.reload.remediation["state"]).to eq(cs::REMEDIATION_STUCK)
    end
  end
end
