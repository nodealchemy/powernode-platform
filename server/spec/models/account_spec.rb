require 'rails_helper'

RSpec.describe Account, type: :model do
  let(:account) { build(:account) }

  describe "associations" do
    it { should have_many(:users).dependent(:destroy) }
    it { should have_one(:subscription).dependent(:destroy) }
    it { should have_many(:invitations).dependent(:destroy) }
    it { should have_many(:account_delegations).dependent(:destroy) }
    it { should have_many(:audit_logs).dependent(:destroy) }
    it { should have_many(:payment_methods).dependent(:destroy) }
    it { should have_many(:webhook_events).dependent(:destroy) }
    it { should have_many(:revenue_snapshots).dependent(:destroy) }
    it { should have_many(:invoices).through(:subscription) }
    it { should have_many(:payments).through(:invoices) }
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
      subscription = create(:subscription, account: account, status: "trialing")
      allow(subscription).to receive(:on_trial?).and_return(true)

      expect(account.on_trial?).to be true
    end

    it "returns false when no subscription exists" do
      expect(account.on_trial?).to be false
    end
  end
end
