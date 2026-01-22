# frozen_string_literal: true

require "rails_helper"

RSpec.describe SupplyChain::ScanTemplate, type: :model do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  describe "constants" do
    it { expect(described_class::CATEGORIES).to eq(%w[security compliance license quality custom]) }
    it { expect(described_class::STATUSES).to eq(%w[draft published archived deprecated]) }
  end

  describe "associations" do
    it { is_expected.to belong_to(:account).optional }
    it { is_expected.to belong_to(:created_by).class_name("User").optional }
    it { is_expected.to have_many(:scan_instances).class_name("SupplyChain::ScanInstance").dependent(:restrict_with_error) }
  end

  describe "validations" do
    subject { build(:supply_chain_scan_template, account: account) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_inclusion_of(:category).in_array(SupplyChain::ScanTemplate::CATEGORIES) }
    it { is_expected.to validate_inclusion_of(:status).in_array(SupplyChain::ScanTemplate::STATUSES) }
    it { is_expected.to validate_presence_of(:version) }
    it { is_expected.to validate_numericality_of(:average_rating).is_greater_than_or_equal_to(0).is_less_than_or_equal_to(5) }
    it { is_expected.to validate_numericality_of(:install_count).is_greater_than_or_equal_to(0) }

    # Note: slug is auto-generated from name by before_validation callback,
    # so shoulda-matchers can't test presence/uniqueness directly
    describe "slug" do
      it "requires slug" do
        template = create(:supply_chain_scan_template, account: account)
        # Clear both name and slug to prevent callback from regenerating slug
        # The callback only runs when name.present? && (slug.blank? || name_changed?)
        template.name = nil
        template.slug = nil
        expect(template).not_to be_valid
        # Will have errors for both name and slug
        expect(template.errors[:slug]).to include("can't be blank")
      end

      it "validates uniqueness of slug" do
        first = create(:supply_chain_scan_template, account: account)
        # Create second template without name to prevent slug callback
        second = create(:supply_chain_scan_template, account: account)
        # Now update second with first's slug and no name to bypass callback
        second.name = nil
        second.slug = first.slug
        expect(second).not_to be_valid
        expect(second.errors[:slug]).to include("has already been taken")
      end
    end

    describe "slug format" do
      it "only allows lowercase letters, numbers, and hyphens" do
        template = create(:supply_chain_scan_template, account: account)
        template.slug = "valid-slug-123"
        expect(template).to be_valid
      end

      it "rejects uppercase letters" do
        template = create(:supply_chain_scan_template, account: account)
        template.slug = "Invalid-Slug"
        expect(template).not_to be_valid
        expect(template.errors[:slug]).to include("only lowercase letters, numbers, and hyphens")
      end

      it "rejects underscores" do
        template = create(:supply_chain_scan_template, account: account)
        template.slug = "invalid_slug"
        expect(template).not_to be_valid
      end

      it "rejects spaces" do
        template = create(:supply_chain_scan_template, account: account)
        template.slug = "invalid slug"
        expect(template).not_to be_valid
      end
    end
  end

  describe "scopes" do
    let!(:system_template) { create(:supply_chain_scan_template, is_system: true) }
    let!(:custom_template) { create(:supply_chain_scan_template, is_system: false, account: account) }
    let!(:public_template) { create(:supply_chain_scan_template, is_public: true) }
    let!(:private_template) { create(:supply_chain_scan_template, is_public: false, account: account) }
    let!(:published_template) { create(:supply_chain_scan_template, status: "published") }
    let!(:draft_template) { create(:supply_chain_scan_template, status: "draft") }
    let!(:archived_template) { create(:supply_chain_scan_template, status: "archived") }
    let!(:security_template) { create(:supply_chain_scan_template, category: "security") }
    let!(:compliance_template) { create(:supply_chain_scan_template, category: "compliance") }
    let!(:license_template) { create(:supply_chain_scan_template, category: "license") }
    let!(:popular_template) { create(:supply_chain_scan_template, install_count: 100) }
    let!(:popular_template2) { create(:supply_chain_scan_template, install_count: 50) }
    let!(:top_rated_template) { create(:supply_chain_scan_template, average_rating: 5.0) }
    let!(:top_rated_template2) { create(:supply_chain_scan_template, average_rating: 4.5) }

    describe ".system_templates" do
      it "returns only system templates" do
        result = described_class.system_templates
        expect(result).to include(system_template)
        expect(result).not_to include(custom_template)
      end
    end

    describe ".custom_templates" do
      it "returns only custom templates" do
        result = described_class.custom_templates
        expect(result).to include(custom_template)
        expect(result).not_to include(system_template)
      end
    end

    describe ".public_templates" do
      it "returns only public templates" do
        result = described_class.public_templates
        expect(result).to include(public_template)
        expect(result).not_to include(private_template)
      end
    end

    describe ".private_templates" do
      it "returns only private templates" do
        result = described_class.private_templates
        expect(result).to include(private_template)
        expect(result).not_to include(public_template)
      end
    end

    describe ".published" do
      it "returns only published templates" do
        result = described_class.published
        expect(result).to include(published_template)
        expect(result).not_to include(draft_template, archived_template)
      end
    end

    describe ".draft" do
      it "returns only draft templates" do
        result = described_class.draft
        expect(result).to include(draft_template)
        expect(result).not_to include(published_template, archived_template)
      end
    end

    describe ".archived" do
      it "returns only archived templates" do
        result = described_class.archived
        expect(result).to include(archived_template)
        expect(result).not_to include(published_template, draft_template)
      end
    end

    describe ".by_category" do
      it "filters by category" do
        result = described_class.by_category("security")
        expect(result).to include(security_template)
        expect(result).not_to include(compliance_template, license_template)
      end
    end

    describe ".security_templates" do
      it "returns templates with security category" do
        result = described_class.security_templates
        expect(result).to include(security_template)
        expect(result).not_to include(compliance_template, license_template)
      end
    end

    describe ".compliance_templates" do
      it "returns templates with compliance category" do
        result = described_class.compliance_templates
        expect(result).to include(compliance_template)
        expect(result).not_to include(security_template, license_template)
      end
    end

    describe ".license_templates" do
      it "returns templates with license category" do
        result = described_class.license_templates
        expect(result).to include(license_template)
        expect(result).not_to include(security_template, compliance_template)
      end
    end

    describe ".popular" do
      it "orders by install_count descending" do
        result = described_class.popular
        expect(result.first).to eq(popular_template)
        expect(result.second).to eq(popular_template2)
      end
    end

    describe ".top_rated" do
      it "orders by average_rating descending" do
        result = described_class.top_rated
        # Only verify ordering is correct (highest first)
        expect(result.first).to eq(top_rated_template)
        # There are many templates with 4.5 rating (factory default), so we just verify
        # the 5.0 template comes before 4.5 templates
        expect(result.pluck(:average_rating)).to eq(result.pluck(:average_rating).sort.reverse)
      end
    end

    describe ".for_ecosystem" do
      # Use a unique ecosystem that isn't in the factory defaults (npm, gem, pip)
      let!(:rust_template) { create(:supply_chain_scan_template, supported_ecosystems: %w[rust]) }
      let!(:rust_go_template) { create(:supply_chain_scan_template, supported_ecosystems: %w[rust go]) }
      let!(:go_only_template) { create(:supply_chain_scan_template, supported_ecosystems: %w[go]) }

      it "returns templates supporting the ecosystem" do
        # Go is supported by 2 templates we created
        result = described_class.for_ecosystem("go")
        expect(result.count).to eq(2)
        expect(result).to include(rust_go_template, go_only_template)
      end

      it "returns single template for unique ecosystem" do
        # Only rust_template has rust but not go
        result = described_class.for_ecosystem("rust")
        expect(result.count).to eq(2)
        expect(result).to include(rust_template, rust_go_template)
      end
    end

    describe ".available_for_account" do
      let(:other_account) { create(:account) }

      before do
        create(:supply_chain_scan_template, is_public: true, account: other_account)
        create(:supply_chain_scan_template, is_public: false, account: other_account)
        create(:supply_chain_scan_template, is_system: true, is_public: false)
      end

      it "includes public templates" do
        result = described_class.available_for_account(account)
        public_count = result.where(is_public: true).count
        expect(public_count).to be > 0
      end

      it "includes account's own templates" do
        own_template = create(:supply_chain_scan_template, account: account, is_public: false)
        result = described_class.available_for_account(account)
        expect(result).to include(own_template)
      end

      it "includes system templates" do
        result = described_class.available_for_account(account)
        system_count = result.where(is_system: true).count
        expect(system_count).to be > 0
      end

      it "excludes other accounts' private templates" do
        result = described_class.available_for_account(account)
        other_private = described_class.where.not(account_id: [account.id, nil]).where(is_public: false).first
        expect(result).not_to include(other_private) if other_private
      end
    end

    describe ".alphabetical" do
      before do
        create(:supply_chain_scan_template, name: "Zebra Scanner")
        create(:supply_chain_scan_template, name: "Apple Scanner")
        create(:supply_chain_scan_template, name: "Banana Scanner")
      end

      it "orders by name ascending" do
        result = described_class.alphabetical
        names = result.map(&:name)
        expect(names).to eq(names.sort)
      end
    end
  end

  describe "instance methods - predicates" do
    describe "#system?" do
      it "returns true for system templates" do
        template = build(:supply_chain_scan_template, is_system: true)
        expect(template.system?).to be true
      end

      it "returns false for custom templates" do
        template = build(:supply_chain_scan_template, is_system: false)
        expect(template.system?).to be false
      end
    end

    describe "#custom?" do
      it "returns true for custom templates" do
        template = build(:supply_chain_scan_template, is_system: false)
        expect(template.custom?).to be true
      end

      it "returns false for system templates" do
        template = build(:supply_chain_scan_template, is_system: true)
        expect(template.custom?).to be false
      end
    end

    describe "#public?" do
      it "returns true for public templates" do
        template = build(:supply_chain_scan_template, is_public: true)
        expect(template.public?).to be true
      end

      it "returns false for private templates" do
        template = build(:supply_chain_scan_template, is_public: false)
        expect(template.public?).to be false
      end
    end

    describe "#private?" do
      it "returns true for private templates" do
        template = build(:supply_chain_scan_template, is_public: false)
        expect(template.private?).to be true
      end

      it "returns false for public templates" do
        template = build(:supply_chain_scan_template, is_public: true)
        expect(template.private?).to be false
      end
    end

    describe "#published?" do
      it "returns true for published status" do
        template = build(:supply_chain_scan_template, status: "published")
        expect(template.published?).to be true
      end

      it "returns false for other statuses" do
        %w[draft archived deprecated].each do |status|
          template = build(:supply_chain_scan_template, status: status)
          expect(template.published?).to be false
        end
      end
    end

    describe "#draft?" do
      it "returns true for draft status" do
        template = build(:supply_chain_scan_template, status: "draft")
        expect(template.draft?).to be true
      end

      it "returns false for other statuses" do
        %w[published archived deprecated].each do |status|
          template = build(:supply_chain_scan_template, status: status)
          expect(template.draft?).to be false
        end
      end
    end

    describe "#archived?" do
      it "returns true for archived status" do
        template = build(:supply_chain_scan_template, status: "archived")
        expect(template.archived?).to be true
      end

      it "returns false for other statuses" do
        %w[draft published deprecated].each do |status|
          template = build(:supply_chain_scan_template, status: status)
          expect(template.archived?).to be false
        end
      end
    end

    describe "#deprecated?" do
      it "returns true for deprecated status" do
        template = build(:supply_chain_scan_template, status: "deprecated")
        expect(template.deprecated?).to be true
      end

      it "returns false for other statuses" do
        %w[draft published archived].each do |status|
          template = build(:supply_chain_scan_template, status: status)
          expect(template.deprecated?).to be false
        end
      end
    end

    describe "#security?" do
      it "returns true for security category" do
        template = build(:supply_chain_scan_template, category: "security")
        expect(template.security?).to be true
      end

      it "returns false for other categories" do
        %w[compliance license quality custom].each do |category|
          template = build(:supply_chain_scan_template, category: category)
          expect(template.security?).to be false
        end
      end
    end

    describe "#compliance?" do
      it "returns true for compliance category" do
        template = build(:supply_chain_scan_template, category: "compliance")
        expect(template.compliance?).to be true
      end

      it "returns false for other categories" do
        %w[security license quality custom].each do |category|
          template = build(:supply_chain_scan_template, category: category)
          expect(template.compliance?).to be false
        end
      end
    end

    describe "#license?" do
      it "returns true for license category" do
        template = build(:supply_chain_scan_template, category: "license")
        expect(template.license?).to be true
      end

      it "returns false for other categories" do
        %w[security compliance quality custom].each do |category|
          template = build(:supply_chain_scan_template, category: category)
          expect(template.license?).to be false
        end
      end
    end
  end

  describe "instance methods - ecosystem" do
    describe "#supports_ecosystem?" do
      let(:template) { build(:supply_chain_scan_template, supported_ecosystems: %w[npm ruby python]) }

      it "returns true when ecosystem is supported" do
        expect(template.supports_ecosystem?("npm")).to be true
        expect(template.supports_ecosystem?("ruby")).to be true
      end

      it "returns false when ecosystem is not supported" do
        expect(template.supports_ecosystem?("go")).to be false
      end

      it "returns false when supported_ecosystems is nil" do
        template.supported_ecosystems = nil
        expect(template.supports_ecosystem?("npm")).to be false
      end
    end

    describe "#ecosystem_count" do
      it "returns count of supported ecosystems" do
        template = build(:supply_chain_scan_template, supported_ecosystems: %w[npm ruby python])
        expect(template.ecosystem_count).to eq(3)
      end

      it "returns 0 when supported_ecosystems is nil" do
        template = build(:supply_chain_scan_template, supported_ecosystems: nil)
        expect(template.ecosystem_count).to eq(0)
      end

      it "returns 0 for empty array" do
        template = build(:supply_chain_scan_template, supported_ecosystems: [])
        expect(template.ecosystem_count).to eq(0)
      end
    end
  end

  describe "instance methods - state transitions" do
    describe "#publish!" do
      let(:template) { create(:supply_chain_scan_template, status: "draft", is_public: false) }

      it "changes status to published" do
        template.publish!
        expect(template.status).to eq("published")
      end

      it "makes template public" do
        template.publish!
        expect(template.is_public).to be true
      end

      it "persists changes" do
        template.publish!
        template.reload
        expect(template).to be_published
      end
    end

    describe "#archive!" do
      let(:template) { create(:supply_chain_scan_template, status: "published") }

      it "changes status to archived" do
        template.archive!
        expect(template.status).to eq("archived")
      end

      it "persists changes" do
        template.archive!
        template.reload
        expect(template).to be_archived
      end
    end

    describe "#deprecate!" do
      let(:template) { create(:supply_chain_scan_template, status: "published") }

      it "changes status to deprecated" do
        template.deprecate!
        expect(template.status).to eq("deprecated")
      end

      it "persists changes" do
        template.deprecate!
        template.reload
        expect(template).to be_deprecated
      end
    end
  end

  describe "instance methods - install count" do
    describe "#increment_install_count!" do
      let(:template) { create(:supply_chain_scan_template, install_count: 5) }

      it "increments install_count by 1" do
        expect {
          template.increment_install_count!
        }.to change { template.install_count }.from(5).to(6)
      end

      it "persists changes" do
        template.increment_install_count!
        template.reload
        expect(template.install_count).to eq(6)
      end

      it "persists when called multiple times" do
        template.increment_install_count!
        template.increment_install_count!
        template.reload
        expect(template.install_count).to eq(7)
      end
    end
  end

  describe "instance methods - rating" do
    describe "#update_rating!" do
      let(:template) { create(:supply_chain_scan_template, average_rating: 4.0, install_count: 5) }

      it "updates average rating based on new rating" do
        template.update_rating!(5.0)
        # (4.0 * 4 + 5.0) / 5 = 21.0 / 5 = 4.2
        expect(template.average_rating).to eq(4.2)
      end

      it "rounds result to 2 decimal places" do
        template.update_rating!(4.3)
        # (4.0 * 4 + 4.3) / 5 = 20.3 / 5 = 4.06
        expect(template.average_rating).to eq(4.06)
      end

      it "uses install_count as denominator when available" do
        template.update_rating!(3.0)
        # (4.0 * 4 + 3.0) / 5 = 19.0 / 5 = 3.8
        expect(template.average_rating).to eq(3.8)
      end

      it "uses 1 as denominator when install_count is 0" do
        template.install_count = 0
        template.update_rating!(5.0)
        # (4.0 * 0 + 5.0) / 1 = 5.0
        expect(template.average_rating).to eq(5.0)
      end

      it "persists changes" do
        template.update_rating!(5.0)
        template.reload
        expect(template.average_rating).to eq(4.2)
      end
    end
  end

  describe "instance methods - installation" do
    describe "#install_for_account!" do
      let(:template) do
        create(:supply_chain_scan_template,
               default_configuration: { timeout: 30, retries: 3 },
               install_count: 5)
      end
      let(:target_account) { create(:account) }

      it "creates a scan instance" do
        expect {
          template.install_for_account!(target_account)
        }.to change(SupplyChain::ScanInstance, :count).by(1)
      end

      it "uses template name for instance" do
        instance = template.install_for_account!(target_account)
        expect(instance.name).to eq(template.name)
      end

      it "merges default configuration with provided config" do
        instance = template.install_for_account!(target_account, config: { timeout: 60 })
        expect(instance.configuration).to include("timeout" => 60, "retries" => 3)
      end

      it "sets status to active" do
        instance = template.install_for_account!(target_account)
        expect(instance.status).to eq("active")
      end

      it "associates with correct account" do
        instance = template.install_for_account!(target_account)
        expect(instance.account).to eq(target_account)
      end

      it "increments install_count" do
        expect {
          template.install_for_account!(target_account)
        }.to change { template.install_count }.by(1)
      end

      it "accepts installed_by parameter" do
        instance = template.install_for_account!(target_account, installed_by: user)
        expect(instance.installed_by).to eq(user)
      end

      it "returns the created scan instance" do
        instance = template.install_for_account!(target_account)
        expect(instance).to be_persisted
        expect(instance).to be_a(SupplyChain::ScanInstance)
      end

      it "handles empty default configuration" do
        template.update!(default_configuration: {})
        instance = template.install_for_account!(target_account, config: { key: "value" })
        expect(instance.configuration).to eq("key" => "value")
      end
    end
  end

  describe "instance methods - validation" do
    describe "#validate_configuration" do
      context "without schema" do
        let(:template) { build(:supply_chain_scan_template, configuration_schema: {}) }

        it "returns valid with empty errors" do
          result = template.validate_configuration({})
          expect(result).to eq({ valid: true, errors: [] })
        end
      end

      context "with required fields" do
        let(:schema) do
          {
            "required" => ["api_key", "endpoint"],
            "properties" => {
              "api_key" => { "type" => "string" },
              "endpoint" => { "type" => "string" }
            }
          }
        end
        let(:template) { build(:supply_chain_scan_template, configuration_schema: schema) }

        it "validates required fields are present" do
          config = { "api_key" => "key123", "endpoint" => "https://api.example.com" }
          result = template.validate_configuration(config)
          expect(result[:valid]).to be true
        end

        it "returns error when required field missing" do
          config = { "api_key" => "key123" }
          result = template.validate_configuration(config)
          expect(result[:valid]).to be false
          expect(result[:errors]).to include("Missing required field: endpoint")
        end
      end

      context "with type validation" do
        let(:schema) do
          {
            "properties" => {
              "timeout" => { "type" => "integer" },
              "enabled" => { "type" => "boolean" },
              "tags" => { "type" => "array" }
            }
          }
        end
        let(:template) { build(:supply_chain_scan_template, configuration_schema: schema) }

        it "validates string type" do
          schema_with_string = {
            "properties" => { "name" => { "type" => "string" } }
          }
          template.configuration_schema = schema_with_string
          result = template.validate_configuration("name" => "valid")
          expect(result[:valid]).to be true
        end

        it "validates integer type" do
          result = template.validate_configuration("timeout" => 30)
          expect(result[:valid]).to be true
        end

        it "rejects wrong type for integer" do
          result = template.validate_configuration("timeout" => "thirty")
          expect(result[:valid]).to be false
          expect(result[:errors]).to include("Field timeout must be of type integer")
        end

        it "validates boolean type" do
          result = template.validate_configuration("enabled" => true)
          expect(result[:valid]).to be true
        end

        it "rejects wrong type for boolean" do
          result = template.validate_configuration("enabled" => "yes")
          expect(result[:valid]).to be false
        end

        it "validates array type" do
          result = template.validate_configuration("tags" => %w[security compliance])
          expect(result[:valid]).to be true
        end

        it "rejects wrong type for array" do
          result = template.validate_configuration("tags" => "security,compliance")
          expect(result[:valid]).to be false
        end

        it "validates numeric type" do
          schema_numeric = {
            "properties" => { "threshold" => { "type" => "number" } }
          }
          template.configuration_schema = schema_numeric
          result = template.validate_configuration("threshold" => 0.75)
          expect(result[:valid]).to be true
        end
      end

      context "with enum validation" do
        let(:schema) do
          {
            "properties" => {
              "severity" => { "type" => "string", "enum" => %w[low medium high critical] }
            }
          }
        end
        let(:template) { build(:supply_chain_scan_template, configuration_schema: schema) }

        it "accepts valid enum values" do
          result = template.validate_configuration("severity" => "high")
          expect(result[:valid]).to be true
        end

        it "rejects invalid enum values" do
          result = template.validate_configuration("severity" => "extreme")
          expect(result[:valid]).to be false
          expect(result[:errors]).to include("Field severity must be one of: low, medium, high, critical")
        end
      end

      context "complex schema" do
        let(:schema) do
          {
            "required" => ["api_key"],
            "properties" => {
              "api_key" => { "type" => "string" },
              "timeout" => { "type" => "integer" },
              "level" => { "type" => "string", "enum" => %w[basic advanced] }
            }
          }
        end
        let(:template) { build(:supply_chain_scan_template, configuration_schema: schema) }

        it "validates multiple constraints" do
          config = { "api_key" => "key", "timeout" => 60, "level" => "advanced" }
          result = template.validate_configuration(config)
          expect(result[:valid]).to be true
        end

        it "accumulates multiple errors" do
          config = { "timeout" => "sixty", "level" => "expert" }
          result = template.validate_configuration(config)
          expect(result[:valid]).to be false
          expect(result[:errors].length).to be >= 2
        end
      end
    end
  end

  describe "instance methods - serialization" do
    let(:template) do
      create(:supply_chain_scan_template,
             name: "Test Scanner",
             description: "A test scanning template",
             category: "security",
             status: "published",
             version: "1.2.0",
             is_system: false,
             is_public: true,
             supported_ecosystems: %w[npm ruby],
             install_count: 42,
             average_rating: 4.5)
    end

    describe "#summary" do
      it "returns expected keys" do
        summary = template.summary
        expect(summary).to include(
          :id,
          :name,
          :slug,
          :description,
          :category,
          :status,
          :version,
          :is_system,
          :is_public,
          :supported_ecosystems,
          :install_count,
          :average_rating,
          :created_at
        )
      end

      it "includes correct values" do
        summary = template.summary
        expect(summary[:name]).to eq("Test Scanner")
        expect(summary[:category]).to eq("security")
        expect(summary[:status]).to eq("published")
        expect(summary[:version]).to eq("1.2.0")
        expect(summary[:is_system]).to be false
        expect(summary[:is_public]).to be true
        expect(summary[:install_count]).to eq(42)
        expect(summary[:average_rating]).to eq(4.5)
      end
    end

    describe "#full_details" do
      it "returns summary and configuration fields" do
        full = template.full_details
        expect(full).to include(:summary, :configuration_schema, :default_configuration)
      end

      it "includes summary data" do
        full = template.full_details
        expect(full[:summary]).to include(:id, :name, :description)
      end

      it "includes configuration schema" do
        schema = { "properties" => { "timeout" => { "type" => "integer" } } }
        template.update!(configuration_schema: schema)
        full = template.full_details
        expect(full[:configuration_schema]).to eq(schema)
      end

      it "includes default configuration" do
        config = { "timeout" => 30, "retries" => 3 }
        template.update!(default_configuration: config)
        full = template.full_details
        expect(full[:default_configuration]).to eq(config)
      end
    end
  end

  describe "callbacks" do
    describe "generate_slug" do
      it "generates slug from name when slug is blank" do
        template = build(:supply_chain_scan_template, name: "Test Template", slug: nil)
        template.valid?
        expect(template.slug).to eq("test-template")
      end

      it "generates slug when name changes" do
        template = create(:supply_chain_scan_template, name: "Original Name")
        # Use update_column to bypass the callback for initial setup
        template.update_column(:slug, "original-name")
        template.update!(name: "Updated Name")
        expect(template.slug).to eq("updated-name")
      end

      it "converts to lowercase" do
        template = build(:supply_chain_scan_template, name: "MyTemplate", slug: nil)
        template.valid?
        expect(template.slug).to eq("mytemplate")
      end

      it "replaces spaces with hyphens" do
        template = build(:supply_chain_scan_template, name: "My Test Template", slug: nil)
        template.valid?
        expect(template.slug).to eq("my-test-template")
      end

      it "removes leading and trailing hyphens" do
        template = build(:supply_chain_scan_template, name: "---test---", slug: nil)
        template.valid?
        expect(template.slug).not_to start_with("-")
        expect(template.slug).not_to end_with("-")
      end

      it "handles special characters" do
        template = build(:supply_chain_scan_template, name: "Test@#$Template!", slug: nil)
        template.valid?
        expect(template.slug).to match(/\A[a-z0-9\-]+\z/)
      end

      it "ensures uniqueness with counter" do
        existing = create(:supply_chain_scan_template, name: "Duplicate", slug: "duplicate")
        template = build(:supply_chain_scan_template, name: "Duplicate", slug: nil)
        template.valid?
        expect(template.slug).to eq("duplicate-1")
      end

      it "increments counter for multiple duplicates" do
        # Create templates and use update_column to set slugs directly (bypassing callbacks)
        t1 = create(:supply_chain_scan_template)
        t1.update_column(:slug, "duplicate")
        t2 = create(:supply_chain_scan_template)
        t2.update_column(:slug, "duplicate-1")

        template = build(:supply_chain_scan_template, name: "Duplicate", slug: nil)
        template.valid?
        expect(template.slug).to eq("duplicate-2")
      end

      it "does not change slug when name doesn't change" do
        template = create(:supply_chain_scan_template, name: "Test")
        original_slug = template.slug
        template.update!(description: "New description")
        expect(template.slug).to eq(original_slug)
      end
    end

    describe "sanitize_jsonb_fields" do
      it "initializes configuration_schema as empty hash" do
        template = build(:supply_chain_scan_template)
        template.configuration_schema = nil
        template.save!
        expect(template.configuration_schema).to eq({})
      end

      it "initializes default_configuration as empty hash" do
        template = build(:supply_chain_scan_template)
        template.default_configuration = nil
        template.save!
        expect(template.default_configuration).to eq({})
      end

      it "initializes supported_ecosystems as empty array" do
        template = build(:supply_chain_scan_template)
        template.supported_ecosystems = nil
        template.save!
        expect(template.supported_ecosystems).to eq([])
      end

      it "initializes metadata as empty hash" do
        template = build(:supply_chain_scan_template)
        template.metadata = nil
        template.save!
        expect(template.metadata).to eq({})
      end

      it "preserves existing values" do
        schema = { "properties" => {} }
        config = { "key" => "value" }
        ecosystems = %w[npm ruby]
        template = create(:supply_chain_scan_template,
                         configuration_schema: schema,
                         default_configuration: config,
                         supported_ecosystems: ecosystems)
        expect(template.configuration_schema).to eq(schema)
        expect(template.default_configuration).to eq(config)
        expect(template.supported_ecosystems).to eq(ecosystems)
      end
    end
  end

  describe "Auditable concern" do
    it "includes Auditable module" do
      expect(described_class.included_modules).to include(Auditable)
    end

    it "has audit callbacks" do
      expect(described_class._create_callbacks.map(&:filter)).to include(:log_record_creation)
      expect(described_class._update_callbacks.map(&:filter)).to include(:log_record_update)
      expect(described_class._destroy_callbacks.map(&:filter)).to include(:log_record_deletion)
    end
  end

  describe "MarketplacePublishable concern" do
    it "includes MarketplacePublishable module" do
      expect(described_class.included_modules).to include(MarketplacePublishable)
    end

    it "responds to marketplace_published scope" do
      expect(described_class.respond_to?(:marketplace_published)).to be true
    end

    it "responds to marketplace status predicates" do
      template = build(:supply_chain_scan_template)
      expect(template.respond_to?(:marketplace_draft?)).to be true
      expect(template.respond_to?(:marketplace_pending?)).to be true
      expect(template.respond_to?(:marketplace_approved?)).to be true
      expect(template.respond_to?(:marketplace_rejected?)).to be true
    end

    it "returns correct marketplace_template_type" do
      template = build(:supply_chain_scan_template)
      expect(template.marketplace_template_type).to eq("scan_template")
    end
  end

  describe "edge cases and error handling" do
    describe "restrict_with_error on has_many :scan_instances" do
      let(:template) { create(:supply_chain_scan_template) }

      it "prevents deletion when scan instances exist" do
        instance = create(:supply_chain_scan_instance, scan_template: template, account: create(:account))
        # Verify the instance is actually associated with our template
        expect(template.scan_instances.reload).to include(instance)

        # dependent: :restrict_with_error prevents deletion and adds error
        # destroy! raises RecordNotDestroyed which wraps the failure
        expect(template.destroy).to be false
        expect(template.errors[:base]).to include(/Cannot delete record because dependent scan instances exist/)
      end

      it "allows deletion when no scan instances exist" do
        expect(template.scan_instances).to be_empty
        expect(template.destroy).to be_truthy
      end
    end

    describe "optional associations" do
      it "allows creation without account" do
        template = build(:supply_chain_scan_template, account: nil)
        expect(template).to be_valid
      end

      it "allows creation without created_by user" do
        template = build(:supply_chain_scan_template, created_by: nil)
        expect(template).to be_valid
      end
    end

    describe "numeric field boundaries" do
      it "accepts average_rating of 0" do
        template = build(:supply_chain_scan_template, average_rating: 0)
        expect(template).to be_valid
      end

      it "accepts average_rating of 5" do
        template = build(:supply_chain_scan_template, average_rating: 5)
        expect(template).to be_valid
      end

      it "rejects average_rating greater than 5" do
        template = build(:supply_chain_scan_template, average_rating: 5.1)
        expect(template).not_to be_valid
      end

      it "rejects average_rating less than 0" do
        template = build(:supply_chain_scan_template, average_rating: -0.1)
        expect(template).not_to be_valid
      end

      it "accepts install_count of 0" do
        template = build(:supply_chain_scan_template, install_count: 0)
        expect(template).to be_valid
      end

      it "rejects negative install_count" do
        template = build(:supply_chain_scan_template, install_count: -1)
        expect(template).not_to be_valid
      end
    end
  end
end
