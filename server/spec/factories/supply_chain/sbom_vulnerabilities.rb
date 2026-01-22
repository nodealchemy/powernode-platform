# frozen_string_literal: true

FactoryBot.define do
  factory :supply_chain_sbom_vulnerability, class: "SupplyChain::SbomVulnerability" do
    association :sbom, factory: :supply_chain_sbom
    association :component, factory: :supply_chain_sbom_component
    association :account
    sequence(:vulnerability_id) { |n| "CVE-#{rand(2020..2025)}-#{10000 + n}" }
    source { "nvd" }
    severity { "high" }
    cvss_score { 7.5 }
    cvss_version { "3.1" }
    cvss_vector { "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H" }
    remediation_status { "open" }
    description { Faker::Lorem.paragraph }
    fixed_version { Faker::App.semantic_version }
    published_at { rand(30..365).days.ago }
    context_factors { {} }
    references { [] }
    metadata { {} }

    # ============================================
    # Severity Traits
    # ============================================
    trait :critical do
      severity { "critical" }
      cvss_score { rand(9.0..10.0).round(1) }
      cvss_vector { "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:C/C:H/I:H/A:H" }
    end

    trait :high do
      severity { "high" }
      cvss_score { rand(7.0..8.9).round(1) }
      cvss_vector { "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:N" }
    end

    trait :medium do
      severity { "medium" }
      cvss_score { rand(4.0..6.9).round(1) }
      cvss_vector { "CVSS:3.1/AV:N/AC:L/PR:L/UI:R/S:U/C:L/I:L/A:N" }
    end

    trait :low do
      severity { "low" }
      cvss_score { rand(0.1..3.9).round(1) }
      cvss_vector { "CVSS:3.1/AV:L/AC:H/PR:H/UI:R/S:U/C:L/I:N/A:N" }
    end

    trait :none do
      severity { "none" }
      cvss_score { 0.0 }
    end

    trait :unknown_severity do
      severity { "unknown" }
      cvss_score { nil }
      cvss_vector { nil }
    end

    # ============================================
    # Source Traits
    # ============================================
    trait :nvd do
      source { "nvd" }
      sequence(:vulnerability_id) { |n| "CVE-#{rand(2020..2025)}-#{10000 + n}" }
    end

    trait :osv do
      source { "osv" }
      sequence(:vulnerability_id) { |n| "GHSA-#{SecureRandom.hex(4)}-#{SecureRandom.hex(4)}-#{SecureRandom.hex(4)}" }
    end

    trait :github_advisory do
      source { "github_advisory" }
      sequence(:vulnerability_id) { |n| "GHSA-#{SecureRandom.hex(4)}-#{SecureRandom.hex(4)}-#{SecureRandom.hex(4)}" }
    end

    trait :snyk do
      source { "snyk" }
      sequence(:vulnerability_id) { |n| "SNYK-JS-#{Faker::Internet.slug.upcase.gsub('-', '')}-#{100000 + n}" }
    end

    trait :sonatype do
      source { "sonatype" }
      sequence(:vulnerability_id) { |n| "sonatype-#{rand(2020..2025)}-#{1000 + n}" }
    end

    trait :custom do
      source { "custom" }
      sequence(:vulnerability_id) { |n| "INTERNAL-#{rand(2020..2025)}-#{1000 + n}" }
    end

    # ============================================
    # Remediation Status Traits
    # ============================================
    trait :open do
      remediation_status { "open" }
    end

    trait :in_progress do
      remediation_status { "in_progress" }
    end

    trait :fixed do
      remediation_status { "fixed" }
    end

    trait :dismissed do
      remediation_status { "dismissed" }
      association :dismissed_by, factory: :user
      dismissed_at { Time.current }
      dismissal_reason { "Not applicable to our use case" }
    end

    trait :wont_fix do
      remediation_status { "wont_fix" }
      dismissal_reason { "Component will be removed in next release" }
    end

    # ============================================
    # Fix Availability Traits
    # ============================================
    trait :has_fix do
      fixed_version { Faker::App.semantic_version }
    end

    trait :no_fix do
      fixed_version { nil }
    end

    # ============================================
    # Context Factor Traits
    # ============================================
    trait :exploited_in_wild do
      context_factors do
        {
          "exploit_in_wild" => true,
          "poc_available" => true
        }
      end
      contextual_score { [cvss_score + 2.5, 10.0].min }
    end

    trait :poc_available do
      context_factors do
        {
          "poc_available" => true
        }
      end
    end

    trait :not_reachable do
      context_factors do
        {
          "not_reachable" => true
        }
      end
      contextual_score { [cvss_score - 1.0, 0.0].max }
    end

    trait :behind_auth do
      context_factors do
        {
          "behind_auth" => true
        }
      end
    end

    # ============================================
    # Age Traits
    # ============================================
    trait :recent do
      published_at { rand(1..14).days.ago }
    end

    trait :old do
      published_at { rand(365..730).days.ago }
    end

    # ============================================
    # References Traits
    # ============================================
    trait :with_references do
      references do
        [
          { "url" => "https://nvd.nist.gov/vuln/detail/#{vulnerability_id}", "type" => "advisory" },
          { "url" => "https://github.com/advisories/#{vulnerability_id}", "type" => "advisory" },
          { "url" => Faker::Internet.url, "type" => "patch" }
        ]
      end
    end

    # ============================================
    # Actionable Traits
    # ============================================
    trait :actionable do
      remediation_status { %w[open in_progress].sample }
    end

    trait :resolved do
      remediation_status { %w[fixed dismissed wont_fix].sample }
    end
  end
end
