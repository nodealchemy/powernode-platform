# frozen_string_literal: true

FactoryBot.define do
  factory :ai_guardrail_config, class: "Ai::GuardrailConfig" do
    account
    agent { nil }
    sequence(:name) { |n| "Guardrail Config #{n}" }
    is_active { true }
    input_rails { [] }
    output_rails { [] }
    retrieval_rails { [] }
    configuration { {} }
    max_input_tokens { 100_000 }
    max_output_tokens { 50_000 }
    toxicity_threshold { 0.7 }
    pii_sensitivity { 0.8 }
    block_on_failure { false }
    total_checks { 0 }
    total_blocks { 0 }

    trait :active do
      is_active { true }
    end

    trait :inactive do
      is_active { false }
    end

    trait :global do
      agent { nil }
    end

    trait :with_agent do
      association :agent, factory: :ai_agent
    end

    trait :strict do
      toxicity_threshold { 0.3 }
      pii_sensitivity { 0.95 }
      block_on_failure { true }
      max_input_tokens { 50_000 }
      max_output_tokens { 25_000 }
      input_rails do
        [
          { "type" => "toxicity_check", "threshold" => 0.3 },
          { "type" => "pii_detection", "sensitivity" => 0.95, "action" => "block" },
          { "type" => "prompt_injection_check", "enabled" => true }
        ]
      end
      output_rails do
        [
          { "type" => "toxicity_check", "threshold" => 0.3 },
          { "type" => "factuality_check", "enabled" => true },
          { "type" => "pii_detection", "sensitivity" => 0.95, "action" => "redact" }
        ]
      end
    end

    trait :permissive do
      toxicity_threshold { 0.9 }
      pii_sensitivity { 0.5 }
      block_on_failure { false }
      max_input_tokens { 200_000 }
      max_output_tokens { 100_000 }
      input_rails do
        [
          { "type" => "toxicity_check", "threshold" => 0.9 }
        ]
      end
      output_rails { [] }
    end

    trait :with_input_rails do
      input_rails do
        [
          { "type" => "toxicity_check", "threshold" => 0.7 },
          { "type" => "pii_detection", "sensitivity" => 0.8, "action" => "warn" },
          { "type" => "token_limit_check", "max_tokens" => 100_000 }
        ]
      end
    end

    trait :with_output_rails do
      output_rails do
        [
          { "type" => "toxicity_check", "threshold" => 0.7 },
          { "type" => "pii_detection", "sensitivity" => 0.8, "action" => "redact" },
          { "type" => "hallucination_check", "enabled" => true }
        ]
      end
    end

    trait :with_retrieval_rails do
      retrieval_rails do
        [
          { "type" => "relevance_check", "min_score" => 0.6 },
          { "type" => "source_verification", "enabled" => true },
          { "type" => "data_classification_check", "max_level" => "confidential" }
        ]
      end
    end

    trait :with_all_rails do
      with_input_rails
      with_output_rails
      with_retrieval_rails
    end

    trait :block_on_failure do
      block_on_failure { true }
    end

    trait :with_usage_stats do
      total_checks { rand(100..10000) }
      total_blocks { rand(5..500) }
    end

    trait :high_block_rate do
      total_checks { 1000 }
      total_blocks { 250 }
    end

    trait :with_configuration do
      configuration do
        {
          "log_level" => "verbose",
          "fallback_action" => "warn",
          "custom_rules" => [
            { "name" => "no_code_execution", "enabled" => true },
            { "name" => "no_external_urls", "enabled" => false }
          ],
          "notification_webhook" => "https://hooks.example.com/guardrails"
        }
      end
    end
  end
end
