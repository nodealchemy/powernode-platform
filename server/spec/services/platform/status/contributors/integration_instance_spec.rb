# frozen_string_literal: true

require "rails_helper"

# Component status plane, increment A3 — the `integration_instance` core
# contributor (read-only).
RSpec.describe Platform::Status::Contributors::IntegrationInstance do
  subject(:contributor) { described_class.new }

  let(:account) { create(:account) }
  let(:unknown_reason) { Platform::Status::Contributors::EnumConditions::UNKNOWN_REASON }

  def condition_of(conditions, type) = conditions.find { |c| c["type"] == type }

  def enumerate(for_account)
    [].tap { |acc| contributor.each_component(for_account) { |record| acc << record } }
  end

  # `status` maps onto three different condition types (Enabled / Held /
  # Progressing), so "the condition this value produced" is whichever one came
  # back — there is exactly one status-derived condition per record.
  def status_condition(instance)
    conditions = contributor.conditions_for(instance)
    conditions.reject { |c| c["type"] == "Healthy" }.first
  end

  describe "the contract" do
    it "answers the registry key and is account scoped" do
      expect(described_class::KIND).to eq("integration_instance")
      expect(contributor.kind).to eq("integration_instance")
      expect(contributor.account_scoped?).to be(true)
    end

    it "presents a string icon name, a label and a group order" do
      expect(contributor.presentation).to eq(
        "icon" => "Cable", "label" => "Integration", "group_order" => 20
      )
    end

    it "links to the integration detail page" do
      instance = create(:devops_integration_instance, account: account)

      expect(contributor.links_for(instance))
        .to eq([ { "label" => "Integration", "path" => "/app/devops/connections/integrations/#{instance.id}" } ])
    end

    it "declares no dependencies — a template and a credential are not components" do
      instance = create(:devops_integration_instance, account: account)

      expect(contributor.dependencies_for(instance)).to eq([])
      expect(contributor.actions_for(instance)).to eq([])
    end
  end

  describe "status coverage" do
    it "maps every value of Devops::IntegrationInstance::STATUSES" do
      expect(contributor.mapped_values(described_class::STATUS_CONDITIONS))
        .to eq(::Devops::IntegrationInstance::STATUSES.sort)
    end

    it "gives every status a reason that is not UnknownStatus" do
      instance = build(:devops_integration_instance, account: account)

      ::Devops::IntegrationInstance::STATUSES.each do |status|
        instance.status = status
        condition = status_condition(instance)

        expect(condition).not_to be_nil, "no status condition for #{status}"
        expect(condition["reason"]).not_to eq(unknown_reason), "#{status} fell through to UnknownStatus"
      end
    end

    it "reports an out-of-band status as unknown/UnknownStatus, never ok" do
      instance = build(:devops_integration_instance, account: account)
      instance.status = "quiesced"

      condition = status_condition(instance)

      expect(condition["type"]).to eq("Enabled")
      expect(condition["status"]).to eq(Platform::Status::Condition::UNKNOWN)
      expect(condition["reason"]).to eq(unknown_reason)
      expect(condition["evidence"]["unmapped_value"]).to eq("quiesced")
    end

    it "derives held from paused, progressing from pending and degraded from error" do
      instance = build(:devops_integration_instance, account: account,
                                                     last_health_check_at: Time.current, health_status: "healthy")

      {
        "paused" => Platform::ComponentStatus::HELD,
        "pending" => Platform::ComponentStatus::PROGRESSING,
        "error" => Platform::ComponentStatus::DEGRADED,
        "active" => Platform::ComponentStatus::OK
      }.each do |status, verdict|
        instance.status = status

        expect(Platform::Status::Condition.verdict_for_set(contributor.conditions_for(instance)))
          .to eq(verdict), "status=#{status}"
      end
    end
  end

  describe "health coverage" do
    let(:instance) do
      build(:devops_integration_instance, account: account, status: "active",
                                          last_health_check_at: 2.minutes.ago)
    end

    it "maps every value of Devops::IntegrationInstance::HEALTH_STATUSES" do
      expect(contributor.mapped_values(described_class::HEALTH_CONDITIONS))
        .to eq(::Devops::IntegrationInstance::HEALTH_STATUSES.sort)
    end

    it "gives every health status a reason that is not UnknownStatus" do
      ::Devops::IntegrationInstance::HEALTH_STATUSES.each do |health|
        instance.health_status = health
        condition = condition_of(contributor.conditions_for(instance), "Healthy")

        expect(condition).not_to be_nil, "no Healthy condition for #{health}"
        expect(condition["reason"]).not_to eq(unknown_reason), "#{health} fell through to UnknownStatus"
      end
    end

    it "reports an out-of-band health status as unknown/UnknownStatus" do
      instance.health_status = "vibrant"

      condition = condition_of(contributor.conditions_for(instance), "Healthy")

      expect(condition["status"]).to eq(Platform::Status::Condition::UNKNOWN)
      expect(condition["reason"]).to eq(unknown_reason)
    end

    it "calls unhealthy down and degraded degraded" do
      instance.health_status = "unhealthy"
      expect(Platform::Status::Condition.verdict_for_set(contributor.conditions_for(instance)))
        .to eq(Platform::ComponentStatus::DOWN)

      instance.health_status = "degraded"
      expect(Platform::Status::Condition.verdict_for_set(contributor.conditions_for(instance)))
        .to eq(Platform::ComponentStatus::DEGRADED)
    end

    # The audit's finding: nothing writes these columns today. The contributor
    # must report the gap rather than the column's default.
    it "reports NeverChecked when last_health_check_at is nil, whatever the column says" do
      never_checked = build(:devops_integration_instance, account: account, status: "active",
                                                          health_status: "healthy", last_health_check_at: nil)

      condition = condition_of(contributor.conditions_for(never_checked), "Healthy")

      expect(condition["status"]).to eq(Platform::Status::Condition::UNKNOWN)
      expect(condition["reason"]).to eq("NeverChecked")
      expect(Platform::Status::Condition.verdict_for_set(contributor.conditions_for(never_checked)))
        .to eq(Platform::ComponentStatus::NOT_MEASURED)
    end

    it "stops reporting NeverChecked the moment a check has run" do
      checked = build(:devops_integration_instance, account: account, status: "active",
                                                    health_status: "healthy", last_health_check_at: 1.minute.ago)

      condition = condition_of(contributor.conditions_for(checked), "Healthy")

      expect(condition["reason"]).to eq("HealthCheckPassed")
      expect(Platform::Status::Condition.verdict_for_set(contributor.conditions_for(checked)))
        .to eq(Platform::ComponentStatus::OK)
    end
  end

  describe "#each_component" do
    it "yields only this account's instances" do
      mine = create(:devops_integration_instance, account: account)
      theirs = create(:devops_integration_instance, account: create(:account))

      ids = enumerate(account).map(&:id)

      expect(ids).to eq([ mine.id ])
      expect(ids).not_to include(theirs.id)
    end

    it "excludes disabled instances and keeps paused ones" do
      paused = create(:devops_integration_instance, :paused, account: account)
      disabled = create(:devops_integration_instance, :disabled, account: account)

      ids = enumerate(account).map(&:id)

      expect(ids).to include(paused.id)
      expect(ids).not_to include(disabled.id)
    end

    it "yields nothing without an account" do
      create(:devops_integration_instance, account: account)

      expect(enumerate(nil)).to eq([])
    end
  end

  describe "#observed_at_for" do
    it "reports the health check's time when one has run and nothing when none has" do
      checked_at = 9.minutes.ago.change(usec: 0)

      expect(contributor.observed_at_for(build(:devops_integration_instance, last_health_check_at: checked_at)))
        .to be_within(1.second).of(checked_at)
      expect(contributor.observed_at_for(build(:devops_integration_instance, last_health_check_at: nil)))
        .to be_nil
    end
  end
end
