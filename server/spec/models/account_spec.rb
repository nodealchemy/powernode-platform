# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Account, type: :model do
  let(:account) { build(:account) }

  describe "associations" do
    it { should have_many(:users).dependent(:destroy) }
    it { should have_many(:invitations).dependent(:destroy) }
    it { should have_many(:account_delegations).dependent(:destroy) }
    it { should have_many(:audit_logs).dependent(:destroy) }
    it { should have_many(:webhook_events).dependent(:destroy) }
    # Billing/revenue associations (subscription, payment_methods, invoices,
    # payments, revenue_snapshots) are added by the business extension's
    # account decorator and are covered by the business extension's suite.
  end

  describe "validations" do
    subject { build(:account) }

    it { should validate_presence_of(:name) }
    it { should validate_length_of(:name).is_at_least(2).is_at_most(100) }
    it { should validate_presence_of(:status) }
    it { should validate_inclusion_of(:status).in_array(%w[active suspended cancelled]) }

    describe "subdomain validation" do
      subject { build(:account) }

      it { should allow_value("").for(:subdomain) }
      it { should allow_value("valid-subdomain").for(:subdomain) }
      it { should allow_value("test123").for(:subdomain) }
      it { should allow_value("Invalid-Subdomain").for(:subdomain) }
      it { should_not allow_value("sub_domain").for(:subdomain) }
      it { should_not allow_value("ab").for(:subdomain) }
      it { should validate_length_of(:subdomain).is_at_least(3).is_at_most(30) }
    end
  end

  describe "scopes" do
    let!(:active_account) { create(:account, status: "active") }
    let!(:suspended_account) { create(:account, status: "suspended") }
    let!(:cancelled_account) { create(:account, status: "cancelled") }

    it "returns active accounts" do
      expect(Account.active).to include(active_account)
      expect(Account.active).not_to include(suspended_account, cancelled_account)
    end

    it "returns suspended accounts" do
      expect(Account.suspended).to include(suspended_account)
      expect(Account.suspended).not_to include(active_account, cancelled_account)
    end

    it "returns cancelled accounts" do
      expect(Account.cancelled).to include(cancelled_account)
      expect(Account.cancelled).not_to include(active_account, suspended_account)
    end
  end

  describe "status methods" do
    it "returns true for active? when status is active" do
      account.status = "active"
      expect(account.active?).to be true
    end

    it "returns false for active? when status is not active" do
      account.status = "suspended"
      expect(account.active?).to be false
    end

    it "returns true for suspended? when status is suspended" do
      account.status = "suspended"
      expect(account.suspended?).to be true
    end

    it "returns true for cancelled? when status is cancelled" do
      account.status = "cancelled"
      expect(account.cancelled?).to be true
    end
  end

  describe "callbacks" do
    describe "#normalize_subdomain" do
      it "normalizes subdomain to lowercase" do
        account.subdomain = "TestAccount"
        account.valid?
        expect(account.subdomain).to eq("testaccount")
      end

      it "strips whitespace from subdomain" do
        account.subdomain = "  test-account  "
        account.valid?
        expect(account.subdomain).to eq("test-account")
      end

      it "normalizes uppercase letters to lowercase in subdomain" do
        account.subdomain = "Test-Account"
        account.valid?
        expect(account.subdomain).to eq("test-account")
      end
    end

    describe "#set_defaults" do
      it "initializes settings as empty hash" do
        account = Account.new
        expect(account.settings).to eq({})
      end
    end
  end

  describe "#owner" do
    it "returns the owner user" do
      account = create(:account)
      owner = create(:user, :owner, account: account)

      expect(account.owner).to eq(owner)
    end
  end

  describe "#current_subscription" do
    let(:account) { create(:account) }

    it "returns the subscription" do
      skip "requires business billing models" unless defined?(Billing::Subscription)
      subscription = create(:subscription, account: account, status: "active")

      expect(account.current_subscription).to eq(subscription)
    end

    it "returns nil when no subscription exists" do
      expect(account.current_subscription).to be_nil
    end
  end

  describe "#has_active_subscription?" do
    let(:account) { create(:account) }

    it "returns true when account has active subscription" do
      skip "requires business billing models" unless defined?(Billing::Subscription)
      create(:subscription, account: account, status: "active")

      expect(account.has_active_subscription?).to be true
    end

    it "returns false when account has no active subscription" do
      expect(account.has_active_subscription?).to be false
    end
  end

  describe "#subscription_status" do
    let(:account) { create(:account) }

    it "returns subscription status when subscription exists" do
      skip "requires business billing models" unless defined?(Billing::Subscription)
      create(:subscription, account: account, status: "active")

      expect(account.subscription_status).to eq("active")
    end

    it "returns 'none' when no subscription exists" do
      expect(account.subscription_status).to eq("none")
    end
  end

  describe "#on_trial?" do
    let(:account) { create(:account) }

    it "returns true when subscription is on trial" do
      skip "requires business billing models" unless defined?(Billing::Subscription)
      subscription = create(:subscription, account: account, status: "trialing")
      allow(subscription).to receive(:on_trial?).and_return(true)

      expect(account.on_trial?).to be true
    end

    it "returns false when no subscription exists" do
      expect(account.on_trial?).to be false
    end
  end

  # IMP-94728a788498: the raw account-wide default-network setting for
  # provisioning. Deliberately unclassified — bucketing (opt-out sentinel,
  # fail-loud) is PlanComposerService's single-copy decision.
  describe "#default_sdwan_network_setting" do
    let(:account) { create(:account) }

    it "reads the string key from settings" do
      account.update!(settings: { "default_sdwan_network_id" => "net-1" })
      expect(account.default_sdwan_network_setting).to eq("net-1")
    end

    it "tolerates an in-memory symbol key" do
      account.settings = { default_sdwan_network_id: "net-2" }
      expect(account.default_sdwan_network_setting).to eq("net-2")
    end

    it "is nil when unset or when settings is not a hash" do
      expect(account.default_sdwan_network_setting).to be_nil
      account.settings = nil
      expect(account.default_sdwan_network_setting).to be_nil
    end
  end

  describe "#destroy! (account teardown)" do
    it "removes an account with its default environment and an agent created by one of its users" do
      account = create(:account)
      Ai::Environment.ensure_defaults_for!(account)
      agent = create(:ai_agent, account: account)
      creator = agent.creator
      project = create(:ai_project, account: account, environment: Ai::Environment.default_for(account))
      env_ids = account.environments.pluck(:id)
      expect(env_ids).not_to be_empty

      expect { account.destroy! }.not_to raise_error

      expect(Account.exists?(account.id)).to be false
      expect(Ai::Environment.where(id: env_ids)).to be_empty
      expect(Ai::Agent.exists?(agent.id)).to be false
      expect(Ai::Project.exists?(project.id)).to be false
      expect(User.exists?(creator.id)).to be false
    end

    # Every account-owned row that references one of the account's users via an
    # FK without ON DELETE CASCADE/NULLIFY must be gone before the user is.
    # [factory, user attribute]
    USER_REFERENCING_ROWS = [
      [:ai_conversation, :user],
      [:ai_agent_execution, :user],
      [:api_key, :created_by],
      [:ai_knowledge_base, :created_by],
      [:ai_mission, :created_by],
      [:ai_approval_chain, :created_by],
      [:ai_compliance_policy, :created_by],
      [:ai_sandbox, :created_by],
      [:ai_team_template, :created_by],
      [:ai_devops_template, :created_by],
      [:ai_mock_response, :created_by],
      [:ai_data_connector, :created_by],
      [:ai_ab_test, :created_by],
      [:ai_performance_benchmark, :created_by]
    ].freeze

    it "removes the only default provider credentials (their guards yield to account teardown)" do
      account = create(:account)
      git_cred = create(:git_provider_credential, account: account, is_default: true)
      ai_cred = create(:ai_provider_credential, account: account, is_default: true)

      expect { account.destroy! }.not_to raise_error

      expect(Devops::GitProviderCredential.exists?(git_cred.id)).to be false
      expect(Ai::ProviderCredential.exists?(ai_cred.id)).to be false
    end

    it "still protects the only default credential outside account teardown" do
      account = create(:account)
      git_cred = create(:git_provider_credential, account: account, is_default: true)

      expect(git_cred.destroy).to be false
      expect(Devops::GitProviderCredential.exists?(git_cred.id)).to be true
    end

    it "removes account-owned rows that reference the account's users" do
      account = create(:account)
      user = create(:user, account: account)
      rows = USER_REFERENCING_ROWS.map do |factory, attr|
        create(factory, account: account, attr => user)
      end

      expect { account.destroy! }.not_to raise_error

      rows.each { |row| expect(row.class.exists?(row.id)).to be(false), "#{row.class} survived" }
      expect(User.exists?(user.id)).to be false
    end
  end
end
