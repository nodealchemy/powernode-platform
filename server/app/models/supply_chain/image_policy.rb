# frozen_string_literal: true

module SupplyChain
  class ImagePolicy < ApplicationRecord
    include Auditable

    self.table_name = "supply_chain_image_policies"

    # ============================================
    # Constants
    # ============================================
    POLICY_TYPES = %w[registry_allowlist signature_required vulnerability_threshold custom].freeze
    ENFORCEMENT_LEVELS = %w[log warn block].freeze

    # ============================================
    # Associations
    # ============================================
    belongs_to :account
    belongs_to :created_by, class_name: "User", optional: true

    # ============================================
    # Validations
    # ============================================
    validates :name, presence: true, uniqueness: { scope: :account_id }
    validates :policy_type, presence: true, inclusion: { in: POLICY_TYPES }
    validates :enforcement_level, presence: true, inclusion: { in: ENFORCEMENT_LEVELS }
    validates :priority, numericality: { greater_than_or_equal_to: 0 }
    validates :max_critical_vulns, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
    validates :max_high_vulns, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

    # ============================================
    # Scopes
    # ============================================
    scope :active, -> { where(is_active: true) }
    scope :inactive, -> { where(is_active: false) }
    scope :by_type, ->(type) { where(policy_type: type) }
    scope :blocking, -> { where(enforcement_level: "block") }
    scope :warning, -> { where(enforcement_level: "warn") }
    scope :ordered, -> { order(priority: :desc, created_at: :asc) }
    scope :signature_policies, -> { where(policy_type: "signature_required") }
    scope :vuln_policies, -> { where(policy_type: "vulnerability_threshold") }

    # ============================================
    # Callbacks
    # ============================================
    before_save :sanitize_jsonb_fields

    # ============================================
    # Instance Methods
    # ============================================
    def active?
      is_active
    end

    def blocking?
      enforcement_level == "block"
    end

    def warning?
      enforcement_level == "warn"
    end

    def logging?
      enforcement_level == "log"
    end

    def registry_allowlist?
      policy_type == "registry_allowlist"
    end

    def signature_required?
      policy_type == "signature_required"
    end

    def vulnerability_threshold?
      policy_type == "vulnerability_threshold"
    end

    def custom?
      policy_type == "custom"
    end

    def activate!
      update!(is_active: true)
    end

    def deactivate!
      update!(is_active: false)
    end

    def evaluate(image)
      result = {
        policy_id: id,
        policy_name: name,
        policy_type: policy_type,
        enforcement_level: enforcement_level,
        passed: true,
        violations: []
      }

      # Check if policy applies to this image
      return result.merge(skipped: true, reason: "Policy does not match image") unless matches_image?(image)

      case policy_type
      when "registry_allowlist"
        evaluate_registry_allowlist(image, result)
      when "signature_required"
        evaluate_signature_required(image, result)
      when "vulnerability_threshold"
        evaluate_vulnerability_threshold(image, result)
      when "custom"
        evaluate_custom_rules(image, result)
      end

      result
    end

    def matches_image?(image)
      return true if match_rules.blank?

      rules = match_rules.with_indifferent_access

      # Check registry match
      if rules[:registries].present?
        return false unless rules[:registries].any? { |r| image.registry.match?(r) }
      end

      # Check repository match
      if rules[:repositories].present?
        return false unless rules[:repositories].any? { |r| image.repository.match?(r) }
      end

      # Check tag match
      if rules[:tags].present?
        return false unless image.tag.present? && rules[:tags].any? { |t| image.tag.match?(t) }
      end

      # Check label match
      if rules[:labels].present?
        rules[:labels].each do |key, value|
          return false unless image.labels[key] == value
        end
      end

      true
    end

    def summary
      {
        id: id,
        name: name,
        description: description,
        policy_type: policy_type,
        enforcement_level: enforcement_level,
        is_active: is_active,
        priority: priority,
        require_signature: require_signature,
        require_sbom: require_sbom,
        max_critical_vulns: max_critical_vulns,
        max_high_vulns: max_high_vulns,
        created_at: created_at
      }
    end

    private

    def sanitize_jsonb_fields
      self.match_rules ||= {}
      self.rules ||= {}
      self.metadata ||= {}
    end

    def evaluate_registry_allowlist(image, result)
      allowed = rules.dig("allowed_registries") || []
      denied = rules.dig("denied_registries") || []

      if denied.any? { |d| image.registry.match?(d) }
        result[:passed] = false
        result[:violations] << {
          type: "denied_registry",
          message: "Registry '#{image.registry}' is explicitly denied"
        }
      elsif allowed.present? && allowed.none? { |a| image.registry.match?(a) }
        result[:passed] = false
        result[:violations] << {
          type: "registry_not_allowed",
          message: "Registry '#{image.registry}' is not in the allowlist"
        }
      end
    end

    def evaluate_signature_required(image, result)
      return unless require_signature

      unless image.signed?
        result[:passed] = false
        result[:violations] << {
          type: "signature_missing",
          message: "Image is not signed"
        }
      end

      if require_sbom && image.sbom.nil?
        result[:passed] = false
        result[:violations] << {
          type: "sbom_missing",
          message: "Image does not have an associated SBOM"
        }
      end
    end

    def evaluate_vulnerability_threshold(image, result)
      if max_critical_vulns.present? && image.critical_vuln_count > max_critical_vulns
        result[:passed] = false
        result[:violations] << {
          type: "critical_vuln_exceeded",
          message: "Image has #{image.critical_vuln_count} critical vulnerabilities (max: #{max_critical_vulns})"
        }
      end

      if max_high_vulns.present? && image.high_vuln_count > max_high_vulns
        result[:passed] = false
        result[:violations] << {
          type: "high_vuln_exceeded",
          message: "Image has #{image.high_vuln_count} high vulnerabilities (max: #{max_high_vulns})"
        }
      end
    end

    def evaluate_custom_rules(image, result)
      custom_rules = rules.with_indifferent_access

      custom_rules.fetch(:checks, []).each do |check|
        case check[:type]
        when "label_required"
          unless image.labels[check[:key]].present?
            result[:passed] = false
            result[:violations] << {
              type: "label_missing",
              message: "Required label '#{check[:key]}' is missing"
            }
          end
        when "label_value"
          unless image.labels[check[:key]] == check[:value]
            result[:passed] = false
            result[:violations] << {
              type: "label_value_mismatch",
              message: "Label '#{check[:key]}' must have value '#{check[:value]}'"
            }
          end
        when "max_age_days"
          if image.pushed_at.present? && image.pushed_at < check[:days].to_i.days.ago
            result[:passed] = false
            result[:violations] << {
              type: "image_too_old",
              message: "Image is older than #{check[:days]} days"
            }
          end
        end
      end
    end
  end
end
