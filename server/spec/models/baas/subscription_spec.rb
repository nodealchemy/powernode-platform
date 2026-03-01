# frozen_string_literal: true

require "rails_helper"

RSpec.describe BaaS::Subscription, type: :model do
  let(:account) { create(:account) }
  let(:tenant) { create(:baas_tenant, account: account) }
  let(:customer) { create(:baas_customer, baas_tenant: tenant) }

  describe "associations" do
    it { is_expected.to belong_to(:baas_tenant).class_name("BaaS::Tenant") }
    it { is_expected.to belong_to(:baas_customer).class_name("BaaS::Customer") }
    it { is_expected.to have_many(:invoices).class_name("BaaS::Invoice").dependent(:nullify) }
  end

  describe "validations" do
    subject { build(:baas_subscription, baas_tenant: tenant, baas_customer: customer) }

    it { is_expected.to validate_presence_of(:external_id) }
    it { is_expected.to validate_presence_of(:plan_external_id) }
    it { is_expected.to validate_presence_of(:status) }
    it { is_expected.to validate_presence_of(:billing_interval) }
    it { is_expected.to validate_uniqueness_of(:external_id).scoped_to(:baas_tenant_id) }
    it { is_expected.to validate_inclusion_of(:status).in_array(%w[incomplete incomplete_expired trialing active past_due canceled unpaid paused]) }
    it { is_expected.to validate_inclusion_of(:billing_interval).in_array(%w[day week month year]) }
    it { is_expected.to validate_numericality_of(:billing_interval_count).is_greater_than(0) }
    it { is_expected.to validate_numericality_of(:quantity).is_greater_than(0) }
  end

  describe "#active?" do
    it "returns true when status is active" do
      subscription = build(:baas_subscription, status: "active")
      expect(subscription.active?).to be true
    end
  end

  describe "#trialing?" do
    it "returns true when status is trialing" do
      subscription = build(:baas_subscription, status: "trialing")
      expect(subscription.trialing?).to be true
    end
  end

  describe "#canceled?" do
    it "returns true when status is canceled" do
      subscription = build(:baas_subscription, status: "canceled")
      expect(subscription.canceled?).to be true
    end
  end

  describe "#in_trial?" do
    it "returns true when trialing with future trial_end" do
      subscription = build(:baas_subscription, status: "trialing", trial_end: 7.days.from_now)
      expect(subscription.in_trial?).to be true
    end

    it "returns false when trial has ended" do
      subscription = build(:baas_subscription, status: "trialing", trial_end: 1.day.ago)
      expect(subscription.in_trial?).to be false
    end
  end

  describe "#trial_days_remaining" do
    it "returns days remaining in trial" do
      subscription = build(:baas_subscription, status: "trialing", trial_end: 7.days.from_now)
      expect(subscription.trial_days_remaining).to eq(7)
    end

    it "returns 0 when not in trial" do
      subscription = build(:baas_subscription, status: "active")
      expect(subscription.trial_days_remaining).to eq(0)
    end
  end

  describe "#cancel!" do
    let(:subscription) { create(:baas_subscription, baas_tenant: tenant, baas_customer: customer, status: "active") }

    it "cancels at period end by default" do
      subscription.cancel!(reason: "customer_request")
      expect(subscription.cancel_at_period_end).to be true
      expect(subscription.cancellation_reason).to eq("customer_request")
    end

    it "cancels immediately when at_period_end is false" do
      subscription.cancel!(reason: "customer_request", at_period_end: false)
      expect(subscription.status).to eq("canceled")
      expect(subscription.canceled_at).to be_present
      expect(subscription.ended_at).to be_present
    end
  end

  describe "#reactivate!" do
    let(:subscription) do
      create(:baas_subscription,
        baas_tenant: tenant,
        baas_customer: customer,
        status: "active",
        cancel_at_period_end: true
      )
    end

    it "removes pending cancellation" do
      subscription.reactivate!
      expect(subscription.cancel_at_period_end).to be false
      expect(subscription.cancellation_reason).to be_nil
    end
  end

  describe "#pause!" do
    let(:subscription) { create(:baas_subscription, baas_tenant: tenant, baas_customer: customer, status: "active") }

    it "sets status to paused" do
      subscription.pause!
      expect(subscription.status).to eq("paused")
    end

    it "returns false when not active" do
      subscription.update!(status: "canceled")
      expect(subscription.pause!).to be false
    end
  end

  describe "#resume!" do
    let(:subscription) { create(:baas_subscription, baas_tenant: tenant, baas_customer: customer, status: "paused") }

    it "sets status to active" do
      subscription.resume!
      expect(subscription.status).to eq("active")
    end

    it "returns false when not paused" do
      subscription.update!(status: "active")
      expect(subscription.resume!).to be false
    end
  end

  describe "#monthly_amount" do
    it "returns unit_amount for monthly billing" do
      subscription = build(:baas_subscription, billing_interval: "month", billing_interval_count: 1, unit_amount: 9900)
      expect(subscription.monthly_amount).to eq(9900)
    end

    it "calculates monthly amount for yearly billing" do
      subscription = build(:baas_subscription, billing_interval: "year", billing_interval_count: 1, unit_amount: 99000)
      expect(subscription.monthly_amount).to eq(8250) # 99000 / 12
    end
  end

  describe "#summary" do
    let(:subscription) { create(:baas_subscription, baas_tenant: tenant, baas_customer: customer) }

    it "returns summary hash" do
      summary = subscription.summary
      expect(summary).to include(:id, :external_id, :customer_id, :plan_id, :status)
    end
  end

  describe "scopes" do
    let!(:active_sub) { create(:baas_subscription, baas_tenant: tenant, baas_customer: customer, status: "active") }
    let!(:canceled_sub) { create(:baas_subscription, baas_tenant: tenant, baas_customer: create(:baas_customer, baas_tenant: tenant), status: "canceled") }
    let!(:trial_sub) { create(:baas_subscription, baas_tenant: tenant, baas_customer: create(:baas_customer, baas_tenant: tenant), status: "trialing") }

    it "filters active subscriptions" do
      expect(described_class.active).to include(active_sub)
      expect(described_class.active).not_to include(canceled_sub)
    end

    it "filters trialing subscriptions" do
      expect(described_class.trialing).to include(trial_sub)
    end
  end

  describe "callbacks" do
    it "increments tenant subscription count on create" do
      expect { create(:baas_subscription, baas_tenant: tenant, baas_customer: customer) }
        .to change { tenant.reload.total_subscriptions }.by(1)
    end
  end
end
