# frozen_string_literal: true

require "rails_helper"

RSpec.describe SupplyChain::CveMonitor, type: :model do
  include ActiveSupport::Testing::TimeHelpers

  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:devops_provider) do
    Devops::Provider.create!(
      account: account,
      name: "Test Provider",
      provider_type: "github",
      base_url: "https://api.github.com",
      api_version: "v3",
      is_default: true
    )
  end
  let(:repository) { Devops::Repository.create!(account: account, provider: devops_provider, name: "test-repo", full_name: "org/test-repo", default_branch: "main") }
  let(:container_image) { create(:supply_chain_container_image, account: account) }

  # Helper to create CVE monitor without triggering Schedulable validations
  def create_cve_monitor(**attrs)
    defaults = {
      account: account,
      name: "Test Monitor #{SecureRandom.hex(4)}",
      scope_type: "account_wide",
      min_severity: "medium",
      is_active: true
    }
    SupplyChain::CveMonitor.create!(defaults.merge(attrs))
  end

  def build_cve_monitor(**attrs)
    defaults = {
      account: account,
      name: "Test Monitor #{SecureRandom.hex(4)}",
      scope_type: "account_wide",
      min_severity: "medium",
      is_active: true
    }
    SupplyChain::CveMonitor.new(defaults.merge(attrs))
  end

  describe "constants" do
    it { expect(described_class::SCOPE_TYPES).to eq(%w[image repository account_wide]) }
    it { expect(described_class::MIN_SEVERITIES).to eq(%w[critical high medium low]) }
  end

  describe "associations" do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:created_by).class_name("User").optional }
  end

  describe "validations" do
    describe "presence validations" do
      it "requires name" do
        monitor = build_cve_monitor(name: nil)
        expect(monitor).not_to be_valid
        expect(monitor.errors[:name]).to include("can't be blank")
      end

      it "requires scope_type" do
        monitor = build_cve_monitor(scope_type: nil)
        expect(monitor).not_to be_valid
        expect(monitor.errors[:scope_type]).to include("can't be blank")
      end

      it "requires min_severity" do
        monitor = build_cve_monitor(min_severity: nil)
        expect(monitor).not_to be_valid
        expect(monitor.errors[:min_severity]).to include("can't be blank")
      end
    end

    describe "inclusion validations" do
      it "validates scope_type is in SCOPE_TYPES" do
        monitor = build_cve_monitor(scope_type: "invalid")
        expect(monitor).not_to be_valid
        expect(monitor.errors[:scope_type]).to include("is not included in the list")
      end

      it "validates min_severity is in MIN_SEVERITIES" do
        monitor = build_cve_monitor(min_severity: "extreme")
        expect(monitor).not_to be_valid
        expect(monitor.errors[:min_severity]).to include("is not included in the list")
      end
    end

    describe "name uniqueness scoped to account" do
      let!(:existing_monitor) { create_cve_monitor(name: "Existing Monitor") }

      it "validates uniqueness of name within account" do
        duplicate = build_cve_monitor(name: "Existing Monitor")
        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:name]).to include("has already been taken")
      end

      it "allows same name in different accounts" do
        other_account = create(:account)
        monitor = build_cve_monitor(account: other_account, name: "Existing Monitor")
        expect(monitor).to be_valid
      end
    end

    describe "scope_id_required_for_non_account_wide validation" do
      it "requires scope_id for image scope" do
        monitor = build_cve_monitor(scope_type: "image", scope_id: nil)
        expect(monitor).not_to be_valid
        expect(monitor.errors[:scope_id]).to include("is required for image scope")
      end

      it "requires scope_id for repository scope" do
        monitor = build_cve_monitor(scope_type: "repository", scope_id: nil)
        expect(monitor).not_to be_valid
        expect(monitor.errors[:scope_id]).to include("is required for repository scope")
      end

      it "does not require scope_id for account_wide scope" do
        monitor = build_cve_monitor(scope_type: "account_wide", scope_id: nil)
        expect(monitor).to be_valid
      end

      it "allows scope_id for account_wide scope" do
        monitor = build_cve_monitor(scope_type: "account_wide", scope_id: SecureRandom.uuid)
        expect(monitor).to be_valid
      end
    end
  end

  describe "scopes" do
    let!(:active_monitor) { create_cve_monitor(is_active: true) }
    let!(:inactive_monitor) { create_cve_monitor(is_active: false) }
    let!(:image_monitor) { create_cve_monitor(scope_type: "image", scope_id: SecureRandom.uuid) }
    let!(:repository_monitor) { create_cve_monitor(scope_type: "repository", scope_id: SecureRandom.uuid) }
    let!(:account_wide_monitor) { create_cve_monitor(scope_type: "account_wide") }
    let!(:due_monitor) { create_cve_monitor(is_active: true, next_run_at: 1.hour.ago) }
    let!(:not_due_monitor) { create_cve_monitor(is_active: true, next_run_at: 1.hour.from_now) }

    describe ".active" do
      it "returns only active monitors" do
        result = described_class.active.where(account: account)
        expect(result).to include(active_monitor)
        expect(result).not_to include(inactive_monitor)
      end
    end

    describe ".inactive" do
      it "returns only inactive monitors" do
        result = described_class.inactive.where(account: account)
        expect(result).to include(inactive_monitor)
        expect(result).not_to include(active_monitor)
      end
    end

    describe ".by_scope" do
      it "filters by scope type" do
        result = described_class.by_scope("image").where(account: account)
        expect(result).to include(image_monitor)
        expect(result).not_to include(repository_monitor, account_wide_monitor)
      end
    end

    describe ".image_scope" do
      it "returns monitors with image scope" do
        result = described_class.image_scope.where(account: account)
        expect(result).to include(image_monitor)
        expect(result).not_to include(repository_monitor, account_wide_monitor)
      end
    end

    describe ".repository_scope" do
      it "returns monitors with repository scope" do
        result = described_class.repository_scope.where(account: account)
        expect(result).to include(repository_monitor)
        expect(result).not_to include(image_monitor, account_wide_monitor)
      end
    end

    describe ".account_wide" do
      it "returns monitors with account_wide scope" do
        result = described_class.account_wide.where(account: account)
        expect(result).to include(account_wide_monitor)
        expect(result).not_to include(image_monitor, repository_monitor)
      end
    end

    describe ".due_for_run" do
      it "includes active monitors with next_run_at in the past" do
        result = described_class.due_for_run.where(account: account)
        expect(result).to include(due_monitor)
      end

      it "includes active monitors with nil next_run_at" do
        nil_run_monitor = create_cve_monitor(is_active: true, next_run_at: nil)
        result = described_class.due_for_run.where(account: account)
        expect(result).to include(nil_run_monitor)
      end

      it "excludes monitors with future next_run_at" do
        result = described_class.due_for_run.where(account: account)
        expect(result).not_to include(not_due_monitor)
      end

      it "excludes inactive monitors even if next_run_at is past" do
        past_inactive = create_cve_monitor(is_active: false, next_run_at: 1.hour.ago)
        result = described_class.due_for_run.where(account: account)
        expect(result).not_to include(past_inactive)
      end
    end

    describe ".recent" do
      let!(:old_monitor) { create_cve_monitor }
      let!(:new_monitor) { create_cve_monitor }

      before do
        old_monitor.update_column(:created_at, 1.week.ago)
      end

      it "orders by created_at descending" do
        result = described_class.recent.where(account: account)
        ids = result.pluck(:id)
        expect(ids.index(new_monitor.id)).to be < ids.index(old_monitor.id)
      end
    end
  end

  describe "callbacks" do
    describe "sanitize_jsonb_fields" do
      it "initializes notification_channels as empty array" do
        monitor = create_cve_monitor
        expect(monitor.notification_channels).to eq([])
      end

      it "initializes filters as empty hash" do
        monitor = create_cve_monitor
        expect(monitor.filters).to eq({})
      end

      it "initializes metadata as empty hash" do
        monitor = create_cve_monitor
        expect(monitor.metadata).to eq({})
      end

      it "preserves existing notification_channels" do
        channels = [ { "type" => "email", "config" => { "to" => "test@example.com" } } ]
        monitor = create_cve_monitor(notification_channels: channels)
        expect(monitor.notification_channels).to eq(channels)
      end

      it "preserves existing filters" do
        filters = { "severity" => "critical", "status" => "open" }
        monitor = create_cve_monitor(filters: filters)
        expect(monitor.filters).to eq(filters)
      end

      it "preserves existing metadata" do
        metadata = { "source" => "automated", "last_check" => Time.current.iso8601 }
        monitor = create_cve_monitor(metadata: metadata)
        expect(monitor.metadata).to eq(metadata)
      end
    end
  end

  describe "instance methods - predicates" do
    describe "#active?" do
      it "returns true when is_active is true" do
        monitor = build_cve_monitor(is_active: true)
        expect(monitor.active?).to be true
      end

      it "returns false when is_active is false" do
        monitor = build_cve_monitor(is_active: false)
        expect(monitor.active?).to be false
      end
    end

    describe "#image_scope?" do
      it "returns true for image scope_type" do
        monitor = build_cve_monitor(scope_type: "image", scope_id: SecureRandom.uuid)
        expect(monitor.image_scope?).to be true
      end

      it "returns false for other scope types" do
        %w[repository account_wide].each do |scope_type|
          scope_id = scope_type == "account_wide" ? nil : SecureRandom.uuid
          monitor = build_cve_monitor(scope_type: scope_type, scope_id: scope_id)
          expect(monitor.image_scope?).to be false
        end
      end
    end

    describe "#repository_scope?" do
      it "returns true for repository scope_type" do
        monitor = build_cve_monitor(scope_type: "repository", scope_id: SecureRandom.uuid)
        expect(monitor.repository_scope?).to be true
      end

      it "returns false for other scope types" do
        %w[image account_wide].each do |scope_type|
          scope_id = scope_type == "account_wide" ? nil : SecureRandom.uuid
          monitor = build_cve_monitor(scope_type: scope_type, scope_id: scope_id)
          expect(monitor.repository_scope?).to be false
        end
      end
    end

    describe "#account_wide?" do
      it "returns true for account_wide scope_type" do
        monitor = build_cve_monitor(scope_type: "account_wide")
        expect(monitor.account_wide?).to be true
      end

      it "returns false for other scope types" do
        %w[image repository].each do |scope_type|
          monitor = build_cve_monitor(scope_type: scope_type, scope_id: SecureRandom.uuid)
          expect(monitor.account_wide?).to be false
        end
      end
    end

    describe "#due_for_run?" do
      it "returns true when active and next_run_at is nil" do
        monitor = build_cve_monitor(is_active: true, next_run_at: nil)
        expect(monitor.due_for_run?).to be true
      end

      it "returns true when active and next_run_at is in the past" do
        monitor = build_cve_monitor(is_active: true, next_run_at: 1.hour.ago)
        expect(monitor.due_for_run?).to be true
      end

      it "returns true when active and next_run_at is current time" do
        current_time = Time.current
        allow(Time).to receive(:current).and_return(current_time)
        monitor = build_cve_monitor(is_active: true, next_run_at: current_time)
        expect(monitor.due_for_run?).to be true
      end

      it "returns false when active but next_run_at is in the future" do
        monitor = build_cve_monitor(is_active: true, next_run_at: 1.hour.from_now)
        expect(monitor.due_for_run?).to be false
      end

      it "returns false when inactive even if next_run_at is past" do
        monitor = build_cve_monitor(is_active: false, next_run_at: 1.hour.ago)
        expect(monitor.due_for_run?).to be false
      end
    end
  end

  describe "instance methods - severity" do
    describe "#severity_includes?" do
      context "with critical min_severity" do
        let(:monitor) { build_cve_monitor(min_severity: "critical") }

        it "includes critical" do
          expect(monitor.severity_includes?("critical")).to be true
        end

        it "excludes high" do
          expect(monitor.severity_includes?("high")).to be false
        end

        it "excludes medium" do
          expect(monitor.severity_includes?("medium")).to be false
        end

        it "excludes low" do
          expect(monitor.severity_includes?("low")).to be false
        end
      end

      context "with high min_severity" do
        let(:monitor) { build_cve_monitor(min_severity: "high") }

        it "includes critical" do
          expect(monitor.severity_includes?("critical")).to be true
        end

        it "includes high" do
          expect(monitor.severity_includes?("high")).to be true
        end

        it "excludes medium" do
          expect(monitor.severity_includes?("medium")).to be false
        end

        it "excludes low" do
          expect(monitor.severity_includes?("low")).to be false
        end
      end

      context "with medium min_severity" do
        let(:monitor) { build_cve_monitor(min_severity: "medium") }

        it "includes critical" do
          expect(monitor.severity_includes?("critical")).to be true
        end

        it "includes high" do
          expect(monitor.severity_includes?("high")).to be true
        end

        it "includes medium" do
          expect(monitor.severity_includes?("medium")).to be true
        end

        it "excludes low" do
          expect(monitor.severity_includes?("low")).to be false
        end
      end

      context "with low min_severity" do
        let(:monitor) { build_cve_monitor(min_severity: "low") }

        it "includes critical" do
          expect(monitor.severity_includes?("critical")).to be true
        end

        it "includes high" do
          expect(monitor.severity_includes?("high")).to be true
        end

        it "includes medium" do
          expect(monitor.severity_includes?("medium")).to be true
        end

        it "includes low" do
          expect(monitor.severity_includes?("low")).to be true
        end
      end

      it "handles case insensitive input" do
        monitor = build_cve_monitor(min_severity: "high")
        expect(monitor.severity_includes?("Critical")).to be true
        expect(monitor.severity_includes?("HIGH")).to be true
        expect(monitor.severity_includes?("Medium")).to be false
      end

      it "returns false for nil severity" do
        monitor = build_cve_monitor(min_severity: "medium")
        expect(monitor.severity_includes?(nil)).to be false
      end

      it "returns false for invalid severity" do
        monitor = build_cve_monitor(min_severity: "medium")
        expect(monitor.severity_includes?("extreme")).to be false
        expect(monitor.severity_includes?("info")).to be false
      end
    end
  end

  describe "instance methods - state management" do
    describe "#activate!" do
      let(:monitor) { create_cve_monitor(is_active: false) }

      it "sets is_active to true" do
        monitor.activate!
        expect(monitor.is_active).to be true
      end

      it "persists the change" do
        monitor.activate!
        monitor.reload
        expect(monitor.is_active).to be true
      end
    end

    describe "#deactivate!" do
      let(:monitor) { create_cve_monitor(is_active: true) }

      it "sets is_active to false" do
        monitor.deactivate!
        expect(monitor.is_active).to be false
      end

      it "persists the change" do
        monitor.deactivate!
        monitor.reload
        expect(monitor.is_active).to be false
      end
    end

    describe "#mark_run_completed!" do
      let(:monitor) { create_cve_monitor(last_run_at: nil, next_run_at: nil, schedule_cron: "0 0 * * *") }

      it "updates last_run_at to current time" do
        freeze_time do
          monitor.mark_run_completed!
          expect(monitor.last_run_at).to be_within(1.second).of(Time.current)
        end
      end

      it "updates next_run_at when schedule_cron is set" do
        monitor.mark_run_completed!
        expect(monitor.next_run_at).not_to be_nil
      end

      it "persists the changes" do
        monitor.mark_run_completed!
        monitor.reload
        expect(monitor.last_run_at).not_to be_nil
        expect(monitor.next_run_at).not_to be_nil
      end
    end
  end

  describe "instance methods - scoped queries" do
    describe "#scoped_images" do
      context "with image scope" do
        let(:image) { create(:supply_chain_container_image, account: account) }
        let(:monitor) { create_cve_monitor(scope_type: "image", scope_id: image.id) }

        it "returns the specific image" do
          result = monitor.scoped_images
          expect(result).to include(image)
        end

        it "does not return other images" do
          other_image = create(:supply_chain_container_image, account: account)
          result = monitor.scoped_images
          expect(result).not_to include(other_image)
        end

        it "returns empty relation for non-existent image" do
          monitor.scope_id = SecureRandom.uuid
          result = monitor.scoped_images
          expect(result).to be_empty
        end
      end

      context "with repository scope" do
        let(:repo) { Devops::Repository.create!(account: account, provider: devops_provider, name: "test-repo", full_name: "org/test-repo", default_branch: "main") }
        let(:monitor) { create_cve_monitor(scope_type: "repository", scope_id: repo.id) }

        it "returns images matching repository name pattern" do
          matching_image = create(:supply_chain_container_image, account: account, repository: "project/test-repo")
          result = monitor.scoped_images
          expect(result).to include(matching_image)
        end

        it "returns empty relation when repository not found" do
          monitor.scope_id = SecureRandom.uuid
          result = monitor.scoped_images
          expect(result).to be_empty
        end
      end

      context "with account_wide scope" do
        let(:monitor) { create_cve_monitor(scope_type: "account_wide") }

        it "returns all account images" do
          image1 = create(:supply_chain_container_image, account: account)
          image2 = create(:supply_chain_container_image, account: account)
          result = monitor.scoped_images
          expect(result).to include(image1, image2)
        end

        it "does not return images from other accounts" do
          other_account = create(:account)
          other_image = create(:supply_chain_container_image, account: other_account)
          result = monitor.scoped_images
          expect(result).not_to include(other_image)
        end
      end
    end

    describe "#scoped_sboms" do
      context "with repository scope" do
        let(:repo) { Devops::Repository.create!(account: account, provider: devops_provider, name: "sbom-repo", full_name: "org/sbom-repo", default_branch: "main") }
        let(:monitor) { create_cve_monitor(scope_type: "repository", scope_id: repo.id) }

        it "returns sboms for the repository" do
          sbom = create(:supply_chain_sbom, account: account, repository_id: repo.id)
          result = monitor.scoped_sboms
          expect(result).to include(sbom)
        end

        it "does not return sboms from other repositories" do
          other_repo = Devops::Repository.create!(account: account, provider: devops_provider, name: "other-repo", full_name: "org/other-repo", default_branch: "main")
          other_sbom = create(:supply_chain_sbom, account: account, repository_id: other_repo.id)
          result = monitor.scoped_sboms
          expect(result).not_to include(other_sbom)
        end
      end

      context "with account_wide scope" do
        let(:monitor) { create_cve_monitor(scope_type: "account_wide") }

        it "returns all account sboms" do
          sbom1 = create(:supply_chain_sbom, account: account)
          sbom2 = create(:supply_chain_sbom, account: account)
          result = monitor.scoped_sboms
          expect(result).to include(sbom1, sbom2)
        end

        it "does not return sboms from other accounts" do
          other_account = create(:account)
          other_sbom = create(:supply_chain_sbom, account: other_account)
          result = monitor.scoped_sboms
          expect(result).not_to include(other_sbom)
        end
      end

      context "with image scope" do
        let(:image) { create(:supply_chain_container_image, account: account) }
        let(:monitor) { create_cve_monitor(scope_type: "image", scope_id: image.id) }

        it "returns empty relation" do
          result = monitor.scoped_sboms
          expect(result).to be_empty
        end
      end
    end
  end

  describe "instance methods - notification channels" do
    describe "#notification_channel_count" do
      it "returns 0 when notification_channels is empty" do
        monitor = build_cve_monitor(notification_channels: [])
        expect(monitor.notification_channel_count).to eq(0)
      end

      it "returns correct count for multiple channels" do
        channels = [
          { type: "email", config: {} },
          { type: "slack", config: {} },
          { type: "webhook", config: {} }
        ]
        monitor = build_cve_monitor(notification_channels: channels)
        expect(monitor.notification_channel_count).to eq(3)
      end
    end

    describe "#add_notification_channel" do
      let(:monitor) { create_cve_monitor(notification_channels: []) }

      it "adds a new notification channel" do
        expect {
          monitor.add_notification_channel(type: "email", config: { to: "test@example.com" })
        }.to change { monitor.notification_channels.length }.by(1)
      end

      it "includes the channel type" do
        monitor.add_notification_channel(type: "slack", config: { webhook_url: "https://hooks.slack.com/test" })
        channel = monitor.notification_channels.last
        expect(channel["type"]).to eq("slack")
      end

      it "includes the channel config" do
        config = { webhook_url: "https://hooks.slack.com/test" }
        monitor.add_notification_channel(type: "slack", config: config)
        channel = monitor.notification_channels.last
        expect(channel["config"]).to eq(config.deep_stringify_keys)
      end

      it "includes added_at timestamp" do
        freeze_time do
          monitor.add_notification_channel(type: "email", config: {})
          channel = monitor.notification_channels.last
          expect(channel["added_at"]).to eq(Time.current.iso8601)
        end
      end

      it "persists the change" do
        monitor.add_notification_channel(type: "email", config: { to: "test@example.com" })
        monitor.reload
        expect(monitor.notification_channels.length).to eq(1)
      end

      it "appends to existing channels" do
        monitor.update!(notification_channels: [ { type: "email", config: {} } ])
        monitor.add_notification_channel(type: "slack", config: {})
        expect(monitor.notification_channels.length).to eq(2)
      end
    end

    describe "#remove_notification_channel" do
      let(:monitor) do
        create_cve_monitor(
          notification_channels: [
            { "type" => "email", "config" => {} },
            { "type" => "slack", "config" => {} },
            { "type" => "webhook", "config" => {} }
          ]
        )
      end

      it "removes the specified channel type" do
        expect {
          monitor.remove_notification_channel("slack")
        }.to change { monitor.notification_channels.length }.by(-1)
      end

      it "removes only the matching channel" do
        monitor.remove_notification_channel("slack")
        types = monitor.notification_channels.map { |c| c["type"] }
        expect(types).not_to include("slack")
        expect(types).to include("email", "webhook")
      end

      it "persists the change" do
        monitor.remove_notification_channel("email")
        monitor.reload
        types = monitor.notification_channels.map { |c| c["type"] }
        expect(types).not_to include("email")
      end

      it "handles removing non-existent channel type" do
        expect {
          monitor.remove_notification_channel("non_existent")
        }.not_to change { monitor.notification_channels.length }
      end
    end
  end

  describe "instance methods - summary" do
    describe "#summary" do
      let(:monitor) do
        create_cve_monitor(
          name: "Critical CVE Monitor",
          description: "Monitors critical CVEs",
          scope_type: "account_wide",
          scope_id: nil,
          min_severity: "critical",
          schedule_cron: "0 0 * * *",
          is_active: true,
          last_run_at: 1.hour.ago,
          next_run_at: 23.hours.from_now,
          notification_channels: [ { type: "email", config: {} } ]
        )
      end

      it "returns a hash with expected keys" do
        summary = monitor.summary
        expect(summary).to include(
          :id,
          :name,
          :description,
          :scope_type,
          :scope_id,
          :min_severity,
          :schedule_cron,
          :is_active,
          :last_run_at,
          :next_run_at,
          :notification_channel_count,
          :created_at
        )
      end

      it "includes correct values" do
        summary = monitor.summary
        expect(summary[:name]).to eq("Critical CVE Monitor")
        expect(summary[:description]).to eq("Monitors critical CVEs")
        expect(summary[:scope_type]).to eq("account_wide")
        expect(summary[:min_severity]).to eq("critical")
        expect(summary[:schedule_cron]).to eq("0 0 * * *")
        expect(summary[:is_active]).to be true
      end

      it "includes notification_channel_count" do
        summary = monitor.summary
        expect(summary[:notification_channel_count]).to eq(1)
      end

      it "includes id" do
        summary = monitor.summary
        expect(summary[:id]).to eq(monitor.id)
      end

      it "includes scope_id when present" do
        image = create(:supply_chain_container_image, account: account)
        image_monitor = create_cve_monitor(scope_type: "image", scope_id: image.id)
        summary = image_monitor.summary
        expect(summary[:scope_id]).to eq(image.id)
      end
    end
  end

  describe "concerns" do
    describe "Auditable" do
      it "includes Auditable module" do
        expect(described_class.included_modules).to include(Auditable)
      end

      it "has audit callbacks" do
        expect(described_class._create_callbacks.map(&:filter)).to include(:log_record_creation)
        expect(described_class._update_callbacks.map(&:filter)).to include(:log_record_update)
        expect(described_class._destroy_callbacks.map(&:filter)).to include(:log_record_deletion)
      end
    end
  end

  describe "edge cases" do
    it "allows creation without created_by user" do
      monitor = build_cve_monitor(created_by: nil)
      expect(monitor).to be_valid
    end

    it "accepts valid UUID for scope_id" do
      uuid = SecureRandom.uuid
      monitor = build_cve_monitor(scope_type: "image", scope_id: uuid)
      expect(monitor).to be_valid
    end

    it "allows nil scope_id for account_wide" do
      monitor = build_cve_monitor(scope_type: "account_wide", scope_id: nil)
      expect(monitor).to be_valid
    end
  end
end
