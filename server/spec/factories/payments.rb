FactoryBot.define do
  factory :payment do
    # Default associations - account and invoice are required
    association :account
    association :invoice
    # payment_method is optional - only create for certain gateways
    
    # Ensure payment account matches invoice account when invoice is provided
    after(:build) do |payment, evaluator|
      if payment.invoice && payment.invoice.account
        payment.account = payment.invoice.account
      end
      
      # Create payment_method for all gateways
      if payment.payment_method.nil?
        if payment.gateway == 'stripe'
          payment.payment_method = FactoryBot.create(:payment_method, :stripe, account: payment.account)
        elsif payment.gateway == 'paypal'
          payment.payment_method = FactoryBot.create(:payment_method, :paypal, account: payment.account)
        end
      end
    end
    
    amount_cents { 2999 }
    currency { "USD" }
    status { "pending" }
    gateway { "stripe" }
    processed_at { nil }
    failure_reason { nil }
    metadata { {} }

    trait :succeeded do
      status { "succeeded" }
      processed_at { Time.current }
    end

    trait :failed do
      status { "failed" }
      failure_reason { "Card declined" }
    end

    trait :stripe_payment do
      gateway { "stripe" }
      metadata do
        { 
          "stripe_payment_intent_id" => "pi_test_123456789", 
          "stripe_charge_id" => "ch_test_123456789" 
        }
      end
    end

    trait :paypal_payment do
      gateway { "paypal" }
      metadata do
        { 
          "paypal_order_id" => "ORDER-123456789", 
          "paypal_capture_id" => "CAPTURE-123456789" 
        }
      end
    end

    # manual_payment removed - only stripe and paypal gateways are allowed

    trait :with_gateway_fee do
      metadata do
        { 
          "gateway_fee_cents" => 100 
        }
      end
    end
  end
end