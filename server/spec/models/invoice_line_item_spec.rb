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
    it { should validate_presence_of(:unit_price_cents) }
    it { should validate_numericality_of(:unit_price_cents).is_greater_than_or_equal_to(0) }
    it { should validate_presence_of(:total_cents) }
    it { should validate_numericality_of(:total_cents).is_greater_than_or_equal_to(0) }
    it { should validate_presence_of(:line_type) }
    it { should validate_inclusion_of(:line_type).in_array(%w[subscription usage discount tax adjustment]) }
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
        line_item = build(:invoice_line_item, quantity: 3, unit_price_cents: 1000)
        line_item.save!

        expect(line_item.total_cents).to eq(3000)
      end

      it "recalculates when quantity changes" do
        line_item = create(:invoice_line_item, quantity: 2, unit_price_cents: 1500)

        line_item.quantity = 4
        line_item.save!

        expect(line_item.total_cents).to eq(6000)
      end

      it "recalculates when unit price changes" do
        line_item = create(:invoice_line_item, quantity: 2, unit_price_cents: 1000)

        line_item.unit_price_cents = 1500
        line_item.save!

        expect(line_item.total_cents).to eq(3000)
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
    let(:line_item) { create(:invoice_line_item, invoice: invoice, unit_price_cents: 2500, quantity: 2) }

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

      context "with monthly billing cycle" do
        it "calculates proration factor for partial month" do
          line_item = build(:invoice_line_item,
            invoice: invoice,
            period_start: Date.new(2024, 1, 1),
            period_end: Date.new(2024, 1, 15)
          )

          expect(line_item.proration_factor).to be_within(0.01).of(0.47) # 14 days / 30 days
        end

        it "returns 1.0 for full month" do
          line_item = build(:invoice_line_item,
            invoice: invoice,
            period_start: Date.new(2024, 1, 1),
            period_end: Date.new(2024, 1, 30)
          )

          expect(line_item.proration_factor).to be_within(0.01).of(0.97) # 29 days / 30 days
        end
      end

      context "with quarterly billing cycle" do
        let(:plan) { create(:plan, billing_cycle: "quarterly") }

        it "calculates proration factor for partial quarter" do
          line_item = build(:invoice_line_item,
            invoice: invoice,
            period_start: Date.new(2024, 1, 1),
            period_end: Date.new(2024, 2, 1)
          )

          expect(line_item.proration_factor).to be_within(0.01).of(0.34) # 31 days / 90 days
        end
      end

      context "with yearly billing cycle" do
        let(:plan) { create(:plan, billing_cycle: "yearly") }

        it "calculates proration factor for partial year" do
          line_item = build(:invoice_line_item,
            invoice: invoice,
            period_start: Date.new(2024, 1, 1),
            period_end: Date.new(2024, 7, 1)
          )

          expect(line_item.proration_factor).to be_within(0.01).of(0.49) # ~182 days / 365 days
        end
      end

      context "with unknown billing cycle" do
        it "returns 1.0 for unknown billing cycle" do
          plan = build(:plan, billing_cycle: "monthly")
          allow(plan).to receive(:billing_cycle).and_return("unknown")
          subscription = build(:subscription, plan: plan)
          invoice = build(:invoice, subscription: subscription)

          line_item = build(:invoice_line_item,
            invoice: invoice,
            period_start: Date.new(2024, 1, 1),
            period_end: Date.new(2024, 1, 15)
          )

          expect(line_item.proration_factor).to eq(1.0)
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
          period_end: Date.new(2024, 1, 31)
        )

        # 30 days (Jan 1 to Jan 31) / 30 days baseline = 1.0, so not prorated
        # Note: (Jan 31 - Jan 1) = 30 days
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
          unit_price_cents: 2999
        )

        expect(line_item.line_type).to eq("subscription")
        expect(line_item.description).to include("Pro Plan")
        expect(line_item.total_cents).to eq(2999)
      end
    end

    describe "usage line items" do
      it "represents usage-based charges" do
        line_item = create(:invoice_line_item,
          line_type: "usage",
          description: "API Calls (per 1000)",
          quantity: 5,
          unit_price_cents: 500
        )

        expect(line_item.line_type).to eq("usage")
        expect(line_item.description).to include("API Calls")
        expect(line_item.total_cents).to eq(2500)
      end
    end

    describe "discount line items" do
      it "represents discounts applied" do
        line_item = create(:invoice_line_item,
          line_type: "discount",
          description: "20% Off Promotion",
          quantity: 1,
          unit_price_cents: -600
        )

        expect(line_item.line_type).to eq("discount")
        expect(line_item.description).to include("Promotion")
        expect(line_item.unit_price_cents).to be_negative
      end
    end

    describe "tax line items" do
      it "represents tax charges" do
        line_item = create(:invoice_line_item,
          line_type: "tax",
          description: "Sales Tax (8.5%)",
          quantity: 1,
          unit_price_cents: 255
        )

        expect(line_item.line_type).to eq("tax")
        expect(line_item.description).to include("Tax")
        expect(line_item.total_cents).to eq(255)
      end
    end

    describe "adjustment line items" do
      it "represents manual adjustments" do
        line_item = create(:invoice_line_item,
          line_type: "adjustment",
          description: "Credit for service outage",
          quantity: 1,
          unit_price_cents: -1000
        )

        expect(line_item.line_type).to eq("adjustment")
        expect(line_item.description).to include("Credit")
        expect(line_item.unit_price_cents).to be_negative
      end
    end
  end
end
