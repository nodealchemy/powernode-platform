# frozen_string_literal: true

require "rails_helper"

# Component status plane, increment A3 — the `provider_circuit_breaker` core
# contributor over Ai::ProviderCircuitBreakerService.all_provider_stats.
#
# This is the SHARED kind: the source is process-wide Redis state with no
# account anywhere in it, so the rows carry a NULL account. The tenancy oracle
# here is therefore the opposite of every other kind's — it asserts that no
# account is invented.
RSpec.describe Platform::Status::Contributors::ProviderCircuitBreaker do
  subject(:contributor) { described_class.new }

  let(:account) { create(:account) }
  let(:provider_id) { SecureRandom.uuid }
  let(:unknown_reason) { Platform::Status::Contributors::EnumConditions::UNKNOWN_REASON }

  def stats(state: "closed", **overrides)
    {
      service_name: "Test Provider",
      resource_id: "provider:#{provider_id}",
      state: state,
      failure_count: 0,
      success_count: 4,
      consecutive_failures: 0,
      consecutive_successes: 4,
      last_failure_time: nil,
      last_success_time: Time.current,
      state_changed_at: 12.minutes.ago,
      next_retry_at: nil,
      config: {},
      provider_id: provider_id,
      provider_name: "Test Provider",
      can_attempt: true
    }.merge(overrides)
  end

  def only_condition(row) = contributor.conditions_for(row).first

  def enumerate(for_account)
    [].tap { |acc| contributor.each_component(for_account) { |record| acc << record } }
  end

  describe "the contract" do
    it "answers the registry key" do
      expect(described_class::KIND).to eq("provider_circuit_breaker")
      expect(contributor.kind).to eq("provider_circuit_breaker")
    end

    it "is NOT account scoped — the source carries no account" do
      expect(contributor.account_scoped?).to be(false)
    end

    it "presents a string icon name, a label and a group order" do
      expect(contributor.presentation).to eq(
        "icon" => "CircuitBoard", "label" => "Provider Circuit Breaker", "group_order" => 41
      )
    end

    it "names a breaker by its provider TYPE and a short id suffix, never the operator's name" do
      named = stats(provider_type: "anthropic")

      expect(contributor.ref_for(named)).to eq(provider_id)
      expect(contributor.display_name_for(named))
        .to eq("anthropic circuit ##{provider_id.delete('-').last(6)}")
      expect(contributor.display_name_for(named)).not_to include("Test Provider")
    end

    it "falls back to a generic noun when the provider type is unresolvable" do
      expect(contributor.display_name_for(stats(provider_type: nil))).to start_with("provider circuit #")
    end

    # A link to an account-scoped page would render for a cross-tenant reader
    # and then 403 — the contract's own rule about buttons, applied to links.
    it "links nowhere, and declares no dependency on an account-scoped component" do
      expect(contributor.links_for(stats)).to eq([])
      expect(contributor.dependencies_for(stats)).to eq([])
      expect(contributor.actions_for(stats)).to eq([])
    end
  end

  describe "state coverage" do
    it "maps every value of CircuitBreakerCore::STATES" do
      expect(contributor.mapped_values(described_class::STATE_CONDITIONS))
        .to eq(::CircuitBreakerCore::STATES.sort)
    end

    it "gives every state a reason that is not UnknownStatus" do
      ::CircuitBreakerCore::STATES.each do |state|
        condition = only_condition(stats(state: state))

        expect(condition).not_to be_nil, "no condition for #{state}"
        expect(condition["reason"]).not_to eq(unknown_reason), "#{state} fell through to UnknownStatus"
      end
    end

    it "reports an out-of-band state as unknown/UnknownStatus, never ok" do
      condition = only_condition(stats(state: "tripped"))

      expect(condition["status"]).to eq(Platform::Status::Condition::UNKNOWN)
      expect(condition["reason"]).to eq(unknown_reason)
      expect(condition["evidence"]["unmapped_value"]).to eq("tripped")
    end

    it "derives ok, degraded and progressing from the three states" do
      {
        "closed" => Platform::ComponentStatus::OK,
        "open" => Platform::ComponentStatus::DEGRADED,
        "half_open" => Platform::ComponentStatus::PROGRESSING
      }.each do |state, verdict|
        expect(Platform::Status::Condition.verdict_for_set(contributor.conditions_for(stats(state: state))))
          .to eq(verdict), "state=#{state}"
      end
    end

    it "carries the counters and the retry window as evidence" do
      opened_at = 3.minutes.ago
      condition = only_condition(stats(state: "open", consecutive_failures: 5, can_attempt: false,
                                       state_changed_at: opened_at, next_retry_at: 1.minute.from_now))

      evidence = condition["evidence"]

      expect(evidence["state"]).to eq("open")
      expect(evidence["consecutive_failures"]).to eq(5)
      expect(evidence["can_attempt"]).to be(false)
      # State and counters only — no tenant-identifying field.
      expect(evidence).not_to have_key("provider_id")
      expect(Time.zone.parse(evidence["state_changed_at"])).to be_within(1.second).of(opened_at)
      expect(evidence["next_retry_at"]).to be_present
    end
  end

  describe "#observed_at_for" do
    it "reports the breaker's own last state change, not the sweep's clock" do
      changed_at = 40.minutes.ago

      expect(contributor.observed_at_for(stats(state_changed_at: changed_at)))
        .to be_within(1.second).of(changed_at)
    end

    it "reports nothing when the source has no state-change time" do
      expect(contributor.observed_at_for(stats(state_changed_at: nil))).to be_nil
    end
  end

  describe "#each_component" do
    before do
      allow(::Ai::ProviderCircuitBreakerService).to receive(:all_provider_stats).and_return([ stats ])
    end

    it "yields whatever the source returns, for any account and for none" do
      expect(enumerate(account).map { |s| s[:provider_id] }).to eq([ provider_id ])
      expect(enumerate(create(:account)).map { |s| s[:provider_id] }).to eq([ provider_id ])
      expect(enumerate(nil).map { |s| s[:provider_id] }).to eq([ provider_id ])
    end

    it "resolves the provider TYPE in one query for the whole set, not one per row" do
      provider = create(:ai_provider, account: account, provider_type: "anthropic")
      allow(::Ai::ProviderCircuitBreakerService).to receive(:all_provider_stats)
        .and_return([ stats(provider_id: provider.id), stats(provider_id: provider.id) ])

      expect(::Ai::Provider).to receive(:where).once.and_call_original

      expect(enumerate(account).map { |s| s[:provider_type] }).to eq(%w[anthropic anthropic])
    end

    it "still yields when the type lookup fails, with no type rather than no row" do
      allow(::Ai::Provider).to receive(:where).and_raise(StandardError, "db gone")

      yielded = enumerate(account)

      expect(yielded.size).to eq(1)
      expect(yielded.first[:provider_type]).to be_nil
    end
  end

  describe "through the sweep" do
    around do |example|
      saved = Platform::Status::Registry.contributors
      Platform::Status::Registry.reset!
      example.run
    ensure
      Platform::Status::Registry.reset!
      saved.each { |kind, registered| Platform::Status::Registry.register(kind, registered) }
    end

    before do
      Platform::Status::Registry.register(described_class::KIND, contributor)
      allow(::Ai::ProviderCircuitBreakerService).to receive(:all_provider_stats).and_return([ stats(state: "open") ])
    end

    it "writes a NULL-account row rather than inventing a tenant" do
      Platform::Status::SweepService.run_once!(account)

      row = Platform::ComponentStatus.find_by(component_kind: described_class::KIND, component_ref: provider_id)

      expect(row).not_to be_nil
      expect(row.account_id).to be_nil
      expect(row.verdict).to eq(Platform::ComponentStatus::DEGRADED)
    end

    # THE SANITIZATION ORACLE. A shared row is broadcast on a shared stream and
    # read by any holder of `platform.status.read` in EVERY account, so it must
    # carry nothing that identifies a tenant.
    it "writes a row carrying no provider name and no link" do
      Platform::Status::SweepService.run_once!(account)

      row = Platform::ComponentStatus.find_by(component_kind: described_class::KIND,
                                              component_ref: provider_id)

      expect(row.attributes.to_json).not_to include("Test Provider")
      expect(row.display_name).not_to include("Test Provider")
      expect(row.links).to eq([])
      expect(row.dependencies).to eq([])
      expect(row.conditions.first["evidence"]).not_to have_key("provider_id")
    end

    # The other arm: the assertion above can actually see a leak. Without this
    # example a serialization that stopped containing the name for any reason
    # (an empty row, a renamed column) would pass it vacuously.
    it "and that assertion would catch a name if one were carried" do
      Platform::Status::SweepService.run_once!(account)

      row = Platform::ComponentStatus.find_by(component_kind: described_class::KIND,
                                              component_ref: provider_id)
      row.update!(display_name: "Test Provider circuit")

      expect(row.reload.attributes.to_json).to include("Test Provider")
    end

    it "does not duplicate the shared row when a second account is swept" do
      Platform::Status::SweepService.run_once!(account)
      Platform::Status::SweepService.run_once!(create(:account))

      expect(Platform::ComponentStatus.where(component_kind: described_class::KIND).count).to eq(1)
    end

    # Redis down: the source raises. The plane must report blindness, not health.
    it "becomes not_measured/ContributorError when the source cannot be read" do
      allow(::Ai::ProviderCircuitBreakerService).to receive(:all_provider_stats)
        .and_raise(StandardError, "redis unavailable")

      Platform::Status::SweepService.run_once!(account)

      row = Platform::ComponentStatus.find_by(component_kind: described_class::KIND,
                                              component_ref: Platform::ComponentStatus::WILDCARD_REF)

      expect(row.verdict).to eq(Platform::ComponentStatus::NOT_MEASURED)
      expect(row.conditions.first["reason"]).to eq(Platform::Status::SweepService::CONTRIBUTOR_ERROR_REASON)
    end
  end
end
