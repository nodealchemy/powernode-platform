# frozen_string_literal: true

module SupplyChain
  class AttributionService
    def self.generate_notice_file(sbom:, format: "text", include_full_license_text: false, user: nil)
      components = sbom.components.requiring_attribution

      content = components.map(&:to_notice_entry).join("\n\n")

      {
        success: true,
        content: content,
        format: format,
        component_count: components.count,
        license_count: components.map(&:license_id).uniq.compact.count
      }
    rescue StandardError => e
      Rails.logger.error("AttributionService.generate_notice_file failed: #{e.message}")
      {
        success: false,
        error: e.message
      }
    end
  end
end
