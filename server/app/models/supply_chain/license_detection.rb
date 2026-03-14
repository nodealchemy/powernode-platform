# frozen_string_literal: true

module SupplyChain
  class LicenseDetection < ApplicationRecord
    include Auditable

    self.table_name = "supply_chain_license_detections"

    # ============================================
    # Constants
    # ============================================
    DETECTION_SOURCES = %w[manifest file api ai manual].freeze

    # ============================================
    # Associations
    # ============================================
    belongs_to :account
    belongs_to :sbom_component, class_name: "SupplyChain::SbomComponent"
    belongs_to :license, class_name: "SupplyChain::License", optional: true

    # ============================================
    # Validations
    # ============================================
    validates :detection_source, presence: true, inclusion: { in: DETECTION_SOURCES }
    validates :confidence_score, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }

    # ============================================
    # Scopes
    # ============================================
    scope :by_source, ->(source) { where(detection_source: source) }
    scope :manifest_detections, -> { where(detection_source: "manifest") }
    scope :file_detections, -> { where(detection_source: "file") }
    scope :api_detections, -> { where(detection_source: "api") }
    scope :ai_detections, -> { where(detection_source: "ai") }
    scope :manual_detections, -> { where(detection_source: "manual") }
    scope :primary, -> { where(is_primary: true) }
    scope :needs_review, -> { where(requires_review: true) }
    scope :high_confidence, -> { where("confidence_score >= ?", 0.9) }
    scope :low_confidence, -> { where("confidence_score < ?", 0.5) }
    scope :for_component, ->(component_id) { where(sbom_component_id: component_id) }
    scope :recent, -> { order(created_at: :desc) }

    # ============================================
    # Callbacks
    # ============================================
    before_save :sanitize_jsonb_fields
    before_save :resolve_license
    after_save :update_component_license, if: :should_update_component?

    # ============================================
    # Instance Methods
    # ============================================
    def manifest?
      detection_source == "manifest"
    end

    def file?
      detection_source == "file"
    end

    def api?
      detection_source == "api"
    end

    def ai?
      detection_source == "ai"
    end

    def manual?
      detection_source == "manual"
    end

    def primary?
      is_primary
    end

    def needs_review?
      requires_review
    end

    def high_confidence?
      confidence_score >= 0.9
    end

    def low_confidence?
      confidence_score < 0.5
    end

    def resolved?
      license.present?
    end

    def effective_license_id
      license&.spdx_id || detected_license_id
    end

    def effective_license_name
      license&.name || detected_license_name
    end

    def mark_as_primary!
      transaction do
        sbom_component.license_detections.update_all(is_primary: false)
        update!(is_primary: true)
        update_component_license
      end
    end

    def mark_needs_review!(reason = nil)
      update!(
        requires_review: true,
        metadata: metadata.merge("review_reason" => reason)
      )
    end

    def clear_review_flag!
      update!(requires_review: false)
    end

    def summary
      {
        id: id,
        sbom_component_id: sbom_component_id,
        detected_license_id: detected_license_id,
        detected_license_name: detected_license_name,
        resolved_license_id: license&.spdx_id,
        detection_source: detection_source,
        confidence_score: confidence_score,
        is_primary: is_primary,
        requires_review: requires_review,
        file_path: file_path,
        created_at: created_at
      }
    end

    private

    def sanitize_jsonb_fields
      self.ai_interpretation ||= {}
      self.metadata ||= {}
    end

    def resolve_license
      return if license.present?
      return unless detected_license_id.present?

      self.license = SupplyChain::License.find_by_spdx(detected_license_id)
    end

    def should_update_component?
      is_primary && (saved_change_to_is_primary? || saved_change_to_license_id?)
    end

    def update_component_license
      return unless license.present?

      sbom_component.update!(
        license_spdx_id: license.spdx_id,
        license_name: license.name
      )
    end
  end
end
