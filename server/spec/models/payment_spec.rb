require 'rails_helper'

RSpec.describe Payment, type: :model do
  let(:payment) { build(:payment) }

  describe "associations" do
    it { should belong_to(:account) }
    it { should belong_to(:invoice) }
    it { should belong_to(:payment_method).optional }
    it { should have_one(:subscription).through(:invoice) }
  end

  describe "validations" do
    it { should validate_presence_of(:amount_cents) }
    it { should validate_numericality_of(:amount_cents).is_greater_than(0) }
    it { should validate_presence_of(:currency) }
    it { should validate_inclusion_of(:currency).in_array(%w[USD EUR GBP]) }
    it { should validate_presence_of(:gateway) }
    it { should validate_inclusion_of(:gateway).in_array(%w[stripe paypal]) }
    it { should validate_presence_of(:status) }
    it { should validate_inclusion_of(:status).in_array(%w[pending processing succeeded failed canceled refunded partially_refunded]) }
  end

  describe "scopes" do
    let!(:succeeded_payment) { create(:payment, status: "succeeded") }
    let!(:failed_payment) { create(:payment, status: "failed") }
    let!(:pending_payment) { create(:payment, status: "pending") }
    let!(:stripe_payment) { create(:payment, gateway: "stripe") }
    let!(:paypal_payment) { create(:payment, gateway: "paypal") }

    it "returns succeeded payments" do
      expect(Payment.succeeded).to include(succeeded_payment)
      expect(Payment.succeeded).not_to include(failed_payment, pending_payment)
    end

    it "returns failed payments" do
      expect(Payment.failed).to include(failed_payment)
      expect(Payment.failed).not_to include(succeeded_payment, pending_payment)
    end

    it "returns pending payments" do
      expect(Payment.pending).to include(pending_payment)
      expect(Payment.pending).not_to include(succeeded_payment, failed_payment)
    end

    it "filters by gateway" do
      expect(Payment.by_gateway("stripe")).to include(stripe_payment)
      expect(Payment.by_gateway("stripe")).not_to include(paypal_payment)
    end

    it "returns stripe payments" do
      expect(Payment.stripe_payments).to include(stripe_payment)
      expect(Payment.stripe_payments).not_to include(paypal_payment)
    end

    it "returns paypal payments" do
      expect(Payment.paypal_payments).to include(paypal_payment)
      expect(Payment.paypal_payments).not_to include(stripe_payment)
    end
  end

  describe "callbacks" do
    describe "#calculate_net_amount" do
      it "calculates net amount without gateway fee" do
        payment = build(:payment, amount_cents: 2000, metadata: {})
        payment.save!

        expect(payment.net_amount.cents).to eq(2000)
      end

      it "calculates net amount with gateway fee" do
        payment = build(:payment, amount_cents: 2000, metadata: { "gateway_fee_cents" => 100 })
        payment.save!

        expect(payment.net_amount.cents).to eq(1900)
      end
    end

    describe "#set_defaults" do
      it "initializes metadata as empty hash" do
        payment = Payment.new
        expect(payment.metadata).to eq({})
      end

      it "sets currency from invoice" do
        invoice = create(:invoice, currency: "EUR")
        payment = Payment.new(invoice: invoice)

        expect(payment.currency).to eq("EUR")
      end

      it "defaults to USD when no invoice currency" do
        payment = Payment.new
        expect(payment.currency).to eq("USD")
      end
    end
  end

  describe "state machine" do
    describe "initial state" do
      it "starts in pending state" do
        payment = build(:payment)
        expect(payment.status).to eq("pending")
        expect(payment).to be_pending
      end
    end

    describe "#process" do
      it "transitions from pending to processing" do
        payment = create(:payment, status: "pending")

        expect { payment.process! }.to change { payment.status }.from("pending").to("processing")
      end
    end

    describe "#succeed" do
      it "transitions from pending to succeeded" do
        payment = create(:payment, status: "pending")

        expect { payment.succeed! }.to change { payment.status }.from("pending").to("succeeded")
      end

      it "transitions from processing to succeeded" do
        payment = create(:payment, status: "processing")

        expect { payment.succeed! }.to change { payment.status }.from("processing").to("succeeded")
      end

      it "sets processed_at timestamp" do
        payment = create(:payment, status: "pending")

        payment.succeed!
        expect(payment.processed_at).to be_within(1.second).of(Time.current)
      end

      it "marks invoice as paid when succeeding" do
        subscription = create(:subscription)
        invoice = create(:invoice, 
          account: subscription.account, 
          subscription: subscription, 
          status: "open"
        )
        payment = create(:payment, 
          account: subscription.account, 
          invoice: invoice, 
          status: "pending"
        )

        expect { payment.succeed! }.to change { invoice.reload.status }.from("open").to("paid")
      end
    end

    describe "#fail" do
      it "transitions from pending to failed" do
        payment = create(:payment, status: "pending")

        expect { payment.fail! }.to change { payment.status }.from("pending").to("failed")
      end

      it "transitions from processing to failed" do
        payment = create(:payment, status: "processing")

        expect { payment.fail! }.to change { payment.status }.from("processing").to("failed")
      end

      it "sets failed_at timestamp" do
        payment = create(:payment, status: "pending")

        payment.fail!
        expect(payment.failed_at).to be_within(1.second).of(Time.current)
      end
    end

    describe "#cancel" do
      it "transitions from pending to canceled" do
        payment = create(:payment, status: "pending")

        expect { payment.cancel! }.to change { payment.status }.from("pending").to("canceled")
      end

      it "transitions from processing to canceled" do
        payment = create(:payment, status: "processing")

        expect { payment.cancel! }.to change { payment.status }.from("processing").to("canceled")
      end
    end

    describe "#refund" do
      it "transitions from succeeded to refunded" do
        payment = create(:payment, status: "succeeded")

        expect { payment.refund! }.to change { payment.status }.from("succeeded").to("refunded")
      end
    end

    describe "#partially_refund" do
      it "transitions from succeeded to partially_refunded" do
        payment = create(:payment, status: "succeeded")

        expect { payment.partially_refund! }.to change { payment.status }.from("succeeded").to("partially_refunded")
      end
    end
  end

  describe "money methods" do
    let(:payment) { create(:payment, amount_cents: 2000, metadata: { "gateway_fee_cents" => 100 }, currency: "USD") }

    describe "#amount" do
      it "returns Money object for amount" do
        expect(payment.amount).to be_a(Money)
        expect(payment.amount.cents).to eq(2000)
        expect(payment.amount.currency.to_s).to eq("USD")
      end
    end

    describe "#gateway_fee" do
      it "returns Money object for gateway fee" do
        expect(payment.gateway_fee).to be_a(Money)
        expect(payment.gateway_fee.cents).to eq(100)
        expect(payment.gateway_fee.currency.to_s).to eq("USD")
      end

      it "returns zero when no gateway fee" do
        payment = create(:payment, metadata: {})
        expect(payment.gateway_fee.cents).to eq(0)
      end
    end

    describe "#net_amount" do
      it "returns Money object for net amount" do
        expect(payment.net_amount).to be_a(Money)
        expect(payment.net_amount.cents).to eq(1900)
        expect(payment.net_amount.currency.to_s).to eq("USD")
      end

      it "returns full amount when no gateway fee" do
        payment = create(:payment, amount_cents: 2000, metadata: {})
        expect(payment.net_amount.cents).to eq(2000)
      end
    end
  end

  describe "instance methods" do
    describe "#provider" do
      it "returns 'stripe' for stripe gateway" do
        stripe_payment = build(:payment, gateway: "stripe")

        expect(stripe_payment.provider).to eq("stripe")
      end

      it "returns 'paypal' for paypal gateway" do
        paypal_payment = build(:payment, gateway: "paypal")

        expect(paypal_payment.provider).to eq("paypal")
      end

      it "returns 'stripe' when no payment method" do
        stripe_payment = build(:payment, gateway: "stripe", payment_method: nil)

        expect(stripe_payment.provider).to eq("stripe")
      end
    end

    describe "#gateway_transaction_id" do
      it "returns stripe payment intent ID for stripe payments" do
        payment = build(:payment, gateway: "stripe", metadata: { "stripe_payment_intent_id" => "pi_123" })

        expect(payment.gateway_transaction_id).to eq("pi_123")
      end

      it "returns stripe charge ID when no payment intent" do
        payment = build(:payment, gateway: "stripe", metadata: { "stripe_charge_id" => "ch_123" })

        expect(payment.gateway_transaction_id).to eq("ch_123")
      end

      it "returns paypal order ID for paypal payments" do
        payment = build(:payment, gateway: "paypal", metadata: { "paypal_order_id" => "ORDER_123" })

        expect(payment.gateway_transaction_id).to eq("ORDER_123")
      end

      it "returns paypal capture ID when no order ID" do
        payment = build(:payment, gateway: "paypal", metadata: { "paypal_capture_id" => "CAPTURE_123" })

        expect(payment.gateway_transaction_id).to eq("CAPTURE_123")
      end

      it "returns nil when no transaction metadata" do
        payment = build(:payment, gateway: "stripe", metadata: {})

        expect(payment.gateway_transaction_id).to be_nil
      end
    end

    describe "#processing_time" do
      it "calculates processing time" do
        payment = build(:payment,
          created_at: 1.hour.ago,
          processed_at: Time.current
        )

        expect(payment.processing_time).to be_within(5.seconds).of(1.hour)
      end

      it "returns nil when not processed" do
        payment = build(:payment, processed_at: nil)

        expect(payment.processing_time).to be_nil
      end

      it "returns nil when no created_at" do
        payment = build(:payment, created_at: nil, processed_at: Time.current)

        expect(payment.processing_time).to be_nil
      end
    end

    describe "#can_be_refunded?" do
      it "returns true for succeeded payments" do
        payment = build(:payment, status: "succeeded")

        expect(payment.can_be_refunded?).to be true
      end

      it "returns false for failed payments" do
        payment = build(:payment, status: "failed")

        expect(payment.can_be_refunded?).to be false
      end

      it "returns false for refunded payments" do
        payment = build(:payment, status: "refunded")

        expect(payment.can_be_refunded?).to be false
      end

      it "returns false for partially refunded payments" do
        payment = build(:payment, status: "partially_refunded")

        expect(payment.can_be_refunded?).to be false
      end
    end

    describe "#refundable_amount" do
      it "returns full amount for refundable payments" do
        payment = build(:payment, status: "succeeded", amount_cents: 2000)

        expect(payment.refundable_amount.cents).to eq(2000)
      end

      it "returns zero for non-refundable payments" do
        payment = build(:payment, status: "failed", amount_cents: 2000)

        expect(payment.refundable_amount.cents).to eq(0)
      end
    end
  end

  describe "gateway specific behavior" do
    describe "stripe payments" do
      it "processes stripe payments correctly" do
        payment = create(:payment,
          gateway: "stripe",
          metadata: { 
            "stripe_payment_intent_id" => "pi_123456",
            "stripe_charge_id" => "ch_123456"
          }
        )

        expect(payment.provider).to eq("stripe")
        expect(payment.gateway_transaction_id).to eq("pi_123456")
      end
    end

    describe "paypal payments" do
      it "processes paypal payments correctly" do
        payment = create(:payment,
          gateway: "paypal",
          metadata: { "paypal_order_id" => "ORDER_789012" }
        )

        expect(payment.provider).to eq("paypal")
        expect(payment.gateway_transaction_id).to eq("ORDER_789012")
      end
    end

    describe "payment metadata" do
      it "processes custom metadata correctly" do
        payment = create(:payment,
          gateway: "stripe",
          metadata: { reference_number: "TXN_123456" }
        )

        expect(payment.provider).to eq("stripe")
        expect(payment.metadata["reference_number"]).to eq("TXN_123456")
      end
    end
  end
end
