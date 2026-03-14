# frozen_string_literal: true

module SupplyChain
  class License < ApplicationRecord
    include Auditable

    self.table_name = "supply_chain_licenses"

    # ============================================
    # Constants
    # ============================================
    CATEGORIES = %w[permissive copyleft weak_copyleft public_domain proprietary unknown].freeze

    # Common SPDX license identifiers
    COMMON_PERMISSIVE = %w[MIT Apache-2.0 BSD-2-Clause BSD-3-Clause ISC Unlicense CC0-1.0].freeze
    COMMON_COPYLEFT = %w[GPL-2.0-only GPL-3.0-only AGPL-3.0-only].freeze
    COMMON_WEAK_COPYLEFT = %w[LGPL-2.1-only LGPL-3.0-only MPL-2.0 EPL-1.0 EPL-2.0].freeze

    # ============================================
    # Associations
    # ============================================
    has_many :license_detections, class_name: "SupplyChain::LicenseDetection",
             foreign_key: :license_id, dependent: :nullify
    has_many :license_violations, class_name: "SupplyChain::LicenseViolation",
             foreign_key: :license_id, dependent: :nullify
    has_many :attributions, class_name: "SupplyChain::Attribution",
             foreign_key: :license_id, dependent: :nullify

    # ============================================
    # Validations
    # ============================================
    validates :spdx_id, presence: true, uniqueness: true
    validates :name, presence: true
    validates :category, presence: true, inclusion: { in: CATEGORIES }

    # ============================================
    # Scopes
    # ============================================
    scope :by_category, ->(category) { where(category: category) }
    scope :permissive, -> { where(category: "permissive") }
    scope :copyleft, -> { where(is_copyleft: true) }
    scope :strong_copyleft, -> { where(is_strong_copyleft: true) }
    scope :weak_copyleft, -> { where(category: "weak_copyleft") }
    scope :network_copyleft, -> { where(is_network_copyleft: true) }
    scope :osi_approved, -> { where(is_osi_approved: true) }
    scope :deprecated, -> { where(is_deprecated: true) }
    scope :active, -> { where(is_deprecated: false) }
    scope :public_domain, -> { where(category: "public_domain") }
    scope :proprietary, -> { where(category: "proprietary") }
    scope :alphabetical, -> { order(name: :asc) }

    # ============================================
    # Callbacks
    # ============================================
    before_save :sanitize_jsonb_fields
    before_save :set_category_flags

    # ============================================
    # Class Methods
    # ============================================
    class << self
      def find_by_spdx(spdx_id)
        find_by(spdx_id: spdx_id) || find_by(spdx_id: normalize_spdx_id(spdx_id))
      end

      def search(query)
        where("spdx_id ILIKE :q OR name ILIKE :q", q: "%#{query}%")
      end

      def normalize_spdx_id(id)
        # Handle common variations
        id.to_s.strip
          .gsub(/\s+/, "-")
          .gsub(/GPL\s*v?(\d)/i, 'GPL-\1.0-only')
          .gsub(/Apache\s*(\d)/i, 'Apache-\1.0')
      end

      def compatible?(license1, license2)
        l1 = license1.is_a?(License) ? license1 : find_by_spdx(license1)
        l2 = license2.is_a?(License) ? license2 : find_by_spdx(license2)

        return false unless l1 && l2

        # Check compatibility matrix
        l1.compatible_with?(l2)
      end
    end

    # ============================================
    # Instance Methods
    # ============================================
    def permissive?
      category == "permissive"
    end

    def copyleft?
      is_copyleft
    end

    def strong_copyleft?
      is_strong_copyleft
    end

    def weak_copyleft?
      category == "weak_copyleft"
    end

    def network_copyleft?
      is_network_copyleft
    end

    def osi_approved?
      is_osi_approved
    end

    def deprecated?
      is_deprecated
    end

    def public_domain?
      category == "public_domain"
    end

    def proprietary?
      category == "proprietary"
    end

    def requires_attribution?
      !public_domain? && category != "unknown"
    end

    def requires_license_copy?
      copyleft? || weak_copyleft? || spdx_id.in?(%w[Apache-2.0 BSD-3-Clause])
    end

    def requires_source_disclosure?
      copyleft? || network_copyleft?
    end

    def compatible_with?(other_license)
      return true if permissive? && other_license.permissive?
      return true if public_domain?

      # Check compatibility matrix if available
      if compatibility.present? && compatibility["compatible_with"].present?
        return compatibility["compatible_with"].include?(other_license.spdx_id)
      end

      # Default compatibility rules
      return false if copyleft? && other_license.copyleft? && spdx_id != other_license.spdx_id
      return true if permissive?

      false
    end

    def risk_level
      case category
      when "public_domain" then "none"
      when "permissive" then "low"
      when "weak_copyleft" then "medium"
      when "copyleft"
        network_copyleft? ? "critical" : "high"
      when "proprietary" then "high"
      else "unknown"
      end
    end

    def short_description
      case category
      when "permissive"
        "Permissive license with minimal restrictions"
      when "copyleft"
        if network_copyleft?
          "Strong copyleft with network disclosure requirement"
        elsif strong_copyleft?
          "Strong copyleft requiring derivative works to use same license"
        else
          "Copyleft license requiring disclosure of modifications"
        end
      when "weak_copyleft"
        "Weak copyleft allowing linking without license contamination"
      when "public_domain"
        "Public domain dedication with no restrictions"
      when "proprietary"
        "Proprietary license with commercial restrictions"
      else
        "Unknown license terms"
      end
    end

    def summary
      {
        id: id,
        spdx_id: spdx_id,
        name: name,
        category: category,
        is_osi_approved: is_osi_approved,
        is_copyleft: is_copyleft,
        is_strong_copyleft: is_strong_copyleft,
        is_network_copyleft: is_network_copyleft,
        is_deprecated: is_deprecated,
        risk_level: risk_level,
        requires_attribution: requires_attribution?,
        requires_license_copy: requires_license_copy?,
        requires_source_disclosure: requires_source_disclosure?,
        url: url
      }
    end

    private

    def sanitize_jsonb_fields
      self.compatibility ||= {}
      self.detection_patterns ||= []
      self.metadata ||= {}
    end

    def set_category_flags
      case category
      when "copyleft"
        self.is_copyleft = true
        self.is_strong_copyleft = spdx_id.in?(COMMON_COPYLEFT) || spdx_id.match?(/^(A?GPL|EUPL)/)
        self.is_network_copyleft = spdx_id.match?(/^AGPL/)
      when "weak_copyleft"
        self.is_copyleft = true
        self.is_strong_copyleft = false
        self.is_network_copyleft = false
      else
        # Don't override if explicitly set
        self.is_copyleft ||= false
        self.is_strong_copyleft ||= false
        self.is_network_copyleft ||= false
      end
    end
  end
end
