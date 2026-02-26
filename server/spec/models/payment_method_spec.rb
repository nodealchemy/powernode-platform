# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Billing::PaymentMethod, type: :model do
  let(:payment_method) { build(:payment_method) }

  describe "associations" do
    it { should belong_to(:account) }
  end

  describe "validations" do
    it { should validate_presence_of(:gateway) }
    it { should validate_inclusion_of(:gateway).in_array(%w[stripe paypal]) }
    it { should validate_presence_of(:external_id) }
    it { should validate_presence_of(:payment_type) }
    it { should validate_inclusion_of(:payment_type).in_array(%w[card bank paypal apple_pay google_pay]) }
  end

  describe "scopes" do
    let!(:stripe_payment_method) { create(:payment_method, gateway: "stripe") }
    let!(:paypal_payment_method) { create(:payment_method, gateway: "paypal") }

    describe ".for_gateway" do
      it "returns payment methods for stripe" do
        expect(Billing::PaymentMethod.for_gateway("stripe")).to include(stripe_payment_method)
        expect(Billing::PaymentMethod.for_gateway("stripe")).not_to include(paypal_payment_method)
      end

      it "returns payment methods for paypal" do
        expect(Billing::PaymentMethod.for_gateway("paypal")).to include(paypal_payment_method)
        expect(Billing::PaymentMethod.for_gateway("paypal")).not_to include(stripe_payment_method)
      end
    end
  end


  describe "gateway methods" do
    describe "#stripe?" do
      it "returns true when gateway is stripe" do
        payment_method = build(:payment_method, gateway: "stripe")
        expect(payment_method.stripe?).to be true
      end

      it "returns false when gateway is not stripe" do
        payment_method = build(:payment_method, gateway: "paypal")
        expect(payment_method.stripe?).to be false
      end
    end

    describe "#paypal?" do
      it "returns true when gateway is paypal" do
        payment_method = build(:payment_method, gateway: "paypal")
        expect(payment_method.paypal?).to be true
      end

      it "returns false when gateway is not paypal" do
        payment_method = build(:payment_method, gateway: "stripe")
        expect(payment_method.paypal?).to be false
      end
    end
  end

  describe "payment method type methods" do
    describe "#card?" do
      it "returns true when payment method type is card" do
        payment_method = build(:payment_method, payment_type: "card")
        expect(payment_method.card?).to be true
      end

      it "returns false when payment method type is not card" do
        payment_method = build(:payment_method, payment_type: "bank")
        expect(payment_method.card?).to be false
      end
    end

    describe "#bank_account?" do
      it "returns true when payment method type is bank_account" do
        payment_method = build(:payment_method, payment_type: "bank")
        expect(payment_method.bank_account?).to be true
      end

      it "returns false when payment method type is not bank_account" do
        payment_method = build(:payment_method, payment_type: "card")
        expect(payment_method.bank_account?).to be false
      end
    end

    describe "#paypal_account?" do
      it "returns true when payment method type is paypal_account" do
        payment_method = build(:payment_method, payment_type: "paypal")
        expect(payment_method.paypal_account?).to be true
      end

      it "returns false when payment method type is not paypal_account" do
        payment_method = build(:payment_method, payment_type: "card")
        expect(payment_method.paypal_account?).to be false
      end
    end
  end

  describe "#display_name" do
    context "for card payment method" do
      it "returns formatted card display name" do
        payment_method = build(:payment_method,
          payment_type: "card",
          last_four: "4242"
        )

        expect(payment_method.display_name).to eq("Card •••• 4242")
      end

      it "handles nil last_four gracefully" do
        payment_method = build(:payment_method,
          payment_type: "card",
          last_four: nil
        )

        expect(payment_method.display_name).to eq("Card •••• ")
      end
    end

    context "for bank account payment method" do
      it "returns formatted bank account display name" do
        payment_method = build(:payment_method,
          payment_type: "bank",
          last_four: "1234"
        )

        expect(payment_method.display_name).to eq("Bank Account •••• 1234")
      end
    end

    context "for paypal account payment method" do
      it "returns formatted paypal display name" do
        payment_method = build(:payment_method,
          payment_type: "paypal"
        )

        expect(payment_method.display_name).to eq("PayPal")
      end
    end

    context "for unknown payment method type" do
      it "returns generic display name" do
        payment_method = build(:payment_method, payment_type: "unknown")

        expect(payment_method.display_name).to eq("Payment Method")
      end
    end
  end

  describe "#can_be_used_for_recurring?" do
    context "with stripe gateway" do
      it "returns true for card payment method" do
        payment_method = build(:payment_method,
          gateway: "stripe",
          payment_type: "card"
        )

        expect(payment_method.can_be_used_for_recurring?).to be true
      end

      it "returns true for bank account payment method" do
        payment_method = build(:payment_method,
          gateway: "stripe",
          payment_type: "bank"
        )

        expect(payment_method.can_be_used_for_recurring?).to be true
      end

      it "returns false for paypal account payment method with stripe" do
        payment_method = build(:payment_method,
          gateway: "stripe",
          payment_type: "paypal"
        )

        expect(payment_method.can_be_used_for_recurring?).to be false
      end
    end

    context "with paypal gateway" do
      it "returns true for paypal account payment method" do
        payment_method = build(:payment_method,
          gateway: "paypal",
          payment_type: "paypal"
        )

        expect(payment_method.can_be_used_for_recurring?).to be true
      end

      it "returns false for card payment method with paypal" do
        payment_method = build(:payment_method,
          gateway: "paypal",
          payment_type: "card"
        )

        expect(payment_method.can_be_used_for_recurring?).to be false
      end

      it "returns false for bank account payment method with paypal" do
        payment_method = build(:payment_method,
          gateway: "paypal",
          payment_type: "bank"
        )

        expect(payment_method.can_be_used_for_recurring?).to be false
      end
    end

    context "with unknown gateway" do
      it "returns false" do
        payment_method = build(:payment_method, gateway: "unknown")

        expect(payment_method.can_be_used_for_recurring?).to be false
      end
    end
  end

  describe "#deactivate!" do
    it "sets is_default to false" do
      payment_method = create(:payment_method, is_default: true)

      payment_method.deactivate!

      expect(payment_method.is_default).to be false
    end

    it "persists the changes to database" do
      payment_method = create(:payment_method, is_default: true)

      payment_method.deactivate!
      payment_method.reload

      expect(payment_method.is_default).to be false
    end
  end

  describe "payment method types" do
    describe "stripe card" do
      it "creates valid stripe card payment method" do
        payment_method = create(:payment_method,
          gateway: "stripe",
          payment_type: "card",
          last_four: "4242"
        )

        expect(payment_method).to be_valid
        expect(payment_method.stripe?).to be true
        expect(payment_method.card?).to be true
        expect(payment_method.can_be_used_for_recurring?).to be true
        expect(payment_method.display_name).to eq("Card •••• 4242")
      end
    end

    describe "stripe bank account" do
      it "creates valid stripe bank account payment method" do
        payment_method = create(:payment_method,
          gateway: "stripe",
          payment_type: "bank",
          last_four: "6789"
        )

        expect(payment_method).to be_valid
        expect(payment_method.stripe?).to be true
        expect(payment_method.bank_account?).to be true
        expect(payment_method.can_be_used_for_recurring?).to be true
        expect(payment_method.display_name).to eq("Bank Account •••• 6789")
      end
    end

    describe "paypal account" do
      it "creates valid paypal account payment method" do
        payment_method = create(:payment_method,
          gateway: "paypal",
          payment_type: "paypal"
        )

        expect(payment_method).to be_valid
        expect(payment_method.paypal?).to be true
        expect(payment_method.paypal_account?).to be true
        expect(payment_method.can_be_used_for_recurring?).to be true
        expect(payment_method.display_name).to eq("PayPal")
      end
    end
  end
end
