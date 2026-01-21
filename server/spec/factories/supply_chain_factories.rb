# frozen_string_literal: true

FactoryBot.define do
  # SBOM
  factory :supply_chain_sbom, class: "SupplyChain::Sbom" do
    association :account
    name { "#{Faker::App.name} SBOM" }
    sbom_id { "urn:uuid:#{SecureRandom.uuid}" }
    format { "cyclonedx_1_5" }
    version { Faker::App.semantic_version }
    status { "active" }
    component_count { rand(10..100) }
    vulnerability_count { rand(0..20) }
    risk_score { rand(0..100) }
    ntia_minimum_compliant { [true, false].sample }
    document { { bomFormat: "CycloneDX", specVersion: "1.5", components: [] } }

    trait :with_components do
      after(:create) do |sbom|
        create_list(:supply_chain_sbom_component, 5, sbom: sbom)
      end
    end

    trait :with_vulnerabilities do
      after(:create) do |sbom|
        create_list(:supply_chain_sbom_vulnerability, 3, sbom: sbom)
      end
    end
  end

  # SBOM Component
  factory :supply_chain_sbom_component, class: "SupplyChain::SbomComponent" do
    association :sbom, factory: :supply_chain_sbom
    purl { "pkg:npm/#{Faker::Internet.slug}@#{Faker::App.semantic_version}" }
    name { Faker::Internet.slug }
    version { Faker::App.semantic_version }
    ecosystem { %w[npm gem pip maven go cargo].sample }
    dependency_type { %w[direct transitive dev].sample }
    depth { rand(0..5) }
    risk_score { rand(0..100) }
    has_known_vulnerabilities { [true, false].sample }
  end

  # SBOM Vulnerability
  factory :supply_chain_sbom_vulnerability, class: "SupplyChain::SbomVulnerability" do
    association :sbom, factory: :supply_chain_sbom
    association :component, factory: :supply_chain_sbom_component
    vulnerability_id { "CVE-#{rand(2020..2024)}-#{rand(1000..99999)}" }
    severity { %w[critical high medium low].sample }
    cvss_score { rand(0.0..10.0).round(1) }
    cvss_vector { "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H" }
    remediation_status { %w[open in_progress fixed wont_fix].sample }
    fixed_version { Faker::App.semantic_version }
  end

  # License
  factory :supply_chain_license, class: "SupplyChain::License" do
    spdx_id { "#{%w[MIT Apache BSD GPL LGPL MPL].sample}-#{rand(1..3)}.0" }
    name { "#{Faker::Hacker.adjective.capitalize} License" }
    category { %w[permissive copyleft weak_copyleft public_domain proprietary unknown].sample }
    is_copyleft { category == "copyleft" || category == "weak_copyleft" }
    is_strong_copyleft { category == "copyleft" }
    is_network_copyleft { false }
    is_osi_approved { [true, false].sample }
    is_deprecated { false }

    trait :permissive do
      spdx_id { "MIT" }
      name { "MIT License" }
      category { "permissive" }
      is_copyleft { false }
      is_strong_copyleft { false }
    end

    trait :copyleft do
      spdx_id { "GPL-3.0-only" }
      name { "GNU General Public License v3.0" }
      category { "copyleft" }
      is_copyleft { true }
      is_strong_copyleft { true }
    end

    trait :network_copyleft do
      spdx_id { "AGPL-3.0-only" }
      name { "GNU Affero General Public License v3.0" }
      category { "copyleft" }
      is_copyleft { true }
      is_strong_copyleft { true }
      is_network_copyleft { true }
    end
  end

  # Vendor
  factory :supply_chain_vendor, class: "SupplyChain::Vendor" do
    association :account
    name { Faker::Company.name }
    vendor_type { %w[saas api library infrastructure hardware consulting].sample }
    risk_tier { %w[critical high medium low].sample }
    risk_score { rand(0..100) }
    status { "active" }
    handles_pii { [true, false].sample }
    handles_phi { false }
    handles_pci { [true, false].sample }
    certifications { [%w[SOC2 ISO27001 GDPR HIPAA PCI-DSS].sample(rand(0..3))] }
    contact_name { Faker::Name.name }
    contact_email { Faker::Internet.email }
    website { Faker::Internet.url }

    trait :critical do
      risk_tier { "critical" }
      handles_phi { true }
    end

    trait :low_risk do
      risk_tier { "low" }
      handles_pii { false }
      handles_phi { false }
      handles_pci { false }
    end
  end

  # Risk Assessment
  factory :supply_chain_risk_assessment, class: "SupplyChain::RiskAssessment" do
    association :vendor, factory: :supply_chain_vendor
    assessment_type { %w[initial periodic ad_hoc].sample }
    status { "completed" }
    assessment_date { rand(1..30).days.ago }
    completed_at { assessment_date + rand(1..7).days }
    security_score { rand(50..100) }
    compliance_score { rand(50..100) }
    operational_score { rand(50..100) }
    overall_score { (security_score + compliance_score + operational_score) / 3 }
    findings { [] }
    recommendations { [] }
  end

  # Attestation
  factory :supply_chain_attestation, class: "SupplyChain::Attestation" do
    association :account
    attestation_id { "urn:uuid:#{SecureRandom.uuid}" }
    attestation_type { "slsa_provenance" }
    slsa_level { [1, 2, 3].sample }
    subject_name { "app:#{Faker::App.name.downcase}" }
    subject_digest { "sha256:#{SecureRandom.hex(32)}" }
    predicate_type { "https://slsa.dev/provenance/v1" }
    predicate { { builder: { id: "https://github.com/actions/runner" } } }
    verification_status { "pending" }

    trait :signed do
      signature { Base64.encode64(SecureRandom.random_bytes(256)) }
      signature_algorithm { "ECDSA-P256" }
    end

    trait :verified do
      signature { Base64.encode64(SecureRandom.random_bytes(256)) }
      verification_status { "verified" }
    end

    trait :logged_to_rekor do
      rekor_log_id { SecureRandom.hex(32) }
      rekor_log_url { "https://rekor.sigstore.dev/api/v1/log/entries/#{rekor_log_id}" }
      rekor_logged_at { Time.current }
    end
  end

  # Container Image
  factory :supply_chain_container_image, class: "SupplyChain::ContainerImage" do
    association :account
    registry { %w[gcr.io docker.io ghcr.io].sample }
    repository { "#{Faker::Internet.slug}/#{Faker::App.name.downcase}" }
    tag { "v#{Faker::App.semantic_version}" }
    digest { "sha256:#{SecureRandom.hex(32)}" }
    status { "unverified" }
    critical_vuln_count { rand(0..5) }
    high_vuln_count { rand(0..10) }
    medium_vuln_count { rand(0..20) }
    low_vuln_count { rand(0..50) }
    is_deployed { [true, false].sample }
    layers { [] }

    trait :verified do
      status { "verified" }
    end

    trait :quarantined do
      status { "quarantined" }
      critical_vuln_count { rand(5..10) }
    end

    trait :clean do
      critical_vuln_count { 0 }
      high_vuln_count { 0 }
      medium_vuln_count { 0 }
      low_vuln_count { 0 }
    end
  end

  # Questionnaire Template
  factory :supply_chain_questionnaire_template, class: "SupplyChain::QuestionnaireTemplate" do
    name { "#{%w[SOC2 ISO27001 GDPR HIPAA].sample} Assessment" }
    description { Faker::Lorem.sentence }
    template_type { %w[soc2 iso27001 gdpr hipaa custom].sample }
    version { "1.0" }
    is_system { false }
    is_active { true }
    sections { [{ id: "section1", name: "General", weight: 1.0, order: 0 }] }
    questions { [{ id: "q1", section_id: "section1", text: "Sample question?", type: "yes_no", required: true }] }
  end

  # Questionnaire Response
  factory :supply_chain_questionnaire_response, class: "SupplyChain::QuestionnaireResponse" do
    association :vendor, factory: :supply_chain_vendor
    association :template, factory: :supply_chain_questionnaire_template
    status { "pending" }
    access_token { SecureRandom.urlsafe_base64(32) }
    sent_at { Time.current }
    due_at { 30.days.from_now }
    responses { {} }

    trait :submitted do
      status { "submitted" }
      submitted_at { Time.current }
      responses { { "q1" => "yes" } }
      overall_score { rand(60..100) }
    end

    trait :approved do
      status { "approved" }
      submitted_at { 1.week.ago }
      reviewed_at { Time.current }
      overall_score { rand(75..100) }
    end
  end

  # Scan Template
  factory :supply_chain_scan_template, class: "SupplyChain::ScanTemplate" do
    name { "#{Faker::Hacker.adjective.capitalize} Security Scan" }
    slug { name.downcase.gsub(/[^a-z0-9]+/, "-") }
    description { Faker::Lorem.paragraph }
    category { %w[security compliance license quality custom].sample }
    status { "published" }
    version { "1.0.0" }
    is_system { false }
    is_public { true }
    supported_ecosystems { %w[npm gem pip].sample(rand(1..3)) }
    average_rating { rand(3.5..5.0).round(1) }
    install_count { rand(0..1000) }
    configuration_schema { {} }
    default_configuration { {} }
  end

  # Scan Instance
  factory :supply_chain_scan_instance, class: "SupplyChain::ScanInstance" do
    association :account
    association :scan_template, factory: :supply_chain_scan_template
    name { "#{scan_template.name} Instance" }
    status { "active" }
    configuration { {} }
    is_active { true }
  end
end
