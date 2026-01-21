# frozen_string_literal: true

module SupplyChain
  class VendorRiskService
    class RiskError < StandardError; end

    RISK_CATEGORIES = {
      security: {
        weight: 0.40,
        factors: %w[encryption access_control incident_response vulnerability_management]
      },
      compliance: {
        weight: 0.35,
        factors: %w[certifications data_handling privacy regulatory]
      },
      operational: {
        weight: 0.25,
        factors: %w[availability support financial_stability business_continuity]
      }
    }.freeze

    attr_reader :account, :vendor, :options

    def initialize(account:, vendor:, options: {})
      @account = account
      @vendor = vendor
      @options = options.with_indifferent_access
      @logger = Rails.logger
    end

    def assess!
      assessment = create_assessment

      begin
        assessment.start!

        # Calculate scores for each category
        scores = calculate_category_scores(assessment)

        # Add findings
        findings = generate_findings(scores)
        findings.each { |f| assessment.add_finding(**f) }

        # Add recommendations
        recommendations = generate_recommendations(scores, findings)
        recommendations.each { |r| assessment.add_recommendation(**r) }

        assessment.update!(
          security_score: scores[:security],
          compliance_score: scores[:compliance],
          operational_score: scores[:operational],
          summary: generate_summary(scores, findings)
        )

        assessment.complete!

        assessment
      rescue StandardError => e
        @logger.error "[VendorRiskService] Assessment failed: #{e.message}"
        raise RiskError, "Risk assessment failed: #{e.message}"
      end
    end

    def reassess!
      # Create a periodic reassessment
      @options[:assessment_type] = "periodic"
      assess!
    end

    def calculate_inherent_risk
      # Calculate inherent risk based on vendor characteristics
      risk_factors = {
        data_sensitivity: calculate_data_sensitivity_risk,
        criticality: calculate_criticality_risk,
        accessibility: calculate_accessibility_risk
      }

      weighted_score = (
        (risk_factors[:data_sensitivity] * 0.4) +
        (risk_factors[:criticality] * 0.35) +
        (risk_factors[:accessibility] * 0.25)
      )

      {
        score: weighted_score.round(2),
        tier: score_to_tier(weighted_score),
        factors: risk_factors
      }
    end

    def monitor_vendor!
      # Check for monitoring events
      events = []

      # Check certification expiry
      vendor.certifications.each do |cert|
        next unless cert["expires_at"].present?

        expires_at = Time.parse(cert["expires_at"])
        if expires_at < 30.days.from_now
          events << create_certification_expiry_event(cert, expires_at)
        end
      end

      # Check contract renewal
      if vendor.contract_end_date.present? && vendor.contract_end_date < 60.days.from_now
        events << create_contract_renewal_event
      end

      # Check for overdue assessment
      if vendor.needs_assessment?
        events << create_assessment_due_event
      end

      events
    end

    private

    def create_assessment
      SupplyChain::RiskAssessment.create!(
        vendor: vendor,
        account: account,
        assessment_type: options[:assessment_type] || "initial",
        status: "draft",
        assessor: options[:user],
        assessment_date: Time.current
      )
    end

    def calculate_category_scores(assessment)
      questionnaire = get_latest_questionnaire

      {
        security: calculate_security_score(questionnaire),
        compliance: calculate_compliance_score(questionnaire),
        operational: calculate_operational_score(questionnaire)
      }
    end

    def calculate_security_score(questionnaire)
      base_score = 100

      # Deduct for missing security controls
      base_score -= 20 unless has_encryption?
      base_score -= 15 unless has_mfa?
      base_score -= 10 unless has_incident_response?
      base_score -= 15 unless has_vulnerability_program?
      base_score -= 10 unless has_security_training?

      # Add points for certifications
      base_score += 10 if vendor.soc2_certified?
      base_score += 5 if vendor.iso27001_certified?

      # Questionnaire-based adjustments
      if questionnaire.present? && questionnaire.section_scores.present?
        security_sections = %w[cc5 cc6 cc7 a9 a12]
        avg_score = security_sections
                      .map { |s| questionnaire.section_scores[s] }
                      .compact
                      .sum / [security_sections.length, 1].max

        base_score = (base_score * 0.5 + avg_score * 0.5).round(2)
      end

      [[base_score, 0].max, 100].min.round(2)
    end

    def calculate_compliance_score(questionnaire)
      base_score = 100

      # Data handling compliance
      base_score -= 20 if vendor.handles_pii && !vendor.has_dpa
      base_score -= 20 if vendor.handles_phi && !vendor.has_baa
      base_score -= 15 if vendor.handles_pci && !vendor.has_certification?("PCI DSS")

      # Certifications
      base_score += 15 if vendor.soc2_certified?
      base_score += 10 if vendor.iso27001_certified?
      base_score += 10 if vendor.has_certification?("GDPR")
      base_score += 10 if vendor.has_certification?("HIPAA")

      # Questionnaire-based adjustments
      if questionnaire.present? && questionnaire.section_scores.present?
        compliance_sections = %w[a18 cc1 cc2]
        scores = compliance_sections.map { |s| questionnaire.section_scores[s] }.compact
        if scores.any?
          avg_score = scores.sum / scores.length
          base_score = (base_score * 0.6 + avg_score * 0.4).round(2)
        end
      end

      [[base_score, 0].max, 100].min.round(2)
    end

    def calculate_operational_score(questionnaire)
      base_score = 100

      # Business continuity
      base_score -= 15 unless has_business_continuity?
      base_score -= 10 unless has_disaster_recovery?

      # Support and SLA
      base_score -= 10 unless has_sla?
      base_score -= 5 unless has_dedicated_support?

      # Financial stability (simplified check)
      base_score -= 10 if vendor.vendor_type == "saas" && !vendor.has_certification?("SOC 2 Type II")

      # Questionnaire-based adjustments
      if questionnaire.present? && questionnaire.section_scores.present?
        operational_sections = %w[cc9 a17]
        scores = operational_sections.map { |s| questionnaire.section_scores[s] }.compact
        if scores.any?
          avg_score = scores.sum / scores.length
          base_score = (base_score * 0.6 + avg_score * 0.4).round(2)
        end
      end

      [[base_score, 0].max, 100].min.round(2)
    end

    def generate_findings(scores)
      findings = []

      # Security findings
      if scores[:security] < 60
        findings << {
          title: "Critical security gaps identified",
          severity: "critical",
          description: "Multiple security control deficiencies were identified",
          category: "security"
        }
      elsif scores[:security] < 80
        findings << {
          title: "Security improvements needed",
          severity: "high",
          description: "Some security controls need strengthening",
          category: "security"
        }
      end

      # Compliance findings
      if vendor.handles_pii && !vendor.has_dpa
        findings << {
          title: "Missing Data Processing Agreement",
          severity: "high",
          description: "Vendor handles PII but no DPA is in place",
          category: "compliance",
          remediation: "Request and execute DPA with vendor"
        }
      end

      if vendor.handles_phi && !vendor.has_baa
        findings << {
          title: "Missing Business Associate Agreement",
          severity: "critical",
          description: "Vendor handles PHI but no BAA is in place",
          category: "compliance",
          remediation: "Execute BAA immediately or cease PHI sharing"
        }
      end

      # Certification findings
      unless vendor.soc2_certified?
        findings << {
          title: "No SOC 2 certification",
          severity: "medium",
          description: "Vendor does not have SOC 2 Type II certification",
          category: "compliance"
        }
      end

      findings
    end

    def generate_recommendations(scores, findings)
      recommendations = []

      # Based on scores
      if scores[:security] < 80
        recommendations << {
          title: "Request security assessment documentation",
          priority: "high",
          description: "Obtain detailed security controls documentation from vendor"
        }
      end

      if scores[:compliance] < 70
        recommendations << {
          title: "Review compliance posture",
          priority: "high",
          description: "Schedule compliance review meeting with vendor"
        }
      end

      # Based on findings
      if findings.any? { |f| f[:severity] == "critical" }
        recommendations << {
          title: "Immediate risk mitigation required",
          priority: "critical",
          description: "Address critical findings before continuing vendor relationship"
        }
      end

      # Based on vendor characteristics
      if vendor.handles_sensitive_data? && !vendor.soc2_certified?
        recommendations << {
          title: "Request SOC 2 Type II report",
          priority: "high",
          description: "Require vendor to complete SOC 2 certification"
        }
      end

      recommendations
    end

    def generate_summary(scores, findings)
      critical_count = findings.count { |f| f[:severity] == "critical" }
      high_count = findings.count { |f| f[:severity] == "high" }

      "Risk assessment completed with overall score of #{calculate_overall_score(scores).round(1)}. " \
      "#{critical_count} critical and #{high_count} high severity findings identified. " \
      "Security: #{scores[:security]}%, Compliance: #{scores[:compliance]}%, Operational: #{scores[:operational]}%"
    end

    def calculate_overall_score(scores)
      (scores[:security] * RISK_CATEGORIES[:security][:weight]) +
        (scores[:compliance] * RISK_CATEGORIES[:compliance][:weight]) +
        (scores[:operational] * RISK_CATEGORIES[:operational][:weight])
    end

    def calculate_data_sensitivity_risk
      risk = 30 # Base risk

      risk += 30 if vendor.handles_pii
      risk += 40 if vendor.handles_phi
      risk += 30 if vendor.handles_pci

      [risk, 100].min
    end

    def calculate_criticality_risk
      case vendor.vendor_type
      when "infrastructure" then 80
      when "saas" then 60
      when "api" then 50
      when "library" then 40
      else 30
      end
    end

    def calculate_accessibility_risk
      # Risk based on how accessible the vendor's systems are
      50 # Default medium risk
    end

    def score_to_tier(score)
      case score
      when 80..100 then "critical"
      when 60...80 then "high"
      when 30...60 then "medium"
      else "low"
      end
    end

    def get_latest_questionnaire
      vendor.questionnaire_responses.reviewed.order(reviewed_at: :desc).first
    end

    def has_encryption?
      vendor.certifications.any? { |c| c["name"]&.include?("SOC") || c["name"]&.include?("ISO") }
    end

    def has_mfa?
      vendor.metadata&.dig("security_controls", "mfa") == true
    end

    def has_incident_response?
      vendor.metadata&.dig("security_controls", "incident_response") == true
    end

    def has_vulnerability_program?
      vendor.metadata&.dig("security_controls", "vulnerability_management") == true
    end

    def has_security_training?
      vendor.metadata&.dig("security_controls", "security_training") == true
    end

    def has_business_continuity?
      vendor.metadata&.dig("operational", "business_continuity") == true
    end

    def has_disaster_recovery?
      vendor.metadata&.dig("operational", "disaster_recovery") == true
    end

    def has_sla?
      vendor.metadata&.dig("operational", "sla") == true
    end

    def has_dedicated_support?
      vendor.metadata&.dig("operational", "dedicated_support") == true
    end

    def create_certification_expiry_event(cert, expires_at)
      SupplyChain::VendorMonitoringEvent.create_certification_expiry(
        vendor: vendor,
        account: account,
        certification_name: cert["name"],
        expires_at: expires_at
      )
    end

    def create_contract_renewal_event
      SupplyChain::VendorMonitoringEvent.create_contract_renewal(
        vendor: vendor,
        account: account,
        renewal_date: vendor.contract_end_date
      )
    end

    def create_assessment_due_event
      SupplyChain::VendorMonitoringEvent.create!(
        vendor: vendor,
        account: account,
        event_type: "compliance_update",
        severity: "medium",
        source: "automated",
        title: "Risk assessment overdue",
        description: "Vendor #{vendor.name} requires a new risk assessment",
        recommended_actions: [
          {
            id: SecureRandom.uuid,
            action: "Schedule and complete vendor risk assessment",
            priority: "high",
            status: "pending",
            added_at: Time.current.iso8601
          }
        ]
      )
    end
  end
end
