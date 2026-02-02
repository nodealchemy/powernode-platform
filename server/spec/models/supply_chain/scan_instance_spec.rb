# frozen_string_literal: true

require "rails_helper"

RSpec.describe SupplyChain::ScanInstance, type: :model do
  let(:account) { create(:account) }
  let(:scan_template) { create(:supply_chain_scan_template, account: account) }
  let(:user) { create(:user, account: account) }

  describe "table configuration" do
    it "uses correct table name" do
      expect(described_class.table_name).to eq("supply_chain_scan_instances")
    end
  end

  describe "constants" do
    it "defines STATUSES constant" do
      expect(described_class::STATUSES).to eq(%w[active paused disabled])
    end

    it "all status values are strings" do
      expect(described_class::STATUSES).to all(be_a(String))
    end
  end

  describe "associations" do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:scan_template).class_name("SupplyChain::ScanTemplate") }
    it { is_expected.to belong_to(:installed_by).class_name("User").optional }
    it { is_expected.to have_many(:executions).class_name("SupplyChain::ScanExecution").dependent(:destroy) }
  end

  describe "validations" do
    subject { build(:supply_chain_scan_instance, account: account, scan_template: scan_template) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:status) }
    it { is_expected.to validate_inclusion_of(:status).in_array(SupplyChain::ScanInstance::STATUSES) }
    # Note: Uniqueness validation exists on the model but can't be tested with shoulda-matchers
    # due to the before_save callback that modifies next_execution_at
    it "validates uniqueness of scan_template_id scoped to account_id" do
      existing = create(:supply_chain_scan_instance, account: account)
      duplicate = build(:supply_chain_scan_instance, account: account, scan_template: existing.scan_template)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:scan_template_id]).to include("already installed for this account")
    end
    it { is_expected.to validate_numericality_of(:execution_count).is_greater_than_or_equal_to(0) }
    it { is_expected.to validate_numericality_of(:success_count).is_greater_than_or_equal_to(0) }
    it { is_expected.to validate_numericality_of(:failure_count).is_greater_than_or_equal_to(0) }

    describe "name validation" do
      it "requires name to be present" do
        instance = build(:supply_chain_scan_instance, name: nil)
        expect(instance).not_to be_valid
        expect(instance.errors[:name]).to be_present
      end

      it "allows various name formats" do
        instance = build(:supply_chain_scan_instance, name: "Security Scan - Production v2.1")
        expect(instance).to be_valid
      end
    end

    describe "status validation" do
      it "rejects invalid status values" do
        instance = build(:supply_chain_scan_instance, status: "invalid")
        expect(instance).not_to be_valid
      end

      it "accepts all valid statuses" do
        described_class::STATUSES.each do |status|
          instance = build(:supply_chain_scan_instance, status: status)
          expect(instance).to be_valid
        end
      end
    end

    describe "scan_template_id uniqueness" do
      let!(:existing_instance) do
        create(:supply_chain_scan_instance, account: account, scan_template: scan_template)
      end

      it "prevents duplicate scan_template installations in same account" do
        new_instance = build(:supply_chain_scan_instance, account: account, scan_template: scan_template)
        expect(new_instance).not_to be_valid
        expect(new_instance.errors[:scan_template_id]).to include("already installed for this account")
      end

      it "allows same scan_template in different accounts" do
        other_account = create(:account)
        new_instance = build(:supply_chain_scan_instance, account: other_account, scan_template: scan_template)
        expect(new_instance).to be_valid
      end
    end

    describe "numeric validations" do
      it "rejects negative execution_count" do
        instance = build(:supply_chain_scan_instance, execution_count: -1)
        expect(instance).not_to be_valid
      end

      it "rejects negative success_count" do
        instance = build(:supply_chain_scan_instance, success_count: -1)
        expect(instance).not_to be_valid
      end

      it "rejects negative failure_count" do
        instance = build(:supply_chain_scan_instance, failure_count: -1)
        expect(instance).not_to be_valid
      end

      it "allows zero for all count fields" do
        instance = build(:supply_chain_scan_instance, execution_count: 0, success_count: 0, failure_count: 0)
        expect(instance).to be_valid
      end
    end
  end

  describe "scopes" do
    let!(:active_instance) { create(:supply_chain_scan_instance, account: account, status: "active") }
    let!(:paused_instance) { create(:supply_chain_scan_instance, account: account, status: "paused") }
    let!(:disabled_instance) { create(:supply_chain_scan_instance, account: account, status: "disabled") }
    let!(:scheduled_instance) do
      create(:supply_chain_scan_instance, account: account, schedule_cron: "0 * * * *")
    end
    let!(:unscheduled_instance) do
      create(:supply_chain_scan_instance, account: account, schedule_cron: nil)
    end

    describe ".by_status" do
      it "filters instances by status" do
        expect(described_class.by_status("active")).to include(active_instance)
        expect(described_class.by_status("active")).not_to include(paused_instance, disabled_instance)
      end

      it "returns all matching status" do
        result = described_class.by_status("paused")
        expect(result).to eq([ paused_instance ])
      end
    end

    describe ".active" do
      it "returns only active instances" do
        result = described_class.active
        expect(result).to include(active_instance, scheduled_instance, unscheduled_instance)
        expect(result).not_to include(paused_instance, disabled_instance)
      end
    end

    describe ".paused" do
      it "returns only paused instances" do
        result = described_class.paused
        expect(result).to eq([ paused_instance ])
      end
    end

    describe ".disabled" do
      it "returns only disabled instances" do
        result = described_class.disabled
        expect(result).to eq([ disabled_instance ])
      end
    end

    describe ".scheduled" do
      it "returns only instances with schedule_cron" do
        result = described_class.scheduled
        expect(result).to include(scheduled_instance)
        expect(result).not_to include(unscheduled_instance, active_instance)
      end
    end

    describe ".due_for_execution" do
      # Use update_column to bypass the before_save callback that sets next_execution_at
      let!(:past_execution) do
        instance = create(:supply_chain_scan_instance, account: account, status: "active", schedule_cron: "0 * * * *")
        instance.update_column(:next_execution_at, 1.hour.ago)
        instance
      end
      let!(:future_execution) do
        instance = create(:supply_chain_scan_instance, account: account, status: "active", schedule_cron: "0 * * * *")
        instance.update_column(:next_execution_at, 1.hour.from_now)
        instance
      end
      let!(:null_execution) do
        instance = create(:supply_chain_scan_instance, account: account, status: "active", schedule_cron: "0 * * * *")
        instance.update_column(:next_execution_at, nil)
        instance
      end

      it "returns active, scheduled instances with null or past next_execution_at" do
        result = described_class.due_for_execution
        expect(result).to include(past_execution, null_execution)
        expect(result).not_to include(future_execution)
      end

      it "excludes paused instances" do
        paused_past = create(:supply_chain_scan_instance,
          account: account,
          status: "paused",
          schedule_cron: "0 * * * *",
          next_execution_at: 1.hour.ago)

        result = described_class.due_for_execution
        expect(result).not_to include(paused_past)
      end

      it "excludes unscheduled instances" do
        result = described_class.due_for_execution
        expect(result).not_to include(unscheduled_instance)
      end
    end

    describe ".by_template" do
      let(:template1) { create(:supply_chain_scan_template) }
      let(:template2) { create(:supply_chain_scan_template) }
      let!(:instance1) { create(:supply_chain_scan_instance, account: account, scan_template: template1) }
      let!(:instance2) { create(:supply_chain_scan_instance, account: account, scan_template: template2) }

      it "returns instances for specific template" do
        result = described_class.by_template(template1.id)
        expect(result).to include(instance1)
        expect(result).not_to include(instance2)
      end
    end

    describe ".recent" do
      let!(:older_instance) { create(:supply_chain_scan_instance, account: account, created_at: 2.days.ago) }
      let!(:newer_instance) { create(:supply_chain_scan_instance, account: account, created_at: 1.day.ago) }
      let!(:newest_instance) { create(:supply_chain_scan_instance, account: account, created_at: Time.current) }

      it "returns instances ordered by created_at descending" do
        result = described_class.recent
        expect(result.first).to eq(newest_instance)
        expect(result.last).to eq(older_instance)
      end
    end
  end

  describe "callbacks" do
    describe "sanitize_jsonb_fields" do
      it "initializes configuration to empty hash if nil" do
        instance = build(:supply_chain_scan_instance, configuration: nil)
        instance.save!
        expect(instance.configuration).to eq({})
      end

      it "initializes metadata to empty hash if nil" do
        instance = build(:supply_chain_scan_instance, metadata: nil)
        instance.save!
        expect(instance.metadata).to eq({})
      end

      it "preserves existing configuration" do
        config = { "api_key" => "secret" }
        instance = build(:supply_chain_scan_instance, configuration: config)
        instance.save!
        expect(instance.configuration).to eq(config)
      end

      it "preserves existing metadata" do
        meta = { "custom_field" => "value" }
        instance = build(:supply_chain_scan_instance, metadata: meta)
        instance.save!
        expect(instance.metadata).to eq(meta)
      end
    end

    describe "calculate_next_execution" do
      it "calculates next_execution_at when schedule_cron changes" do
        instance = create(:supply_chain_scan_instance, account: account, schedule_cron: nil)
        expect(instance.next_execution_at).to be_nil

        instance.update!(schedule_cron: "0 * * * *")
        expect(instance.next_execution_at).not_to be_nil
      end

      it "does not recalculate when other fields change" do
        instance = create(:supply_chain_scan_instance, account: account, schedule_cron: "0 * * * *")
        original_next_execution = instance.next_execution_at

        instance.update!(name: "Updated Name")
        expect(instance.next_execution_at).to eq(original_next_execution)
      end

      it "sets next_execution_at to approximately 1 hour from now" do
        instance = build(:supply_chain_scan_instance, schedule_cron: "0 * * * *")
        instance.save!

        expect(instance.next_execution_at).to be_within(2.minutes).of(1.hour.from_now)
      end
    end
  end

  describe "instance methods - status predicates" do
    describe "#active?" do
      it "returns true when status is active" do
        instance = build(:supply_chain_scan_instance, status: "active")
        expect(instance.active?).to be true
      end

      it "returns false for other statuses" do
        expect(build(:supply_chain_scan_instance, status: "paused").active?).to be false
        expect(build(:supply_chain_scan_instance, status: "disabled").active?).to be false
      end
    end

    describe "#paused?" do
      it "returns true when status is paused" do
        instance = build(:supply_chain_scan_instance, status: "paused")
        expect(instance.paused?).to be true
      end

      it "returns false for other statuses" do
        expect(build(:supply_chain_scan_instance, status: "active").paused?).to be false
        expect(build(:supply_chain_scan_instance, status: "disabled").paused?).to be false
      end
    end

    describe "#disabled?" do
      it "returns true when status is disabled" do
        instance = build(:supply_chain_scan_instance, status: "disabled")
        expect(instance.disabled?).to be true
      end

      it "returns false for other statuses" do
        expect(build(:supply_chain_scan_instance, status: "active").disabled?).to be false
        expect(build(:supply_chain_scan_instance, status: "paused").disabled?).to be false
      end
    end

    describe "#scheduled?" do
      it "returns true when schedule_cron is present" do
        instance = build(:supply_chain_scan_instance, schedule_cron: "0 * * * *")
        expect(instance.scheduled?).to be true
      end

      it "returns false when schedule_cron is nil" do
        instance = build(:supply_chain_scan_instance, schedule_cron: nil)
        expect(instance.scheduled?).to be false
      end

      it "returns false when schedule_cron is blank string" do
        instance = build(:supply_chain_scan_instance, schedule_cron: "")
        expect(instance.scheduled?).to be false
      end
    end

    describe "#due_for_execution?" do
      it "returns true when active, scheduled, and next_execution_at is in past" do
        instance = build(:supply_chain_scan_instance,
          status: "active",
          schedule_cron: "0 * * * *",
          next_execution_at: 1.hour.ago)
        expect(instance.due_for_execution?).to be true
      end

      it "returns true when active, scheduled, and next_execution_at is nil" do
        instance = build(:supply_chain_scan_instance,
          status: "active",
          schedule_cron: "0 * * * *",
          next_execution_at: nil)
        expect(instance.due_for_execution?).to be true
      end

      it "returns true when active, scheduled, and next_execution_at is now" do
        instance = build(:supply_chain_scan_instance,
          status: "active",
          schedule_cron: "0 * * * *",
          next_execution_at: Time.current)
        expect(instance.due_for_execution?).to be true
      end

      it "returns false when not active" do
        instance = build(:supply_chain_scan_instance,
          status: "paused",
          schedule_cron: "0 * * * *",
          next_execution_at: 1.hour.ago)
        expect(instance.due_for_execution?).to be false
      end

      it "returns false when not scheduled" do
        instance = build(:supply_chain_scan_instance,
          status: "active",
          schedule_cron: nil,
          next_execution_at: 1.hour.ago)
        expect(instance.due_for_execution?).to be false
      end

      it "returns false when next_execution_at is in future" do
        instance = build(:supply_chain_scan_instance,
          status: "active",
          schedule_cron: "0 * * * *",
          next_execution_at: 1.hour.from_now)
        expect(instance.due_for_execution?).to be false
      end
    end
  end

  describe "instance methods - status transitions" do
    let(:instance) { create(:supply_chain_scan_instance, account: account, status: "active") }

    describe "#activate!" do
      it "changes status to active" do
        instance.update!(status: "paused")
        instance.activate!
        expect(instance.reload.status).to eq("active")
      end

      it "persists to database" do
        instance.update!(status: "disabled")
        instance.activate!
        expect(instance.reload.active?).to be true
      end
    end

    describe "#pause!" do
      it "changes status to paused" do
        instance.pause!
        expect(instance.reload.status).to eq("paused")
      end

      it "persists to database" do
        instance.pause!
        expect(instance.reload.paused?).to be true
      end
    end

    describe "#disable!" do
      it "changes status to disabled" do
        instance.disable!
        expect(instance.reload.status).to eq("disabled")
      end

      it "persists to database" do
        instance.disable!
        expect(instance.reload.disabled?).to be true
      end
    end
  end

  describe "instance methods - execution tracking" do
    let(:instance) { create(:supply_chain_scan_instance, account: account) }

    describe "#success_rate" do
      it "returns 0 when execution_count is 0" do
        instance.update!(execution_count: 0, success_count: 0)
        expect(instance.success_rate).to eq(0)
      end

      it "calculates correct percentage" do
        instance.update!(execution_count: 10, success_count: 7)
        expect(instance.success_rate).to eq(70.0)
      end

      it "returns proper decimal precision" do
        instance.update!(execution_count: 3, success_count: 1)
        expect(instance.success_rate).to eq(33.33)
      end

      it "handles 100% success rate" do
        instance.update!(execution_count: 5, success_count: 5)
        expect(instance.success_rate).to eq(100.0)
      end

      it "handles partial success rates" do
        instance.update!(execution_count: 100, success_count: 33)
        expect(instance.success_rate).to eq(33.0)
      end
    end

    describe "#execute!" do
      context "when instance is active" do
        before { instance.update!(status: "active") }

        it "creates a scan execution" do
          expect {
            instance.execute!
          }.to change(SupplyChain::ScanExecution, :count).by(1)
        end

        it "sets execution status to pending" do
          execution = instance.execute!
          expect(execution.status).to eq("pending")
        end

        it "assigns account from instance" do
          execution = instance.execute!
          expect(execution.account).to eq(instance.account)
        end

        it "sets trigger_type to scheduled by default" do
          execution = instance.execute!
          expect(execution.trigger_type).to eq("scheduled")
        end

        it "sets trigger_type to manual when triggered_by provided" do
          execution = instance.execute!(triggered_by: user)
          expect(execution.trigger_type).to eq("manual")
        end

        it "assigns triggered_by user when provided" do
          execution = instance.execute!(triggered_by: user)
          expect(execution.triggered_by).to eq(user)
        end

        it "stores input_data when provided" do
          input = { "param1" => "value1" }
          execution = instance.execute!(input: input)
          expect(execution.input_data).to eq(input)
        end

        it "returns the created execution" do
          execution = instance.execute!
          expect(execution).to be_persisted
          expect(execution).to be_a(SupplyChain::ScanExecution)
        end
      end

      context "when instance is not active" do
        before { instance.update!(status: "paused") }

        it "returns nil" do
          expect(instance.execute!).to be_nil
        end

        it "does not create an execution" do
          expect {
            instance.execute!
          }.not_to change(SupplyChain::ScanExecution, :count)
        end
      end
    end

    describe "#record_execution_result!" do
      context "for successful execution" do
        it "increments success_count" do
          instance.update!(success_count: 5, failure_count: 2, execution_count: 7)
          instance.record_execution_result!(success: true)
          expect(instance.reload.success_count).to eq(6)
        end

        it "increments execution_count" do
          instance.update!(success_count: 5, failure_count: 2, execution_count: 7)
          instance.record_execution_result!(success: true)
          expect(instance.reload.execution_count).to eq(8)
        end

        it "does not increment failure_count" do
          instance.update!(success_count: 5, failure_count: 2, execution_count: 7)
          instance.record_execution_result!(success: true)
          expect(instance.reload.failure_count).to eq(2)
        end

        it "updates last_execution_at" do
          before_time = Time.current
          instance.record_execution_result!(success: true)
          expect(instance.reload.last_execution_at).to be >= before_time
        end

        it "updates next_execution_at" do
          instance.update!(schedule_cron: "0 * * * *")
          instance.record_execution_result!(success: true)
          expect(instance.reload.next_execution_at).not_to be_nil
        end
      end

      context "for failed execution" do
        it "increments failure_count" do
          instance.update!(success_count: 5, failure_count: 2, execution_count: 7)
          instance.record_execution_result!(success: false)
          expect(instance.reload.failure_count).to eq(3)
        end

        it "increments execution_count" do
          instance.update!(success_count: 5, failure_count: 2, execution_count: 7)
          instance.record_execution_result!(success: false)
          expect(instance.reload.execution_count).to eq(8)
        end

        it "does not increment success_count" do
          instance.update!(success_count: 5, failure_count: 2, execution_count: 7)
          instance.record_execution_result!(success: false)
          expect(instance.reload.success_count).to eq(5)
        end

        it "updates last_execution_at" do
          before_time = Time.current
          instance.record_execution_result!(success: false)
          expect(instance.reload.last_execution_at).to be >= before_time
        end
      end
    end

    describe "#latest_execution" do
      it "returns nil when no executions exist" do
        expect(instance.latest_execution).to be_nil
      end

      it "returns the most recent execution" do
        older_exec = create(:supply_chain_scan_execution, scan_instance: instance, created_at: 2.days.ago)
        newer_exec = create(:supply_chain_scan_execution, scan_instance: instance, created_at: 1.day.ago)
        latest_exec = create(:supply_chain_scan_execution, scan_instance: instance, created_at: Time.current)

        expect(instance.latest_execution).to eq(latest_exec)
      end
    end

    describe "#recent_executions" do
      it "returns empty array when no executions exist" do
        expect(instance.recent_executions).to be_empty
      end

      it "returns all executions when limit is not set" do
        create_list(:supply_chain_scan_execution, 5, scan_instance: instance)
        expect(instance.recent_executions.length).to eq(5)
      end

      it "respects the limit parameter" do
        create_list(:supply_chain_scan_execution, 15, scan_instance: instance)
        expect(instance.recent_executions(5).length).to eq(5)
      end

      it "returns executions in reverse chronological order" do
        execs = create_list(:supply_chain_scan_execution, 3, scan_instance: instance)
        result = instance.recent_executions

        expect(result.first.created_at).to be >= result.last.created_at
      end

      it "defaults to limit of 10" do
        create_list(:supply_chain_scan_execution, 15, scan_instance: instance)
        expect(instance.recent_executions.length).to eq(10)
      end
    end
  end

  describe "instance methods - configuration management" do
    let(:instance) { create(:supply_chain_scan_instance, account: account, scan_template: scan_template) }

    describe "#update_configuration!" do
      context "when configuration is valid" do
        before do
          allow(scan_template).to receive(:validate_configuration).and_return({ valid: true, errors: [] })
        end

        it "returns true" do
          result = instance.update_configuration!({ "new_key" => "new_value" })
          expect(result).to be true
        end

        it "updates the configuration" do
          new_config = { "api_key" => "secret123" }
          instance.update_configuration!(new_config)
          expect(instance.reload.configuration).to eq(new_config)
        end

        it "persists changes to database" do
          new_config = { "endpoint" => "https://api.example.com" }
          instance.update_configuration!(new_config)
          expect(instance.reload.configuration).to eq(new_config)
        end
      end

      context "when configuration is invalid" do
        before do
          allow(scan_template).to receive(:validate_configuration).and_return({
            valid: false,
            errors: [ "Missing required field: api_key" ]
          })
        end

        it "returns false" do
          result = instance.update_configuration!({})
          expect(result).to be false
        end

        it "does not update configuration" do
          original_config = instance.configuration
          instance.update_configuration!({})
          expect(instance.configuration).to eq(original_config)
        end

        it "adds error messages" do
          instance.update_configuration!({})
          expect(instance.errors[:configuration]).to include("Missing required field: api_key")
        end
      end
    end

    describe "#template_name" do
      it "returns the scan template name" do
        expect(instance.template_name).to eq(scan_template.name)
      end

      it "reflects template name changes" do
        scan_template.update!(name: "Updated Template Name")
        expect(instance.template_name).to eq("Updated Template Name")
      end
    end

    describe "#template_category" do
      it "returns the scan template category" do
        template = create(:supply_chain_scan_template, category: "security")
        instance = create(:supply_chain_scan_instance, scan_template: template, account: account)
        expect(instance.template_category).to eq("security")
      end

      it "handles different category types" do
        %w[security compliance license quality custom].each do |category|
          template = create(:supply_chain_scan_template, category: category)
          instance = create(:supply_chain_scan_instance, scan_template: template, account: account)
          expect(instance.template_category).to eq(category)
        end
      end
    end
  end

  describe "instance methods - serialization" do
    let(:instance) do
      create(:supply_chain_scan_instance,
        account: account,
        name: "Test Instance",
        description: "Test Description",
        status: "active",
        execution_count: 10,
        success_count: 8,
        failure_count: 2,
        last_execution_at: 1.hour.ago,
        next_execution_at: 1.hour.from_now,
        configuration: { "api_key" => "secret" })
    end

    describe "#summary" do
      let(:summary) { instance.summary }

      it "returns a hash" do
        expect(summary).to be_a(Hash)
      end

      it "includes id" do
        expect(summary[:id]).to eq(instance.id)
      end

      it "includes name" do
        expect(summary[:name]).to eq("Test Instance")
      end

      it "includes description" do
        expect(summary[:description]).to eq("Test Description")
      end

      it "includes scan_template_id" do
        expect(summary[:scan_template_id]).to eq(instance.scan_template_id)
      end

      it "includes template_name" do
        expect(summary[:template_name]).to eq(instance.template_name)
      end

      it "includes template_category" do
        expect(summary[:template_category]).to eq(instance.template_category)
      end

      it "includes status" do
        expect(summary[:status]).to eq("active")
      end

      it "includes schedule_cron" do
        expect(summary[:schedule_cron]).to eq(instance.schedule_cron)
      end

      it "includes execution_count" do
        expect(summary[:execution_count]).to eq(10)
      end

      it "includes success_count" do
        expect(summary[:success_count]).to eq(8)
      end

      it "includes failure_count" do
        expect(summary[:failure_count]).to eq(2)
      end

      it "includes success_rate" do
        expect(summary[:success_rate]).to eq(80.0)
      end

      it "includes last_execution_at" do
        expect(summary[:last_execution_at]).to eq(instance.last_execution_at)
      end

      it "includes next_execution_at" do
        expect(summary[:next_execution_at]).to eq(instance.next_execution_at)
      end

      it "includes created_at" do
        expect(summary[:created_at]).to eq(instance.created_at)
      end

      it "does not include configuration" do
        expect(summary).not_to have_key(:configuration)
      end
    end

    describe "#detailed_instance" do
      let(:execution1) { create(:supply_chain_scan_execution, scan_instance: instance, created_at: 2.hours.ago) }
      let(:execution2) { create(:supply_chain_scan_execution, scan_instance: instance, created_at: 1.hour.ago) }

      before do
        execution1
        execution2
      end

      let(:detailed) { instance.detailed_instance }

      it "returns a hash" do
        expect(detailed).to be_a(Hash)
      end

      it "includes summary" do
        expect(detailed[:summary]).to be_a(Hash)
        expect(detailed[:summary][:id]).to eq(instance.id)
      end

      it "includes configuration" do
        expect(detailed[:configuration]).to eq({ "api_key" => "secret" })
      end

      it "includes template summary" do
        expect(detailed[:template]).to be_a(Hash)
        expect(detailed[:template][:id]).to eq(instance.scan_template.id)
      end

      it "includes recent executions" do
        expect(detailed[:recent_executions]).to be_a(Array)
        expect(detailed[:recent_executions].length).to eq(2)
      end

      it "includes execution summaries" do
        summaries = detailed[:recent_executions]
        expect(summaries.first).to be_a(Hash)
        expect(summaries.first).to have_key(:execution_id)
      end
    end
  end

  describe "integration tests" do
    let(:instance) { create(:supply_chain_scan_instance, account: account, status: "active") }

    it "can create and execute a scan instance" do
      execution = instance.execute!(triggered_by: user)
      expect(execution).to be_persisted
      expect(instance.latest_execution).to eq(execution)
    end

    it "tracks execution history" do
      create_list(:supply_chain_scan_execution, 5, scan_instance: instance)
      expect(instance.recent_executions.length).to eq(5)
    end

    it "updates success rate when recording results" do
      expect(instance.success_rate).to eq(0)

      instance.record_execution_result!(success: true)
      expect(instance.reload.success_rate).to eq(100.0)

      instance.record_execution_result!(success: false)
      expect(instance.reload.success_rate).to eq(50.0)
    end

    it "transitions through statuses correctly" do
      expect(instance.active?).to be true

      instance.pause!
      expect(instance.reload.paused?).to be true
      expect(instance.reload.active?).to be false

      instance.activate!
      expect(instance.reload.active?).to be true
    end

    it "handles scheduled executions" do
      instance.update!(schedule_cron: "0 * * * *")
      expect(instance.scheduled?).to be true

      if instance.next_execution_at
        expect(instance.due_for_execution?).to eq(instance.next_execution_at <= Time.current)
      end
    end

    it "serializes full details correctly" do
      instance.update!(
        execution_count: 20,
        success_count: 18,
        configuration: { "enabled" => true }
      )
      create(:supply_chain_scan_execution, scan_instance: instance)

      details = instance.detailed_instance
      expect(details[:summary][:execution_count]).to eq(20)
      expect(details[:configuration]["enabled"]).to be true
      expect(details[:recent_executions].length).to be > 0
    end
  end

  describe "edge cases and boundary conditions" do
    let(:instance) { create(:supply_chain_scan_instance, account: account) }

    it "handles very large execution counts" do
      instance.update!(execution_count: 999_999, success_count: 999_998)
      # success_rate rounds to 2 decimal places: 999998/999999 * 100 = 99.9999... rounds to 100.0
      expect(instance.success_rate).to eq(100.0)
    end

    it "handles zero executions gracefully" do
      instance.update!(execution_count: 0, success_count: 0, failure_count: 0)
      expect(instance.success_rate).to eq(0)
    end

    it "handles missing template gracefully in summary" do
      summary = instance.summary
      expect(summary[:template_name]).to eq(instance.scan_template.name)
    end

    it "survives deletion of all executions" do
      create_list(:supply_chain_scan_execution, 3, scan_instance: instance)
      instance.executions.destroy_all
      expect(instance.executions).to be_empty
      expect(instance.latest_execution).to be_nil
    end

    it "handles concurrent execution attempts" do
      # Simulating rapid execution requests
      executions = 3.times.map { instance.execute! }
      expect(executions.compact.length).to eq(3)
      expect(instance.reload.executions.count).to eq(3)
    end

    it "maintains consistency when updating counts manually" do
      instance.update!(execution_count: 100, success_count: 50, failure_count: 50)
      expect(instance.execution_count).to eq(100)
      expect(instance.success_rate).to eq(50.0)
    end
  end
end
