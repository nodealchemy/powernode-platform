# frozen_string_literal: true

FactoryBot.define do
  factory :ai_security_audit_trail, class: "Ai::SecurityAuditTrail" do
    account
    action { "privilege_check" }
    outcome { "allowed" }
    asi_reference { "ASI05" }
    csa_pillar { "behavior" }
    severity { "info" }
    source_service { "PrivilegeEnforcementService" }
    context { {} }
    details { {} }

    trait :denied do
      outcome { "denied" }
      severity { "warning" }
    end

    trait :blocked do
      outcome { "blocked" }
      severity { "critical" }
    end

    trait :quarantined do
      outcome { "quarantined" }
      severity { "critical" }
    end

    trait :escalated do
      outcome { "escalated" }
      severity { "warning" }
    end

    trait :identity do
      asi_reference { "ASI03" }
      csa_pillar { "identity" }
      source_service { "AgentIdentityService" }
    end

    trait :communication do
      asi_reference { "ASI07" }
      csa_pillar { "segmentation" }
      source_service { "EncryptedCommunicationService" }
    end

    trait :incident_response do
      asi_reference { "ASI08" }
      csa_pillar { "incident_response" }
      source_service { "QuarantineService" }
    end

    trait :with_agent do
      agent_id { SecureRandom.uuid }
    end

    trait :with_user do
      user_id { SecureRandom.uuid }
    end

    trait :high_risk do
      risk_score { 0.85 }
      severity { "critical" }
    end
  end
end
