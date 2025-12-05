# frozen_string_literal: true

FactoryBot.define do
  factory :validation_rule do
    sequence(:name) { |n| "validation_rule_#{n}_#{SecureRandom.hex(3)}" }
    description { "Validation rule for testing purposes" }
    category { %w[structure connectivity data configuration performance security].sample }
    severity { 'warning' }
    enabled { true }
    auto_fixable { false }
    configuration do
      {
        check_interval: 300,
        enabled_for: ['workflows', 'nodes'],
        remediation_steps: [],
        fix_description: "Fix description for this validation rule",
        validation_logic: { check_type: 'generic' },
        metadata: { priority: 'medium' }
      }
    end

    trait :error_severity do
      severity { 'error' }
      auto_fixable { false }
    end

    trait :warning_severity do
      severity { 'warning' }
      auto_fixable { true }
    end

    trait :info_severity do
      severity { 'info' }
      auto_fixable { false }
    end

    trait :auto_fixable do
      auto_fixable { true }
      configuration do
        {
          check_interval: 300,
          auto_fix_enabled: true,
          fix_strategy: 'automatic',
          remediation_steps: [
            'Identify issue',
            'Apply fix',
            'Verify resolution'
          ]
        }
      end
    end

    trait :structure_validation do
      category { 'structure' }
      name { 'missing_start_node_validation' }
      description { 'Validates that workflow has at least one start node' }
      severity { 'error' }
      auto_fixable { false }
    end

    # Alias for structure_validation (commonly used in tests)
    trait :structure_error do
      category { 'structure' }
      sequence(:name) { |n| "structure_error_validation_#{n}" }
      description { 'Detects structural errors in workflow' }
      severity { 'error' }
      auto_fixable { false }
      configuration do
        {
          check_interval: 300,
          enabled_for: ['workflows'],
          fix_description: 'Fix workflow structure to resolve this error',
          validation_logic: { check_type: 'structure', min_nodes: 1 },
          metadata: { priority: 'high', category: 'structure' }
        }
      end
    end

    trait :connectivity_validation do
      category { 'connectivity' }
      name { 'orphaned_nodes_validation' }
      description { 'Checks for nodes not connected to the workflow' }
      severity { 'warning' }
      auto_fixable { true }
    end

    # Alias for connectivity_validation (commonly used in tests)
    trait :connectivity_warning do
      category { 'connectivity' }
      sequence(:name) { |n| "connectivity_warning_validation_#{n}" }
      description { 'Detects connectivity warnings in workflow' }
      severity { 'warning' }
      auto_fixable { true }
      configuration do
        {
          check_interval: 300,
          enabled_for: ['workflows', 'nodes'],
          fix_description: 'Fix connectivity issues',
          validation_logic: { check_type: 'connectivity' },
          metadata: { priority: 'medium', category: 'connectivity' }
        }
      end
    end

    trait :data_validation do
      category { 'data' }
      name { 'required_fields_validation' }
      description { 'Ensures all required fields are present' }
      severity { 'error' }
      auto_fixable { false }
    end

    trait :configuration_validation do
      category { 'configuration' }
      name { 'invalid_config_validation' }
      description { 'Validates configuration format and values' }
      severity { 'warning' }
      auto_fixable { true }
    end

    trait :performance_validation do
      category { 'performance' }
      name { 'timeout_threshold_validation' }
      description { 'Checks if timeout settings are reasonable' }
      severity { 'info' }
      auto_fixable { false }
    end

    trait :security_validation do
      category { 'security' }
      name { 'credential_exposure_validation' }
      description { 'Detects exposed credentials in configuration' }
      severity { 'error' }
      auto_fixable { false }
    end

    trait :disabled do
      enabled { false }
    end
  end
end
