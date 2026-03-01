# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Billing::SubscriptionService, type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:old_plan) { create(:plan, :basic_plan, billing_cycle: "monthly") }
  let(:new_plan) { create(:plan, :pro_plan, billing_cycle: "monthly") }
  let(:subscription) { create(:subscription, account: account, plan: old_plan) }
  let(:service) { described_class.new(subscription) }

  describe "#calculate_actual_billing_period_days" do
    context "with monthly billing cycle" do
      it "returns 31 days for January" do
        result = service.calculate_actual_billing_period_days("monthly", Date.new(2024, 1, 1))
        expect(result).to eq(31)
      end

      it "returns 29 days for February in leap year (2024)" do
        result = service.calculate_actual_billing_period_days("monthly", Date.new(2024, 2, 1))
        expect(result).to eq(29)
      end

      it "returns 28 days for February in non-leap year (2023)" do
        result = service.calculate_actual_billing_period_days("monthly", Date.new(2023, 2, 1))
        expect(result).to eq(28)
      end

      it "returns 30 days for April" do
        result = service.calculate_actual_billing_period_days("monthly", Date.new(2024, 4, 1))
        expect(result).to eq(30)
      end

      it "returns 31 days for March" do
        result = service.calculate_actual_billing_period_days("monthly", Date.new(2024, 3, 1))
        expect(result).to eq(31)
      end

      it "handles mid-month start dates" do
        # Starting mid-January, one month later is mid-February
        result = service.calculate_actual_billing_period_days("monthly", Date.new(2024, 1, 15))
        expect(result).to eq(31) # Jan 15 to Feb 15 = 31 days
      end

      it "handles month-end boundaries correctly" do
        # Starting Jan 31, one month later handles Feb correctly
        result = service.calculate_actual_billing_period_days("monthly", Date.new(2024, 1, 31))
        # Jan 31 >> 1 = Feb 29 (2024 is leap year), so 29 days
        expect(result).to eq(29)
      end
    end

    context "with quarterly billing cycle" do
      it "returns 91 days for Q1 2024 (leap year: 31+29+31)" do
        result = service.calculate_actual_billing_period_days("quarterly", Date.new(2024, 1, 1))
        expect(result).to eq(91)
      end

      it "returns 90 days for Q1 2023 (non-leap year: 31+28+31)" do
        result = service.calculate_actual_billing_period_days("quarterly", Date.new(2023, 1, 1))
        expect(result).to eq(90)
      end

      it "returns 91 days for Q2 2024 (Apr 30 + May 31 + Jun 30)" do
        result = service.calculate_actual_billing_period_days("quarterly", Date.new(2024, 4, 1))
        expect(result).to eq(91)
      end

      it "returns 92 days for Q3 2024 (Jul 31 + Aug 31 + Sep 30)" do
        result = service.calculate_actual_billing_period_days("quarterly", Date.new(2024, 7, 1))
        expect(result).to eq(92)
      end

      it "returns 92 days for Q4 2024 (Oct 31 + Nov 30 + Dec 31)" do
        result = service.calculate_actual_billing_period_days("quarterly", Date.new(2024, 10, 1))
        expect(result).to eq(92)
      end
    end

    context "with yearly billing cycle" do
      it "returns 366 days for leap year 2024" do
        result = service.calculate_actual_billing_period_days("yearly", Date.new(2024, 1, 1))
        expect(result).to eq(366)
      end

      it "returns 365 days for non-leap year 2023" do
        result = service.calculate_actual_billing_period_days("yearly", Date.new(2023, 1, 1))
        expect(result).to eq(365)
      end

      it "returns 365 days for non-leap year 2025" do
        result = service.calculate_actual_billing_period_days("yearly", Date.new(2025, 1, 1))
        expect(result).to eq(365)
      end

      it "handles mid-year start dates spanning leap year boundary" do
        # From July 2023 to July 2024 (spans the leap day)
        result = service.calculate_actual_billing_period_days("yearly", Date.new(2023, 7, 1))
        expect(result).to eq(366) # Includes Feb 29, 2024
      end
    end

    context "with unknown billing cycle" do
      it "falls back to 30 days" do
        result = service.calculate_actual_billing_period_days("unknown", Date.new(2024, 1, 1))
        expect(result).to eq(30)
      end

      it "falls back to 30 days for nil" do
        result = service.calculate_actual_billing_period_days(nil, Date.new(2024, 1, 1))
        expect(result).to eq(30)
      end
    end

    context "with date string input" do
      it "handles ISO date string" do
        result = service.calculate_actual_billing_period_days("monthly", "2024-02-01")
        expect(result).to eq(29)
      end

      it "handles datetime objects" do
        result = service.calculate_actual_billing_period_days("monthly", Time.zone.parse("2024-02-01 10:00:00"))
        expect(result).to eq(29)
      end
    end
  end

  describe "#calculate_proration" do
    let(:old_plan) { create(:plan, price_cents: 1000, billing_cycle: "monthly") }
    let(:new_plan) { create(:plan, price_cents: 2000, billing_cycle: "monthly") }

    context "when upgrading plan mid-cycle" do
      it "calculates correct proration for upgrade" do
        # Freeze time to January 15, 2024
        travel_to Date.new(2024, 1, 15) do
          # Billing anchor is end of January (16 days remaining)
          result = service.calculate_proration(
            old_plan: old_plan,
            new_plan: new_plan,
            billing_cycle_anchor: Date.new(2024, 1, 31),
            current_period_start: Date.new(2024, 1, 1)
          )

          # January has 31 days, 16 days remaining (Jan 15 to Jan 31)
          expect(result[:days_remaining]).to eq(16)
          expect(result[:days_in_period]).to eq(31)
          expect(result[:proration_factor]).to be_within(0.0001).of(16.0 / 31.0)
          expect(result[:is_upgrade]).to be true

          # New plan prorated: 2000 * (16/31) = 1032.26
          # Old plan credit: 1000 * (16/31) = 516.13
          # Net: 1032.26 - 516.13 = 516.13
          expect(result[:proration_amount_cents]).to be_within(1).of(516)
          expect(result[:new_plan_prorated_cents]).to be_within(1).of(1032)
          expect(result[:old_plan_credit_cents]).to be_within(1).of(516)
        end
      end

      it "calculates correct proration for downgrade" do
        travel_to Date.new(2024, 1, 15) do
          result = service.calculate_proration(
            old_plan: new_plan,  # Swapped: old is expensive
            new_plan: old_plan,  # new is cheaper
            billing_cycle_anchor: Date.new(2024, 1, 31),
            current_period_start: Date.new(2024, 1, 1)
          )

          expect(result[:is_upgrade]).to be false
          # Net should be negative (credit to customer)
          expect(result[:proration_amount_cents]).to be < 0
        end
      end
    end

    context "with February leap year" do
      it "uses 29 days for February 2024 proration" do
        travel_to Date.new(2024, 2, 15) do
          result = service.calculate_proration(
            old_plan: old_plan,
            new_plan: new_plan,
            billing_cycle_anchor: Date.new(2024, 2, 29),
            current_period_start: Date.new(2024, 2, 1)
          )

          # February 2024 has 29 days, 14 days remaining
          expect(result[:days_in_period]).to eq(29)
          expect(result[:days_remaining]).to eq(14)
          expect(result[:proration_factor]).to be_within(0.0001).of(14.0 / 29.0)
        end
      end
    end

    context "with February non-leap year" do
      it "uses 28 days for February 2023 proration" do
        travel_to Date.new(2023, 2, 14) do
          result = service.calculate_proration(
            old_plan: old_plan,
            new_plan: new_plan,
            billing_cycle_anchor: Date.new(2023, 2, 28),
            current_period_start: Date.new(2023, 2, 1)
          )

          # February 2023 has 28 days, 14 days remaining
          expect(result[:days_in_period]).to eq(28)
          expect(result[:days_remaining]).to eq(14)
          expect(result[:proration_factor]).to be_within(0.0001).of(14.0 / 28.0)
        end
      end
    end

    context "with quarterly billing cycle" do
      let(:old_plan) { create(:plan, price_cents: 3000, billing_cycle: "quarterly") }
      let(:new_plan) { create(:plan, price_cents: 6000, billing_cycle: "quarterly") }

      it "uses calendar-aware days for Q1 2024" do
        travel_to Date.new(2024, 2, 1) do
          result = service.calculate_proration(
            old_plan: old_plan,
            new_plan: new_plan,
            billing_cycle_anchor: Date.new(2024, 4, 1),
            current_period_start: Date.new(2024, 1, 1)
          )

          # Q1 2024 has 91 days (31+29+31), 60 days remaining (Feb 1 to Apr 1)
          expect(result[:days_in_period]).to eq(91)
          expect(result[:days_remaining]).to eq(60)
        end
      end
    end

    context "with yearly billing cycle" do
      let(:old_plan) { create(:plan, price_cents: 12000, billing_cycle: "yearly") }
      let(:new_plan) { create(:plan, price_cents: 24000, billing_cycle: "yearly") }

      it "uses 366 days for leap year 2024" do
        travel_to Date.new(2024, 7, 1) do
          result = service.calculate_proration(
            old_plan: old_plan,
            new_plan: new_plan,
            billing_cycle_anchor: Date.new(2025, 1, 1),
            current_period_start: Date.new(2024, 1, 1)
          )

          # 2024 has 366 days, 184 days remaining (Jul 1 to Jan 1)
          expect(result[:days_in_period]).to eq(366)
          expect(result[:days_remaining]).to eq(184)
        end
      end

      it "uses 365 days for non-leap year 2023" do
        travel_to Date.new(2023, 7, 1) do
          result = service.calculate_proration(
            old_plan: old_plan,
            new_plan: new_plan,
            billing_cycle_anchor: Date.new(2024, 1, 1),
            current_period_start: Date.new(2023, 1, 1)
          )

          # 2023 has 365 days, 184 days remaining
          expect(result[:days_in_period]).to eq(365)
          expect(result[:days_remaining]).to eq(184)
        end
      end
    end

    context "edge cases" do
      it "returns zero proration when billing anchor is in the past" do
        travel_to Date.new(2024, 2, 1) do
          result = service.calculate_proration(
            old_plan: old_plan,
            new_plan: new_plan,
            billing_cycle_anchor: Date.new(2024, 1, 15),  # Past date
            current_period_start: Date.new(2024, 1, 1)
          )

          expect(result[:proration_amount_cents]).to eq(0)
          expect(result[:days_remaining]).to eq(0)
          expect(result[:proration_factor]).to eq(0.0)
        end
      end

      it "returns zero proration when billing anchor is today" do
        travel_to Date.new(2024, 1, 15) do
          result = service.calculate_proration(
            old_plan: old_plan,
            new_plan: new_plan,
            billing_cycle_anchor: Date.new(2024, 1, 15),
            current_period_start: Date.new(2024, 1, 1)
          )

          expect(result[:proration_amount_cents]).to eq(0)
          expect(result[:days_remaining]).to eq(0)
        end
      end

      it "handles same price plans (no proration amount)" do
        same_price_plan = create(:plan, price_cents: 1000, billing_cycle: "monthly")

        travel_to Date.new(2024, 1, 15) do
          result = service.calculate_proration(
            old_plan: old_plan,
            new_plan: same_price_plan,
            billing_cycle_anchor: Date.new(2024, 1, 31),
            current_period_start: Date.new(2024, 1, 1)
          )

          expect(result[:proration_amount_cents]).to eq(0)
          expect(result[:is_upgrade]).to be false
        end
      end

      it "uses current date as period start when not provided" do
        travel_to Date.new(2024, 1, 15) do
          result = service.calculate_proration(
            old_plan: old_plan,
            new_plan: new_plan,
            billing_cycle_anchor: Date.new(2024, 1, 31)
            # current_period_start not provided
          )

          # Should still work, using Date.current for period calculations
          expect(result[:days_remaining]).to eq(16)
          expect(result[:days_in_period]).to eq(31) # January from Jan 15
        end
      end
    end
  end

  describe "#format_currency" do
    it "formats positive amounts" do
      expect(service.format_currency(1234)).to eq("$12.34")
    end

    it "formats zero" do
      expect(service.format_currency(0)).to eq("$0.00")
    end

    it "formats negative amounts" do
      # Money gem formats negative amounts with sign after currency symbol
      expect(service.format_currency(-500)).to eq("$-5.00")
    end
  end
end
