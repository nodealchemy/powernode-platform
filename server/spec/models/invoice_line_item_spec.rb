# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InvoiceLineItem, type: :model do
  let(:line_item) { build(:invoice_line_item) }

  describe "associations" do
    it { should belong_to(:invoice) }
  end

  describe "validations" do
    it { should validate_presence_of(:description) }
    it { should validate_presence_of(:quantity) }
    it { should validate_numericality_of(:quantity).is_greater_than(0) }
    it { should validate_presence_of(:unit_amount_cents) }
    it { should validate_numericality_of(:unit_amount_cents).is_greater_than_or_equal_to(0) }
    it { should validate_presence_of(:total_amount_cents) }
    it { should validate_numericality_of(:total_amount_cents).is_greater_than_or_equal_to(0) }
    #     it { should validate_presence_of(:line_type) }
    #     it { should validate_inclusion_of(:line_type).in_array(%w[subscription usage discount tax adjustment]) }
  end

  describe "scopes" do
    let!(:subscription_item) { create(:invoice_line_item, line_type: "subscription") }
    let!(:usage_item) { create(:invoice_line_item, line_type: "usage") }
    let!(:discount_item) { create(:invoice_line_item, line_type: "discount") }
    let!(:tax_item) { create(:invoice_line_item, line_type: "tax") }
    let!(:adjustment_item) { create(:invoice_line_item, line_type: "adjustment") }

    it "returns subscription items" do
      expect(InvoiceLineItem.subscription_items).to include(subscription_item)
      expect(InvoiceLineItem.subscription_items).not_to include(usage_item, discount_item, tax_item, adjustment_item)
    end

    it "returns usage items" do
      expect(InvoiceLineItem.usage_items).to include(usage_item)
      expect(InvoiceLineItem.usage_items).not_to include(subscription_item, discount_item, tax_item, adjustment_item)
    end

    it "returns discount items" do
      expect(InvoiceLineItem.discounts).to include(discount_item)
      expect(InvoiceLineItem.discounts).not_to include(subscription_item, usage_item, tax_item, adjustment_item)
    end

    it "returns tax items" do
      expect(InvoiceLineItem.taxes).to include(tax_item)
      expect(InvoiceLineItem.taxes).not_to include(subscription_item, usage_item, discount_item, adjustment_item)
    end

    it "returns adjustment items" do
      expect(InvoiceLineItem.adjustments).to include(adjustment_item)
      expect(InvoiceLineItem.adjustments).not_to include(subscription_item, usage_item, discount_item, tax_item)
    end
  end

  describe "callbacks" do
    describe "#calculate_total" do
      it "calculates total from quantity and unit price" do
        line_item = build(:invoice_line_item, quantity: 3, unit_amount_cents: 1000)
        line_item.save!

        expect(line_item.total_amount_cents).to eq(3000)
      end

      it "recalculates when quantity changes" do
        line_item = create(:invoice_line_item, quantity: 2, unit_amount_cents: 1500)

        line_item.quantity = 4
        line_item.save!

        expect(line_item.total_amount_cents).to eq(6000)
      end

      it "recalculates when unit price changes" do
        line_item = create(:invoice_line_item, quantity: 2, unit_amount_cents: 1000)

        line_item.unit_amount_cents = 1500
        line_item.save!

        expect(line_item.total_amount_cents).to eq(3000)
      end
    end

    describe "#set_defaults" do
      it "initializes metadata as empty hash" do
        line_item = InvoiceLineItem.new
        expect(line_item.metadata).to eq({})
      end
    end
  end

  describe "money methods" do
    let(:invoice) { create(:invoice, currency: "USD") }
    let(:line_item) { create(:invoice_line_item, invoice: invoice, unit_amount_cents: 2500, quantity: 2) }

    describe "#unit_price" do
      it "returns Money object for unit price" do
        expect(line_item.unit_price).to be_a(Money)
        expect(line_item.unit_price.cents).to eq(2500)
        expect(line_item.unit_price.currency.to_s).to eq("USD")
      end
    end

    describe "#total" do
      it "returns Money object for total" do
        expect(line_item.total).to be_a(Money)
        expect(line_item.total.cents).to eq(5000)
        expect(line_item.total.currency.to_s).to eq("USD")
      end
    end
  end

  describe "instance methods" do
    describe "#period_description" do
      it "returns formatted period description when both dates present" do
        line_item = build(:invoice_line_item,
          period_start: Date.new(2024, 1, 1),
          period_end: Date.new(2024, 1, 31)
        )

        expect(line_item.period_description).to eq("Jan 01 - Jan 31, 2024")
      end

      it "returns nil when period_start is missing" do
        line_item = build(:invoice_line_item,
          period_start: nil,
          period_end: Date.new(2024, 1, 31)
        )

        expect(line_item.period_description).to be_nil
      end

      it "returns nil when period_end is missing" do
        line_item = build(:invoice_line_item,
          period_start: Date.new(2024, 1, 1),
          period_end: nil
        )

        expect(line_item.period_description).to be_nil
      end

      it "returns nil when both period dates are missing" do
        line_item = build(:invoice_line_item,
          period_start: nil,
          period_end: nil
        )

        expect(line_item.period_description).to be_nil
      end
    end

    describe "#proration_factor" do
      let(:plan) { create(:plan, billing_cycle: "monthly") }
      let(:subscription) { create(:subscription, plan: plan) }
      let(:invoice) { create(:invoice, subscription: subscription) }

      it "returns 1.0 when no period dates" do
        line_item = build(:invoice_line_item, invoice: invoice, period_start: nil, period_end: nil)

        expect(line_item.proration_factor).to eq(1.0)
      end

      it "returns 1.0 when period dates are invalid" do
        line_item = build(:invoice_line_item,
          invoice: invoice,
          period_start: Date.new(2024, 1, 31),
          period_end: Date.new(2024, 1, 1)
        )

        expect(line_item.proration_factor).to eq(1.0)
      end

      it "returns 1.0 when no billing cycle available" do
        invoice_without_sub = build(:invoice, subscription: nil)
        line_item = build(:invoice_line_item,
          invoice: invoice_without_sub,
          period_start: Date.new(2024, 1, 1),
          period_end: Date.new(2024, 1, 15)
        )

        expect(line_item.proration_factor).to eq(1.0)
      end

      context "with monthly billing cycle - calendar-aware calculations" do
        # January 2024 has 31 days
        it "calculates proration using actual days in January (31 days)" do
          line_item = build(:invoice_line_item,
            invoice: invoice,
            period_start: Date.new(2024, 1, 1),
            period_end: Date.new(2024, 1, 16)  # 15 days used
          )

          # 15 days / 31 days in January = 0.4839
          expect(line_item.proration_factor).to be_within(0.001).of(15.0 / 31.0)
        end

        # February 2024 is a leap year (29 days)
        it "calculates proration using actual days in February leap year (29 days)" do
          line_item = build(:invoice_line_item,
            invoice: invoice,
            period_start: Date.new(2024, 2, 1),
            period_end: Date.new(2024, 2, 15)  # 14 days used
          )

          # 14 days / 29 days in February 2024 = 0.4828
          expect(line_item.proration_factor).to be_within(0.001).of(14.0 / 29.0)
        end

        # February 2023 is not a leap year (28 days)
        it "calculates proration using actual days in February non-leap year (28 days)" do
          line_item = build(:invoice_line_item,
            invoice: invoice,
            period_start: Date.new(2023, 2, 1),
            period_end: Date.new(2023, 2, 15)  # 14 days used
          )

          # 14 days / 28 days in February 2023 = 0.5
          expect(line_item.proration_factor).to be_within(0.001).of(14.0 / 28.0)
        end

        # April has 30 days
        it "calculates proration using actual days in April (30 days)" do
          line_item = build(:invoice_line_item,
            invoice: invoice,
            period_start: Date.new(2024, 4, 1),
            period_end: Date.new(2024, 4, 16)  # 15 days used
          )

          # 15 days / 30 days in April = 0.5
          expect(line_item.proration_factor).to be_within(0.001).of(15.0 / 30.0)
        end

        it "returns approximately 1.0 for full month coverage" do
          line_item = build(:invoice_line_item,
            invoice: invoice,
            period_start: Date.new(2024, 1, 1),
            period_end: Date.new(2024, 2, 1)  # Full January (31 days)
          )

          # 31 days / 31 days = 1.0
          expect(line_item.proration_factor).to be_within(0.001).of(1.0)
        end
      end

      context "with quarterly billing cycle - calendar-aware calculations" do
        let(:plan) { create(:plan, billing_cycle: "quarterly") }

        # Q1 2024: Jan (31) + Feb (29 leap) + Mar (31) = 91 days
        it "calculates proration using actual days in Q1 2024 (91 days)" do
          line_item = build(:invoice_line_item,
            invoice: invoice,
            period_start: Date.new(2024, 1, 1),
            period_end: Date.new(2024, 2, 1)  # 31 days used
          )

          # 31 days / 91 days in Q1 2024 = 0.3407
          expect(line_item.proration_factor).to be_within(0.001).of(31.0 / 91.0)
        end

        # Q1 2023: Jan (31) + Feb (28 non-leap) + Mar (31) = 90 days
        it "calculates proration using actual days in Q1 2023 (90 days - non-leap)" do
          line_item = build(:invoice_line_item,
            invoice: invoice,
            period_start: Date.new(2023, 1, 1),
            period_end: Date.new(2023, 2, 1)  # 31 days used
          )

          # 31 days / 90 days in Q1 2023 = 0.3444
          expect(line_item.proration_factor).to be_within(0.001).of(31.0 / 90.0)
        end

        # Q2 2024: Apr (30) + May (31) + Jun (30) = 91 days
        it "calculates proration for Q2 period" do
          line_item = build(:invoice_line_item,
            invoice: invoice,
            period_start: Date.new(2024, 4, 1),
            period_end: Date.new(2024, 5, 1)  # 30 days used
          )

          # 30 days / 91 days in Q2 2024
          expect(line_item.proration_factor).to be_within(0.001).of(30.0 / 91.0)
        end
      end

      context "with yearly billing cycle - calendar-aware calculations" do
        let(:plan) { create(:plan, billing_cycle: "yearly") }

        # 2024 is a leap year (366 days)
        it "calculates proration using actual days in leap year 2024 (366 days)" do
          line_item = build(:invoice_line_item,
            invoice: invoice,
            period_start: Date.new(2024, 1, 1),
            period_end: Date.new(2024, 7, 1)  # Jan-Jun = 182 days
          )

          # 182 days / 366 days in 2024 = 0.4973
          expect(line_item.proration_factor).to be_within(0.001).of(182.0 / 366.0)
        end

        # 2023 is not a leap year (365 days)
        it "calculates proration using actual days in non-leap year 2023 (365 days)" do
          line_item = build(:invoice_line_item,
            invoice: invoice,
            period_start: Date.new(2023, 1, 1),
            period_end: Date.new(2023, 7, 1)  # Jan-Jun = 181 days
          )

          # 181 days / 365 days in 2023 = 0.4959
          expect(line_item.proration_factor).to be_within(0.001).of(181.0 / 365.0)
        end

        it "returns approximately 1.0 for full year coverage" do
          line_item = build(:invoice_line_item,
            invoice: invoice,
            period_start: Date.new(2024, 1, 1),
            period_end: Date.new(2025, 1, 1)  # Full 2024 (366 days)
          )

          # 366 days / 366 days = 1.0
          expect(line_item.proration_factor).to be_within(0.001).of(1.0)
        end
      end

      context "with unknown billing cycle" do
        it "falls back to 30-day default for unknown billing cycle" do
          plan = build(:plan, billing_cycle: "monthly")
          allow(plan).to receive(:billing_cycle).and_return("unknown")
          subscription = build(:subscription, plan: plan)
          invoice = build(:invoice, subscription: subscription)

          line_item = build(:invoice_line_item,
            invoice: invoice,
            period_start: Date.new(2024, 1, 1),
            period_end: Date.new(2024, 1, 16)  # 15 days used
          )

          # 15 days / 30 days fallback = 0.5
          expect(line_item.proration_factor).to be_within(0.001).of(15.0 / 30.0)
        end
      end

      context "edge cases" do
        it "handles period spanning month boundary correctly" do
          # Mid-January to mid-February
          line_item = build(:invoice_line_item,
            invoice: invoice,
            period_start: Date.new(2024, 1, 15),
            period_end: Date.new(2024, 2, 15)  # 31 days used
          )

          # Period starts in Jan, so use Jan's days (31)
          # 31 days / 31 days = 1.0
          expect(line_item.proration_factor).to be_within(0.001).of(31.0 / 31.0)
        end

        it "handles single day period" do
          line_item = build(:invoice_line_item,
            invoice: invoice,
            period_start: Date.new(2024, 1, 1),
            period_end: Date.new(2024, 1, 2)  # 1 day used
          )

          # 1 day / 31 days in January = 0.0323
          expect(line_item.proration_factor).to be_within(0.001).of(1.0 / 31.0)
        end
      end
    end

    describe "#is_prorated?" do
      let(:plan) { create(:plan, billing_cycle: "monthly") }
      let(:subscription) { create(:subscription, plan: plan) }
      let(:invoice) { create(:invoice, subscription: subscription) }

      it "returns true when proration factor is less than 1.0" do
        line_item = build(:invoice_line_item,
          invoice: invoice,
          period_start: Date.new(2024, 1, 1),
          period_end: Date.new(2024, 1, 15)
        )

        expect(line_item.is_prorated?).to be true
      end

      it "returns false when proration factor is 1.0" do
        line_item = build(:invoice_line_item,
          invoice: invoice,
          period_start: nil,
          period_end: nil
        )

        expect(line_item.is_prorated?).to be false
      end

      it "returns false for full billing period" do
        line_item = build(:invoice_line_item,
          invoice: invoice,
          period_start: Date.new(2024, 1, 1),
          period_end: Date.new(2024, 2, 1)  # Full January (31 days)
        )

        # Jan 1 to Feb 1 = 31 days / 31 days in January = 1.0, so not prorated
        expect(line_item.is_prorated?).to be false
      end
    end
  end

  describe "line type specific behavior" do
    describe "subscription line items" do
      it "represents subscription charges" do
        line_item = create(:invoice_line_item,
          line_type: "subscription",
          description: "Pro Plan (monthly)",
          quantity: 1,
          unit_amount_cents: 2999
        )

        expect(line_item.line_type).to eq("subscription")
        expect(line_item.description).to include("Pro Plan")
        expect(line_item.total_amount_cents).to eq(2999)
      end
    end

    describe "usage line items" do
      it "represents usage-based charges" do
        line_item = create(:invoice_line_item,
          line_type: "usage",
          description: "API Calls (per 1000)",
          quantity: 5,
          unit_amount_cents: 500
        )

        expect(line_item.line_type).to eq("usage")
        expect(line_item.description).to include("API Calls")
        expect(line_item.total_amount_cents).to eq(2500)
      end
    end

    describe "discount line items" do
      it "represents discounts applied" do
        line_item = create(:invoice_line_item,
          line_type: "discount",
          description: "20% Off Promotion",
          quantity: 1,
          unit_amount_cents: -600
        )

        expect(line_item.line_type).to eq("discount")
        expect(line_item.description).to include("Promotion")
        expect(line_item.unit_amount_cents).to be_negative
      end
    end

    describe "tax line items" do
      it "represents tax charges" do
        line_item = create(:invoice_line_item,
          line_type: "tax",
          description: "Sales Tax (8.5%)",
          quantity: 1,
          unit_amount_cents: 255
        )

        expect(line_item.line_type).to eq("tax")
        expect(line_item.description).to include("Tax")
        expect(line_item.total_amount_cents).to eq(255)
      end
    end

    describe "adjustment line items" do
      it "represents manual adjustments" do
        line_item = create(:invoice_line_item,
          line_type: "adjustment",
          description: "Credit for service outage",
          quantity: 1,
          unit_amount_cents: -1000
        )

        expect(line_item.line_type).to eq("adjustment")
        expect(line_item.description).to include("Credit")
        expect(line_item.unit_amount_cents).to be_negative
      end
    end
  end
end
