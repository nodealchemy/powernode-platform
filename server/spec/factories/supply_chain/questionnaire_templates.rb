# frozen_string_literal: true

FactoryBot.define do
  factory :supply_chain_questionnaire_template, class: "SupplyChain::QuestionnaireTemplate" do
    association :account
    created_by { nil }
    sequence(:name) { |n| "Security Assessment Template #{n}" }
    description { "Comprehensive security assessment questionnaire" }
    template_type { "soc2" }
    version { "1.0" }
    is_system { false }
    is_active { true }
    sections do
      [
        { id: "section1", name: "General Security", description: "General security controls", weight: 1.0, order: 0 },
        { id: "section2", name: "Access Control", description: "Access management", weight: 1.5, order: 1 }
      ]
    end
    questions do
      [
        { id: "q1", section_id: "section1", text: "Do you have a security policy?", type: "yes_no", required: true, order: 0 },
        { id: "q2", section_id: "section1", text: "Describe your security practices.", type: "text", required: false, order: 1 },
        { id: "q3", section_id: "section2", text: "Do you use MFA?", type: "yes_no", required: true, order: 0 }
      ]
    end
    metadata { {} }

    trait :soc2 do
      template_type { "soc2" }
      name { "SOC 2 Type II Security Assessment" }
      description { "Standard SOC 2 Type II security questionnaire covering Trust Service Criteria" }
      sections do
        [
          { id: "cc1", name: "Control Environment", description: "Organization and management", weight: 1.0, order: 0 },
          { id: "cc2", name: "Communication and Information", description: "Information systems", weight: 1.0, order: 1 },
          { id: "cc3", name: "Risk Assessment", description: "Risk identification and management", weight: 1.0, order: 2 },
          { id: "cc6", name: "Logical and Physical Access", description: "Access controls", weight: 1.5, order: 3 },
          { id: "cc7", name: "System Operations", description: "System monitoring and incident response", weight: 1.5, order: 4 }
        ]
      end
    end

    trait :iso27001 do
      template_type { "iso27001" }
      name { "ISO 27001 Security Assessment" }
      description { "ISO 27001 information security management system assessment" }
      sections do
        [
          { id: "a5", name: "Information Security Policies", weight: 1.0, order: 0 },
          { id: "a6", name: "Organization of Information Security", weight: 1.0, order: 1 },
          { id: "a9", name: "Access Control", weight: 1.5, order: 2 },
          { id: "a12", name: "Operations Security", weight: 1.5, order: 3 }
        ]
      end
    end

    trait :gdpr do
      template_type { "gdpr" }
      name { "GDPR Compliance Assessment" }
      description { "General Data Protection Regulation compliance questionnaire" }
    end

    trait :hipaa do
      template_type { "hipaa" }
      name { "HIPAA Security Assessment" }
      description { "Health Insurance Portability and Accountability Act compliance questionnaire" }
    end

    trait :pci_dss do
      template_type { "pci_dss" }
      name { "PCI DSS Compliance Assessment" }
      description { "Payment Card Industry Data Security Standard compliance questionnaire" }
    end

    trait :custom do
      template_type { "custom" }
      sequence(:name) { |n| "Custom Assessment #{n}" }
      description { "Custom security assessment questionnaire" }
    end

    trait :system_template do
      is_system { true }
      account { nil }
    end

    trait :inactive do
      is_active { false }
    end

    trait :with_many_questions do
      questions do
        Array.new(20) do |i|
          section_id = i < 10 ? "section1" : "section2"
          {
            id: "q#{i + 1}",
            section_id: section_id,
            text: "Security question #{i + 1}?",
            type: %w[yes_no text scale choice].sample,
            required: i.even?,
            order: i % 10
          }
        end
      end
    end

    trait :empty do
      sections { [] }
      questions { [] }
    end

    trait :with_created_by do
      association :created_by, factory: :user
    end
  end
end
