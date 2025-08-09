require 'rails_helper'

RSpec.describe Subscription, type: :model do
  let(:subscription) { build(:subscription) }

  describe "associations" do
    it { should belong_to(:account) }
    it { should belong_to(:plan) }
    it { should have_many(:invoices).dependent(:destroy) }
    it { should have_many(:payments).through(:invoices) }
  end

  describe "validations" do
    it { should validate_presence_of(:quantity) }
    it { should validate_numericality_of(:quantity).is_greater_than(0) }

    describe "stripe_subscription_id uniqueness" do
      it "validates uniqueness when present" do
        create(:subscription, stripe_subscription_id: "sub_123")
        duplicate = build(:subscription, stripe_subscription_id: "sub_123")

        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:stripe_subscription_id]).to include("has already been taken")
      end

      it "allows nil values" do
        create(:subscription, stripe_subscription_id: nil)
        another_nil = build(:subscription, stripe_subscription_id: nil)

        expect(another_nil).to be_valid
      end
    end

    describe "paypal_subscription_id uniqueness" do
      it "validates uniqueness when present" do
        create(:subscription, paypal_subscription_id: "I-123")
        duplicate = build(:subscription, paypal_subscription_id: "I-123")

        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:paypal_subscription_id]).to include("has already been taken")
      end

      it "allows nil values" do
        create(:subscription, paypal_subscription_id: nil)
        another_nil = build(:subscription, paypal_subscription_id: nil)

        expect(another_nil).to be_valid
      end
    end

    describe "account uniqueness" do
      it "validates that each account can only have one subscription" do
        account = create(:account)
        create(:subscription, account: account)

        duplicate = build(:subscription, account: account)

        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:account]).to include("can only have one subscription")
      end

      it "allows different accounts to have subscriptions" do
        account1 = create(:account)
        account2 = create(:account)

        subscription1 = create(:subscription, account: account1)
        subscription2 = build(:subscription, account: account2)

        expect(subscription1).to be_valid
        expect(subscription2).to be_valid
      end
    end
  end

  describe "scopes" do
    let!(:trialing_sub) { create(:subscription, status: "trialing") }
    let!(:active_sub) { create(:subscription, status: "active") }
    let!(:canceled_sub) { create(:subscription, status: "canceled") }
    let!(:past_due_sub) { create(:subscription, status: "past_due") }
    let!(:unpaid_sub) { create(:subscription, status: "unpaid") }
    let!(:paused_sub) { create(:subscription, status: "paused") }

    describe ".active" do
      it "returns trialing and active subscriptions" do
        expect(Subscription.active).to include(trialing_sub, active_sub)
        expect(Subscription.active).not_to include(canceled_sub, past_due_sub, unpaid_sub)
      end
    end

    describe ".inactive" do
      it "returns canceled, unpaid, and incomplete_expired subscriptions" do
        incomplete_expired = create(:subscription, status: "incomplete_expired")

        expect(Subscription.inactive).to include(canceled_sub, unpaid_sub, incomplete_expired)
        expect(Subscription.inactive).not_to include(trialing_sub, active_sub, past_due_sub)
      end
    end

    describe ".past_due" do
      it "returns only past_due subscriptions" do
        expect(Subscription.past_due).to include(past_due_sub)
        expect(Subscription.past_due).not_to include(trialing_sub, active_sub, canceled_sub)
      end
    end

    describe ".trialing" do
      it "returns only trialing subscriptions" do
        expect(Subscription.trialing).to include(trialing_sub)
        expect(Subscription.trialing).not_to include(active_sub, canceled_sub, past_due_sub)
      end
    end

    describe ".expiring_soon" do
      it "returns subscriptions expiring within 7 days" do
        # Create plan without trial to avoid trial_period callback overriding current_period_end
        plan_no_trial = create(:plan, trial_days: 0)

        # Create subscription that expires in 5 days (well within 7-day window)
        expiring_soon = create(:subscription, plan: plan_no_trial, current_period_end: 5.days.from_now)
        # Create subscription that expires in 10 days (outside 7-day window)
        not_expiring = create(:subscription, plan: plan_no_trial, current_period_end: 10.days.from_now)

        expect(Subscription.expiring_soon).to include(expiring_soon)
        expect(Subscription.expiring_soon).not_to include(not_expiring)
      end
    end

    describe ".trial_ending_soon" do
      it "returns subscriptions with trials ending within 3 days" do
        trial_ending = create(:subscription, trial_end: 2.days.from_now)
        trial_not_ending = create(:subscription, trial_end: 5.days.from_now)

        expect(Subscription.trial_ending_soon).to include(trial_ending)
        expect(Subscription.trial_ending_soon).not_to include(trial_not_ending)
      end
    end
  end

  describe "callbacks" do
    describe "#set_trial_period" do
      let(:plan_with_trial) { create(:plan, trial_days: 14) }
      let(:plan_without_trial) { create(:plan, trial_days: 0) }

      it "sets trial period when plan has trial days" do
        subscription = build(:subscription, plan: plan_with_trial, trial_end: nil)

        start_time = Time.current
        subscription.save!

        expect(subscription.trial_end).to be_within(2.seconds).of(start_time + 14.days)
        expect(subscription.current_period_start).to be_within(2.seconds).of(start_time)
        expect(subscription.current_period_end).to eq(subscription.trial_end)
      end

      it "does not set trial period when plan has no trial days" do
        subscription = build(:subscription, plan: plan_without_trial)
        subscription.save!

        expect(subscription.trial_end).to be_nil
      end

      it "does not override existing trial_end" do
        existing_trial_end = 30.days.from_now
        subscription = build(:subscription, plan: plan_with_trial, trial_end: existing_trial_end)
        subscription.save!

        expect(subscription.trial_end).to be_within(1.second).of(existing_trial_end)
      end
    end

    describe "#set_defaults" do
      it "initializes metadata as empty hash" do
        subscription = Subscription.new
        expect(subscription.metadata).to eq({})
      end
    end
  end

  describe "state machine" do
    describe "initial state" do
      it "starts in trialing state" do
        # Create subscription without status override to test AASM initial state
        subscription = Subscription.new(account: build(:account), plan: build(:plan), quantity: 1)
        expect(subscription.status).to eq("trialing")
        expect(subscription).to be_trialing
      end
    end

    describe "#activate" do
      it "transitions from trialing to active" do
        subscription = create(:subscription, status: "trialing")

        expect { subscription.activate! }.to change { subscription.status }.from("trialing").to("active")
      end

      it "transitions from past_due to active" do
        subscription = create(:subscription, status: "past_due")

        expect { subscription.activate! }.to change { subscription.status }.from("past_due").to("active")
      end

      it "transitions from paused to active" do
        subscription = create(:subscription, status: "paused")

        expect { subscription.activate! }.to change { subscription.status }.from("paused").to("active")
      end

      it "calls update_period_dates after activation" do
        subscription = create(:subscription, status: "trialing")
        allow(subscription).to receive(:update_period_dates)

        subscription.activate!

        expect(subscription).to have_received(:update_period_dates)
      end
    end

    describe "#mark_past_due" do
      it "transitions from active to past_due" do
        subscription = create(:subscription, status: "active")

        expect { subscription.mark_past_due! }.to change { subscription.status }.from("active").to("past_due")
      end

      it "transitions from trialing to past_due" do
        subscription = create(:subscription, status: "trialing")

        expect { subscription.mark_past_due! }.to change { subscription.status }.from("trialing").to("past_due")
      end
    end

    describe "#cancel" do
      it "transitions from active to canceled" do
        subscription = create(:subscription, status: "active")

        expect { subscription.cancel! }.to change { subscription.status }.from("active").to("canceled")
      end

      it "sets canceled_at timestamp" do
        subscription = create(:subscription, status: "active")

        start_time = Time.current
        subscription.cancel!
        expect(subscription.canceled_at).to be_within(2.seconds).of(start_time)
      end

      it "sets ended_at when not already present" do
        subscription = create(:subscription, status: "active", ended_at: nil)

        start_time = Time.current
        subscription.cancel!
        expect(subscription.ended_at).to be_within(2.seconds).of(start_time)
      end

      it "does not override existing ended_at" do
        existing_end = 1.day.ago
        subscription = create(:subscription, status: "active", ended_at: existing_end)

        subscription.cancel!
        expect(subscription.ended_at).to be_within(1.second).of(existing_end)
      end
    end

    describe "#mark_unpaid" do
      it "transitions from active to unpaid" do
        subscription = create(:subscription, status: "active")

        expect { subscription.mark_unpaid! }.to change { subscription.status }.from("active").to("unpaid")
      end

      it "transitions from past_due to unpaid" do
        subscription = create(:subscription, status: "past_due")

        expect { subscription.mark_unpaid! }.to change { subscription.status }.from("past_due").to("unpaid")
      end
    end

    describe "#pause and #resume" do
      it "pauses active subscription" do
        subscription = create(:subscription, status: "active")

        expect { subscription.pause! }.to change { subscription.status }.from("active").to("paused")
      end

      it "resumes paused subscription" do
        subscription = create(:subscription, status: "paused")

        expect { subscription.resume! }.to change { subscription.status }.from("paused").to("active")
      end
    end

    describe "#expire" do
      it "transitions from incomplete to incomplete_expired" do
        subscription = create(:subscription, status: "incomplete")

        expect { subscription.expire! }.to change { subscription.status }.from("incomplete").to("incomplete_expired")
      end

      it "sets ended_at timestamp" do
        subscription = create(:subscription, status: "incomplete")

        start_time = Time.current
        subscription.expire!
        expect(subscription.ended_at).to be_within(2.seconds).of(start_time)
      end
    end
  end

  describe "instance methods" do
    describe "#active?" do
      it "returns true for trialing subscriptions" do
        subscription = build(:subscription, status: "trialing")
        expect(subscription.active?).to be true
      end

      it "returns true for active subscriptions" do
        subscription = build(:subscription, status: "active")
        expect(subscription.active?).to be true
      end

      it "returns false for other statuses" do
        %w[canceled past_due unpaid paused].each do |status|
          subscription = build(:subscription, status: status)
          expect(subscription.active?).to be false
        end
      end
    end

    describe "#on_trial?" do
      it "returns true when trialing with future trial_end" do
        subscription = build(:subscription, status: "trialing", trial_end: 1.week.from_now)
        expect(subscription.on_trial?).to be true
      end

      it "returns false when trialing with past trial_end" do
        subscription = build(:subscription, status: "trialing", trial_end: 1.day.ago)
        expect(subscription.on_trial?).to be false
      end

      it "returns false when not trialing" do
        subscription = build(:subscription, status: "active", trial_end: 1.week.from_now)
        expect(subscription.on_trial?).to be false
      end

      it "returns false when trial_end is nil" do
        subscription = build(:subscription, status: "trialing", trial_end: nil)
        expect(subscription.on_trial?).to be false
      end
    end

    describe "#trial_ended?" do
      it "returns true when trial_end is in the past" do
        subscription = build(:subscription, trial_end: 1.day.ago)
        expect(subscription.trial_ended?).to be true
      end

      it "returns false when trial_end is in the future" do
        subscription = build(:subscription, trial_end: 1.day.from_now)
        expect(subscription.trial_ended?).to be false
      end

      it "returns false when trial_end is nil" do
        subscription = build(:subscription, trial_end: nil)
        expect(subscription.trial_ended?).to be false
      end
    end

    describe "#days_until_trial_ends" do
      it "calculates days remaining in trial" do
        subscription = build(:subscription, status: "trialing", trial_end: 5.days.from_now)
        expect(subscription.days_until_trial_ends).to eq(5)
      end

      it "returns 0 when not on trial" do
        subscription = build(:subscription, status: "active")
        expect(subscription.days_until_trial_ends).to eq(0)
      end
    end

    describe "#days_until_period_ends" do
      it "calculates days until period ends" do
        subscription = build(:subscription, current_period_end: 10.days.from_now)
        expect(subscription.days_until_period_ends).to eq(10)
      end

      it "returns 0 when current_period_end is nil" do
        subscription = build(:subscription, current_period_end: nil)
        expect(subscription.days_until_period_ends).to eq(0)
      end
    end

    describe "#total_price" do
      it "calculates total price based on quantity" do
        plan = create(:plan, price_cents: 2000)
        subscription = build(:subscription, plan: plan, quantity: 3)

        expect(subscription.total_price).to eq(6000)
      end
    end

    describe "#next_billing_date" do
      it "returns trial_end when on trial" do
        trial_end = 1.week.from_now
        subscription = build(:subscription,
          status: "trialing",
          trial_end: trial_end,
          current_period_end: 1.month.from_now
        )

        expect(subscription.next_billing_date).to be_within(1.second).of(trial_end)
      end

      it "returns current_period_end when not on trial" do
        period_end = 1.month.from_now
        subscription = build(:subscription,
          status: "active",
          trial_end: 1.day.ago,
          current_period_end: period_end
        )

        expect(subscription.next_billing_date).to be_within(1.second).of(period_end)
      end
    end

    describe "#can_be_canceled?" do
      it "returns true for cancelable statuses" do
        %w[trialing active past_due unpaid paused].each do |status|
          subscription = build(:subscription, status: status)
          expect(subscription.can_be_canceled?).to be true
        end
      end

      it "returns false for non-cancelable statuses" do
        %w[canceled incomplete_expired].each do |status|
          subscription = build(:subscription, status: status)
          expect(subscription.can_be_canceled?).to be false
        end
      end
    end

    describe "#using_stripe?" do
      it "returns true when stripe_subscription_id is present" do
        subscription = build(:subscription, stripe_subscription_id: "sub_123")
        expect(subscription.using_stripe?).to be true
      end

      it "returns false when stripe_subscription_id is nil" do
        subscription = build(:subscription, stripe_subscription_id: nil)
        expect(subscription.using_stripe?).to be false
      end
    end

    describe "#using_paypal?" do
      it "returns true when paypal_subscription_id is present" do
        subscription = build(:subscription, paypal_subscription_id: "I-123")
        expect(subscription.using_paypal?).to be true
      end

      it "returns false when paypal_subscription_id is nil" do
        subscription = build(:subscription, paypal_subscription_id: nil)
        expect(subscription.using_paypal?).to be false
      end
    end

    describe "#payment_provider" do
      it "returns 'stripe' when using Stripe" do
        subscription = build(:subscription, stripe_subscription_id: "sub_123")
        expect(subscription.payment_provider).to eq("stripe")
      end

      it "returns 'paypal' when using PayPal" do
        subscription = build(:subscription, paypal_subscription_id: "I-123")
        expect(subscription.payment_provider).to eq("paypal")
      end

      it "returns 'none' when using neither" do
        subscription = build(:subscription, stripe_subscription_id: nil, paypal_subscription_id: nil)
        expect(subscription.payment_provider).to eq("none")
      end

      it "prioritizes Stripe over PayPal" do
        subscription = build(:subscription,
          stripe_subscription_id: "sub_123",
          paypal_subscription_id: "I-123"
        )
        expect(subscription.payment_provider).to eq("stripe")
      end
    end
  end

  describe "private methods" do
    describe "#update_period_dates" do
      let(:monthly_plan) { create(:plan, billing_cycle: "monthly") }
      let(:quarterly_plan) { create(:plan, billing_cycle: "quarterly") }
      let(:yearly_plan) { create(:plan, billing_cycle: "yearly") }

      it "updates period dates for monthly billing" do
        subscription = create(:subscription, plan: monthly_plan, status: "trialing")

        start_time = Time.current
        subscription.send(:update_period_dates)

        expect(subscription.current_period_start).to be_within(2.seconds).of(start_time)
        expect(subscription.current_period_end).to be_within(2.seconds).of(start_time + 1.month)
      end

      it "updates period dates for quarterly billing" do
        subscription = create(:subscription, plan: quarterly_plan, status: "trialing")

        start_time = Time.current
        subscription.send(:update_period_dates)

        expect(subscription.current_period_start).to be_within(2.seconds).of(start_time)
        expect(subscription.current_period_end).to be_within(2.seconds).of(start_time + 3.months)
      end

      it "updates period dates for yearly billing" do
        subscription = create(:subscription, plan: yearly_plan, status: "trialing")

        start_time = Time.current
        subscription.send(:update_period_dates)

        expect(subscription.current_period_start).to be_within(2.seconds).of(start_time)
        expect(subscription.current_period_end).to be_within(2.seconds).of(start_time + 1.year)
      end
    end
  end

  describe "integration scenarios" do
    it "creates subscription with trial period from plan" do
      plan = create(:plan, trial_days: 7)
      account = create(:account)

      subscription = Subscription.create!(account: account, plan: plan, quantity: 1)

      expect(subscription).to be_persisted
      expect(subscription.status).to eq("trialing")
      expect(subscription.on_trial?).to be true
      expect(subscription.days_until_trial_ends).to eq(7)
    end

    it "handles subscription lifecycle transitions" do
      subscription = create(:subscription, status: "trialing")

      # Activate subscription
      subscription.activate!
      expect(subscription.status).to eq("active")

      # Mark past due
      subscription.mark_past_due!
      expect(subscription.status).to eq("past_due")

      # Reactivate
      subscription.activate!
      expect(subscription.status).to eq("active")

      # Pause and resume
      subscription.pause!
      expect(subscription.status).to eq("paused")

      subscription.resume!
      expect(subscription.status).to eq("active")

      # Cancel
      subscription.cancel!
      expect(subscription.status).to eq("canceled")
      expect(subscription.canceled_at).to be_present
    end

    it "manages payment provider associations" do
      stripe_subscription = create(:subscription, stripe_subscription_id: "sub_stripe123")
      paypal_subscription = create(:subscription, paypal_subscription_id: "I-paypal123")

      expect(stripe_subscription.payment_provider).to eq("stripe")
      expect(stripe_subscription.using_stripe?).to be true
      expect(stripe_subscription.using_paypal?).to be false

      expect(paypal_subscription.payment_provider).to eq("paypal")
      expect(paypal_subscription.using_paypal?).to be true
      expect(paypal_subscription.using_stripe?).to be false
    end
  end
end
