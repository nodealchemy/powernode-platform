# frozen_string_literal: true

module SupplyChain
  class LicensePolicy < ApplicationRecord
    include Auditable

    self.table_name = "supply_chain_license_policies"

    # ============================================
    # Constants
    # ============================================
    POLICY_TYPES = %w[allowlist denylist hybrid].freeze
    ENFORCEMENT_LEVELS = %w[log warn block].freeze

    # ============================================
    # Associations
    # ============================================
    belongs_to :account
    belongs_to :created_by, class_name: "User", optional: true

    has_many :license_violations, class_name: "SupplyChain::LicenseViolation",
             foreign_key: :license_policy_id, dependent: :destroy

    # ============================================
    # Validations
    # ============================================
    validates :name, presence: true, uniqueness: { scope: :account_id }
    validates :policy_type, presence: true, inclusion: { in: POLICY_TYPES }
    validates :enforcement_level, presence: true, inclusion: { in: ENFORCEMENT_LEVELS }
    validates :priority, numericality: { greater_than_or_equal_to: 0 }

    # ============================================
    # Scopes
    # ============================================
    scope :active, -> { where(is_active: true) }
    scope :inactive, -> { where(is_active: false) }
    scope :default, -> { where(is_default: true) }
    scope :by_type, ->(type) { where(policy_type: type) }
    scope :blocking, -> { where(enforcement_level: "block") }
    scope :warning, -> { where(enforcement_level: "warn") }
    scope :ordered, -> { order(priority: :desc, created_at: :asc) }

    # ============================================
    # Callbacks
    # ============================================
    before_save :sanitize_jsonb_fields
    before_save :ensure_single_default

    # ============================================
    # Class Methods
    # ============================================
    class << self
      def default_for_account(account)
        account.supply_chain_license_policies.default.first ||
          account.supply_chain_license_policies.active.ordered.first
      end
    end

    # ============================================
    # Instance Methods
    # ============================================
    def active?
      is_active
    end

    def default?
      is_default
    end

    def allowlist?
      policy_type == "allowlist"
    end

    def denylist?
      policy_type == "denylist"
    end

    def hybrid?
      policy_type == "hybrid"
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

    def activate!
      update!(is_active: true)
    end

    def deactivate!
      update!(is_active: false)
    end

    def set_as_default!
      transaction do
        account.supply_chain_license_policies.update_all(is_default: false)
        update!(is_default: true)
      end
    end

    def evaluate(license_spdx_id)
      result = {
        policy_id: id,
        policy_name: name,
        license_spdx_id: license_spdx_id,
        enforcement_level: enforcement_level,
        compliant: true,
        violations: []
      }

      return result.merge(compliant: true, reason: "No license specified") if license_spdx_id.blank?

      license = SupplyChain::License.find_by_spdx(license_spdx_id)

      # Check exception packages first
      return result if exception_for_license?(license_spdx_id)

      # Evaluate based on policy type
      case policy_type
      when "allowlist"
        evaluate_allowlist(license_spdx_id, license, result)
      when "denylist"
        evaluate_denylist(license_spdx_id, license, result)
      when "hybrid"
        evaluate_hybrid(license_spdx_id, license, result)
      end

      # Check copyleft settings
      evaluate_copyleft(license, result) if license

      result
    end

    def evaluate_component(component)
      license_spdx_id = component.license_spdx_id || component.license_name
      evaluate(license_spdx_id)
    end

    def check_license(license, component)
      spdx_id = license.respond_to?(:spdx_id) ? license.spdx_id : license.to_s
      result = evaluate(spdx_id)
      return nil if result[:compliant]

      {
        component_id: component.id,
        component_name: component.name,
        component_version: component.version,
        license_id: license.respond_to?(:id) ? license.id : nil,
        license_spdx_id: spdx_id,
        reason: result[:violations]&.join(", ") || "License not compliant",
        enforcement_level: result[:enforcement_level]
      }
    end

    def allowed_license?(spdx_id)
      return false if denied_licenses.include?(spdx_id)
      return true if allowed_licenses.blank?

      allowed_licenses.include?(spdx_id)
    end

    def denied_license?(spdx_id)
      denied_licenses.include?(spdx_id)
    end

    def exception_for_license?(spdx_id)
      exception_packages.any? { |e| e["license"] == spdx_id }
    end

    def exception_for_package?(package_name)
      exception_packages.any? { |e| e["package"] == package_name }
    end

    def add_allowed_license(spdx_id)
      self.allowed_licenses = (allowed_licenses + [ spdx_id ]).uniq
      save!
    end

    def remove_allowed_license(spdx_id)
      self.allowed_licenses = allowed_licenses - [ spdx_id ]
      save!
    end

    def add_denied_license(spdx_id)
      self.denied_licenses = (denied_licenses + [ spdx_id ]).uniq
      save!
    end

    def remove_denied_license(spdx_id)
      self.denied_licenses = denied_licenses - [ spdx_id ]
      save!
    end

    def add_exception(package_name:, license:, reason:, expires_at: nil)
      exception = {
        package: package_name,
        license: license,
        reason: reason,
        added_at: Time.current.iso8601,
        expires_at: expires_at&.iso8601
      }

      self.exception_packages = (exception_packages + [ exception ])
      save!
    end

    def remove_exception(package_name)
      self.exception_packages = exception_packages.reject { |e| e["package"] == package_name }
      save!
    end

    def summary
      {
        id: id,
        name: name,
        description: description,
        policy_type: policy_type,
        enforcement_level: enforcement_level,
        is_active: is_active,
        is_default: is_default,
        priority: priority,
        allowed_license_count: allowed_licenses.length,
        denied_license_count: denied_licenses.length,
        exception_count: exception_packages.length,
        block_copyleft: block_copyleft,
        block_strong_copyleft: block_strong_copyleft,
        block_unknown: block_unknown,
        created_at: created_at
      }
    end

    private

    def sanitize_jsonb_fields
      self.allowed_licenses ||= []
      self.denied_licenses ||= []
      self.exception_packages ||= []
      self.metadata ||= {}
    end

    def ensure_single_default
      return unless is_default && is_default_changed?

      account.supply_chain_license_policies
             .where.not(id: id)
             .update_all(is_default: false)
    end

    def evaluate_allowlist(spdx_id, license, result)
      return if allowed_licenses.blank?

      unless allowed_licenses.include?(spdx_id)
        result[:compliant] = false
        result[:violations] << {
          type: "not_allowed",
          message: "License '#{spdx_id}' is not in the allowlist"
        }
      end
    end

    def evaluate_denylist(spdx_id, license, result)
      if denied_licenses.include?(spdx_id)
        result[:compliant] = false
        result[:violations] << {
          type: "denied",
          message: "License '#{spdx_id}' is explicitly denied"
        }
      end
    end

    def evaluate_hybrid(spdx_id, license, result)
      # First check denylist
      evaluate_denylist(spdx_id, license, result)

      # If not denied and allowlist is not empty, check allowlist
      if result[:compliant] && allowed_licenses.present?
        evaluate_allowlist(spdx_id, license, result)
      end
    end

    def evaluate_copyleft(license, result)
      if block_copyleft && license.copyleft?
        result[:compliant] = false
        result[:violations] << {
          type: "copyleft",
          message: "Copyleft licenses are blocked by this policy"
        }
      elsif block_strong_copyleft && license.strong_copyleft?
        result[:compliant] = false
        result[:violations] << {
          type: "strong_copyleft",
          message: "Strong copyleft licenses are blocked by this policy"
        }
      end

      if block_unknown && license.category == "unknown"
        result[:compliant] = false
        result[:violations] << {
          type: "unknown",
          message: "Unknown licenses are blocked by this policy"
        }
      end
    end
  end
end
