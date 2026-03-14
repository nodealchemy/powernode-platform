# frozen_string_literal: true

FactoryBot.define do
  factory :supply_chain_scan_template, class: "SupplyChain::ScanTemplate" do
    account { nil }
    created_by { nil }
    sequence(:name) { |n| "Security Scan Template #{n}" }
    sequence(:slug) { |n| "security-scan-template-#{n}-#{SecureRandom.hex(4)}" }
    description { "Automated security scanning template for vulnerability detection" }
    category { "security" }
    status { "published" }
    version { "1.0.0" }
    is_system { false }
    is_public { true }
    supported_ecosystems { %w[npm gem pip] }
    average_rating { 4.5 }
    install_count { 0 }
    configuration_schema do
      {
        type: "object",
        properties: {
          severity_threshold: { type: "string", enum: %w[critical high medium low] },
          scan_depth: { type: "integer" },
          ignore_dev_dependencies: { type: "boolean" }
        },
        required: %w[severity_threshold]
      }
    end
    default_configuration do
      {
        severity_threshold: "high",
        scan_depth: 3,
        ignore_dev_dependencies: false
      }
    end
    metadata { {} }

    trait :security do
      category { "security" }
      name { "Security Vulnerability Scanner" }
      description { "Scans for known security vulnerabilities in dependencies" }
    end

    trait :compliance do
      category { "compliance" }
      name { "Compliance Checker" }
      description { "Checks for compliance with security standards" }
    end

    trait :license do
      category { "license" }
      name { "License Scanner" }
      description { "Scans and identifies licenses in dependencies" }
    end

    trait :quality do
      category { "quality" }
      name { "Code Quality Scanner" }
      description { "Analyzes code quality and best practices" }
    end

    trait :custom do
      category { "custom" }
      sequence(:name) { |n| "Custom Scanner #{n}" }
      description { "Custom scanning template" }
    end

    trait :draft do
      status { "draft" }
      is_public { false }
    end

    trait :published do
      status { "published" }
      is_public { true }
    end

    trait :archived do
      status { "archived" }
    end

    trait :deprecated do
      status { "deprecated" }
    end

    trait :system_template do
      is_system { true }
      account { nil }
    end

    trait :private_template do
      is_public { false }
    end

    trait :popular do
      install_count { rand(500..2000) }
      average_rating { rand(4.0..5.0).round(1) }
    end

    trait :top_rated do
      average_rating { rand(4.5..5.0).round(1) }
    end

    trait :npm_only do
      supported_ecosystems { %w[npm] }
    end

    trait :multi_ecosystem do
      supported_ecosystems { %w[npm gem pip maven go cargo] }
    end

    trait :with_complex_schema do
      configuration_schema do
        {
          type: "object",
          properties: {
            severity_threshold: {
              type: "string",
              enum: %w[critical high medium low],
              description: "Minimum severity level to report"
            },
            scan_depth: {
              type: "integer",
              minimum: 1,
              maximum: 10,
              description: "Depth of dependency tree to scan"
            },
            ignore_dev_dependencies: {
              type: "boolean",
              description: "Whether to skip dev dependencies"
            },
            exclude_patterns: {
              type: "array",
              items: { type: "string" },
              description: "Patterns to exclude from scanning"
            },
            notification_channels: {
              type: "array",
              items: {
                type: "object",
                properties: {
                  type: { type: "string", enum: %w[email slack webhook] },
                  config: { type: "object" }
                }
              }
            }
          },
          required: %w[severity_threshold]
        }
      end
    end

    trait :marketplace_ready do
      is_public { true }
      status { "published" }
      install_count { rand(100..500) }
      average_rating { rand(3.5..5.0).round(1) }
      description { "Production-ready scanning template with comprehensive vulnerability detection" }
    end

    trait :with_account do
      association :account
    end

    trait :with_created_by do
      association :created_by, factory: :user
    end
  end
end
