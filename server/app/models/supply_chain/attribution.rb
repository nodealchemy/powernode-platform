# frozen_string_literal: true

module SupplyChain
  class Attribution < ApplicationRecord
    include Auditable

    self.table_name = "supply_chain_attributions"

    # ============================================
    # Associations
    # ============================================
    belongs_to :account
    belongs_to :sbom_component, class_name: "SupplyChain::SbomComponent"
    belongs_to :license, class_name: "SupplyChain::License", optional: true

    # ============================================
    # Validations
    # ============================================
    validates :package_name, presence: true
    validates :sbom_component_id, uniqueness: true

    # ============================================
    # Scopes
    # ============================================
    scope :requiring_attribution, -> { where(requires_attribution: true) }
    scope :requiring_license_copy, -> { where(requires_license_copy: true) }
    scope :requiring_source_disclosure, -> { where(requires_source_disclosure: true) }
    scope :with_license_text, -> { where.not(license_text: nil) }
    scope :with_notice_text, -> { where.not(notice_text: nil) }
    scope :alphabetical, -> { order(package_name: :asc) }
    scope :by_license, ->(license_id) { where(license_id: license_id) }

    # ============================================
    # Callbacks
    # ============================================
    before_validation :populate_from_component, on: :create
    before_save :sanitize_jsonb_fields
    before_save :set_requirements_from_license

    # ============================================
    # Instance Methods
    # ============================================
    def requires_attribution?
      requires_attribution
    end

    def requires_license_copy?
      requires_license_copy
    end

    def requires_source_disclosure?
      requires_source_disclosure
    end

    def has_license_text?
      license_text.present?
    end

    def has_notice_text?
      notice_text.present?
    end

    def license_name
      license&.name
    end

    def license_spdx_id
      license&.spdx_id
    end

    def full_attribution_text
      parts = []

      parts << "=" * 60
      parts << package_name
      parts << "Version: #{package_version}" if package_version.present?
      parts << "=" * 60
      parts << ""

      if copyright_holder.present?
        copyright_line = "Copyright"
        copyright_line += " (c) #{copyright_year}" if copyright_year.present?
        copyright_line += " #{copyright_holder}"
        parts << copyright_line
        parts << ""
      end

      if license.present?
        parts << "License: #{license.name} (#{license.spdx_id})"
        parts << ""
      end

      if notice_text.present?
        parts << "NOTICE:"
        parts << notice_text
        parts << ""
      end

      if requires_license_copy? && license_text.present?
        parts << "LICENSE TEXT:"
        parts << "-" * 40
        parts << license_text
        parts << ""
      end

      if attribution_url.present?
        parts << "URL: #{attribution_url}"
        parts << ""
      end

      parts.join("\n")
    end

    def to_notice_entry
      entry = "#{package_name}"
      entry += " #{package_version}" if package_version.present?
      entry += " - #{license_name}" if license_name.present?

      if copyright_holder.present?
        entry += "\n  Copyright"
        entry += " (c) #{copyright_year}" if copyright_year.present?
        entry += " #{copyright_holder}"
      end

      entry
    end

    def summary
      {
        id: id,
        sbom_component_id: sbom_component_id,
        package_name: package_name,
        package_version: package_version,
        license_id: license_id,
        license_name: license_name,
        license_spdx_id: license_spdx_id,
        copyright_holder: copyright_holder,
        copyright_year: copyright_year,
        requires_attribution: requires_attribution,
        requires_license_copy: requires_license_copy,
        requires_source_disclosure: requires_source_disclosure,
        has_license_text: has_license_text?,
        has_notice_text: has_notice_text?,
        attribution_url: attribution_url
      }
    end

    # ============================================
    # Class Methods
    # ============================================
    class << self
      def generate_notice_file(attributions)
        lines = []
        lines << "THIRD-PARTY SOFTWARE NOTICES AND INFORMATION"
        lines << "=" * 60
        lines << ""
        lines << "This software includes third-party components under the following licenses:"
        lines << ""

        # Group by license
        by_license = attributions.group_by(&:license_spdx_id)

        by_license.each do |spdx_id, attrs|
          license = attrs.first.license
          license_name = license&.name || spdx_id || "Unknown License"

          lines << "-" * 60
          lines << license_name
          lines << "-" * 60
          lines << ""

          attrs.sort_by(&:package_name).each do |attr|
            lines << "  - #{attr.to_notice_entry}"
          end

          lines << ""

          # Include license text if any attribution requires it
          if attrs.any?(&:requires_license_copy?)
            sample_attr = attrs.find(&:has_license_text?)
            if sample_attr
              lines << "License Text:"
              lines << sample_attr.license_text
              lines << ""
            end
          end
        end

        lines << "=" * 60
        lines << "Generated at: #{Time.current.iso8601}"

        lines.join("\n")
      end

      def generate_for_sbom(sbom)
        sbom.components.find_each do |component|
          next if component.attribution.present?

          create_for_component(component)
        end
      end

      def create_for_component(component)
        license = SupplyChain::License.find_by_spdx(component.license_spdx_id) if component.license_spdx_id.present?

        create!(
          account: component.account,
          sbom_component: component,
          license: license,
          package_name: component.full_name,
          package_version: component.version
        )
      end
    end

    private

    def populate_from_component
      return unless sbom_component.present?

      self.package_name ||= sbom_component.full_name
      self.package_version ||= sbom_component.version
      self.license ||= SupplyChain::License.find_by_spdx(sbom_component.license_spdx_id) if sbom_component.license_spdx_id.present?
    end

    def sanitize_jsonb_fields
      self.metadata ||= {}
    end

    def set_requirements_from_license
      return unless license.present?

      self.requires_attribution = license.requires_attribution? if requires_attribution.nil?
      self.requires_license_copy = license.requires_license_copy? if requires_license_copy.nil?
      self.requires_source_disclosure = license.requires_source_disclosure? if requires_source_disclosure.nil?
    end
  end
end
