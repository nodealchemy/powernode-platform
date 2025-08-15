FactoryBot.define do
  factory :payment do
    invoice
    amount_cents { 2999 }
    status { "pending" }
    payment_method { "stripe_card" }
    processed_at { nil }
    failed_at { nil }
    failure_reason { nil }
    metadata { {} }

    trait :succeeded do
      status { "succeeded" }
      processed_at { Time.current }
    end

    trait :failed do
      status { "failed" }
      failed_at { Time.current }
      failure_reason { "Card declined" }
    end

    trait :stripe_payment do
      payment_method { "stripe_card" }
      metadata { { stripe_payment_intent_id: "pi_test_123456789", stripe_charge_id: "ch_test_123456789" } }
    end

    trait :paypal_payment do
      payment_method { "paypal" }
      metadata { { paypal_order_id: "ORDER-123456789", paypal_capture_id: "CAPTURE-123456789" } }
    end
  end
end
