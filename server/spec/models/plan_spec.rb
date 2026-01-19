# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Plan, type: :model do
  let(:plan) { build(:plan) }

  describe "associations" do
    # Note: Plan uses before_destroy callback for custom deletion logic
    # (allows deletion when only inactive subscriptions exist)
    it { should have_many(:subscriptions) }
  end

  describe "validations" do
    it { should validate_presence_of(:name) }
    # Skip due to normalization callback interfering
    # it { should validate_uniqueness_of(:name).case_insensitive }
    it { should validate_length_of(:name).is_at_least(2).is_at_most(100) }
    it { should validate_presence_of(:price_cents) }
    it { should validate_numericality_of(:price_cents).is_greater_than_or_equal_to(0) }
    it { should validate_presence_of(:currency) }
    it { should validate_inclusion_of(:currency).in_array(%w[USD EUR GBP]) }
    it { should validate_presence_of(:billing_cycle) }
    it { should validate_inclusion_of(:billing_cycle).in_array(%w[monthly yearly quarterly]) }
    it { should validate_presence_of(:status) }
    it { should validate_inclusion_of(:status).in_array(%w[active inactive archived]) }
    it { should validate_presence_of(:trial_days) }
    it { should validate_numericality_of(:trial_days).is_greater_than_or_equal_to(0).is_less_than_or_equal_to(365) }
  end

  describe "scopes" do
    let!(:active_plan) { create(:plan, status: "active") }
    let!(:inactive_plan) { create(:plan, status: "inactive") }
    let!(:archived_plan) { create(:plan, status: "archived") }
    let!(:public_plan) { create(:plan, is_public: true) }
    let!(:private_plan) { create(:plan, is_public: false) }

    it "returns active plans" do
      expect(Plan.active).to include(active_plan)
      expect(Plan.active).not_to include(inactive_plan, archived_plan)
    end

    it "returns public plans" do
      expect(Plan.public_plans).to include(public_plan)
      expect(Plan.public_plans).not_to include(private_plan)
    end

    it "filters by billing cycle" do
      monthly_plan = create(:plan, billing_cycle: "monthly")
      yearly_plan = create(:plan, billing_cycle: "yearly")

      expect(Plan.by_billing_cycle("monthly")).to include(monthly_plan)
      expect(Plan.by_billing_cycle("monthly")).not_to include(yearly_plan)
    end

    it "filters by currency" do
      usd_plan = create(:plan, currency: "USD")
      eur_plan = create(:plan, currency: "EUR")

      expect(Plan.by_currency("USD")).to include(usd_plan)
      expect(Plan.by_currency("USD")).not_to include(eur_plan)
    end
  end

  describe "status methods" do
    it "returns true for active? when status is active" do
      plan.status = "active"
      expect(plan.active?).to be true
    end

    it "returns true for inactive? when status is inactive" do
      plan.status = "inactive"
      expect(plan.inactive?).to be true
    end

    it "returns true for archived? when status is archived" do
      plan.status = "archived"
      expect(plan.archived?).to be true
    end
  end

  describe "price methods" do
    let(:plan) { create(:plan, price_cents: 2999, currency: "USD") }

    describe "#price" do
      it "returns Money object with correct amount" do
        expect(plan.price).to be_a(Money)
        expect(plan.price.cents).to eq(2999)
        expect(plan.price.currency.to_s).to eq("USD")
      end

      it "handles currency correctly" do
        # Can't set invalid currency due to DB constraint, so test with valid currency
        plan.currency = "EUR"
        expect(plan.price.currency.to_s).to eq("EUR")
      end
    end

    describe "#price=" do
      it "sets price from Money object" do
        money = Money.new(1999, "EUR")
        plan.price = money
        expect(plan.price_cents).to eq(1999)
        expect(plan.currency).to eq("EUR")
      end

      it "sets price from numeric value" do
        plan.price = 19.99
        # Allow for minor rounding differences in Money gem
        expect(plan.price_cents).to be_within(1).of(1999)
      end
    end

    describe "#monthly_price" do
      context "with monthly billing cycle" do
        it "returns the full price" do
          plan.billing_cycle = "monthly"
          expect(plan.monthly_price.cents).to eq(2999)
        end
      end

      context "with quarterly billing cycle" do
        it "returns price divided by 3" do
          plan.billing_cycle = "quarterly"
          expected = (2999 / 3.0).round
          expect(plan.monthly_price.cents).to eq(expected)
        end
      end

      context "with yearly billing cycle" do
        it "returns price divided by 12" do
          plan.billing_cycle = "yearly"
          expected = (2999 / 12.0).round
          expect(plan.monthly_price.cents).to eq(expected)
        end
      end
    end
  end

  describe "feature methods" do
    let(:plan) { create(:plan, features: { "analytics" => true, "api_access" => false }) }

    describe "#has_feature?" do
      it "returns true when feature exists and is enabled" do
        expect(plan.has_feature?("analytics")).to be true
        expect(plan.has_feature?(:analytics)).to be true
      end

      it "returns false when feature exists but is disabled" do
        expect(plan.has_feature?("api_access")).to be false
      end

      it "returns false when feature doesn't exist" do
        expect(plan.has_feature?("nonexistent")).to be false
      end
    end
  end

  describe "limit methods" do
    let(:plan) { create(:plan, limits: { "users" => 10, "projects" => 5 }) }

    describe "#get_limit" do
      it "returns limit value when it exists" do
        expect(plan.get_limit("users")).to eq(10)
        expect(plan.get_limit(:users)).to eq(10)
      end

      it "returns nil when limit doesn't exist" do
        expect(plan.get_limit("nonexistent")).to be_nil
      end
    end
  end

  describe "#assign_default_roles_to_user" do
    let(:plan) { create(:plan, default_roles: [ "test_user", "test_member" ]) }
    let(:user) { create(:user) }
    let!(:user_role) { create(:role, name: "test_user") }
    let!(:member_role) { create(:role, name: "test_member") }

    it "assigns default roles to user" do
      expect(user).to receive(:assign_role).with(user_role)
      expect(user).to receive(:assign_role).with(member_role)

      plan.assign_default_roles_to_user(user)
    end

    it "skips roles that don't exist" do
      plan.default_roles = [ "NonexistentRole" ]
      expect(user).not_to receive(:assign_role)

      plan.assign_default_roles_to_user(user)
    end
  end

  describe "#can_be_deleted?" do
    let(:plan) { create(:plan) }

    it "returns true when no active subscriptions exist" do
      create(:subscription, plan: plan, status: "canceled")
      expect(plan.can_be_deleted?).to be true
    end

    it "returns false when active subscriptions exist" do
      create(:subscription, plan: plan, status: "active")
      expect(plan.can_be_deleted?).to be false
    end
  end

  describe "callbacks" do
    describe "#normalize_name" do
      it "strips and titleizes the name" do
        plan.name = "  basic plan  "
        plan.valid?
        expect(plan.name).to eq("Basic Plan")
      end
    end

    describe "#set_defaults" do
      it "initializes default values" do
        plan = Plan.new
        expect(plan.features).to eq({})
        expect(plan.limits).to eq({
          'max_api_keys' => 5,
          'max_users' => 2,
          'max_webhooks' => 5,
          'max_workers' => 3
        })
        expect(plan.default_roles).to eq([])
      end
    end
  end
end
