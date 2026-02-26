# frozen_string_literal: true

module Ai
  class MissionTemplate < ApplicationRecord
    self.table_name = "ai_mission_templates"

    TEMPLATE_TYPES = %w[system account community].freeze
    MISSION_TYPES = %w[development research operations custom].freeze
    STATUSES = %w[active archived].freeze

    belongs_to :account, optional: true # nil for system templates

    validates :name, presence: true, length: { maximum: 255 }
    validates :template_type, presence: true, inclusion: { in: TEMPLATE_TYPES }
    validates :mission_type, presence: true, inclusion: { in: MISSION_TYPES }
    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :version, numericality: { only_integer: true, greater_than: 0 }
    validate :phases_format

    scope :system, -> { where(template_type: "system") }
    scope :for_account, ->(account_id) { where(account_id: [account_id, nil]) }
    scope :active, -> { where(status: "active") }
    scope :by_type, ->(type) { where(mission_type: type) }
    scope :defaults, -> { where(is_default: true) }

    attribute :phases, :json, default: -> { [] }
    attribute :approval_gates, :json, default: -> { [] }
    attribute :rejection_mappings, :json, default: -> { {} }
    attribute :skill_compositions, :json, default: -> { {} }
    attribute :default_configuration, :json, default: -> { {} }

    def instantiate_phases
      (phases || []).sort_by { |p| p["order"] || 0 }.map do |phase|
        phase.symbolize_keys.slice(:key, :label, :description, :requires_approval,
                                    :job_class, :estimated_duration_minutes, :skip_allowed, :order)
      end
    end

    def phase_keys
      (phases || []).sort_by { |p| p["order"] || 0 }.map { |p| p["key"] }
    end

    def approval_gate_keys
      approval_gates || []
    end

    def rejection_mapping_for(gate)
      (rejection_mappings || {})[gate]
    end

    def template_summary
      {
        id: id,
        name: name,
        description: description,
        template_type: template_type,
        mission_type: mission_type,
        phase_count: phases&.length || 0,
        phase_keys: phase_keys,
        approval_gates: approval_gate_keys,
        is_default: is_default,
        version: version,
        status: status
      }
    end

    def template_details
      template_summary.merge(
        phases: phases,
        rejection_mappings: rejection_mappings,
        skill_compositions: skill_compositions,
        default_configuration: default_configuration,
        account_id: account_id,
        created_at: created_at&.iso8601,
        updated_at: updated_at&.iso8601
      )
    end

    private

    def phases_format
      return if phases.blank?

      unless phases.is_a?(Array)
        errors.add(:phases, "must be an array")
        return
      end

      phases.each_with_index do |phase, i|
        unless phase.is_a?(Hash) && phase["key"].present?
          errors.add(:phases, "entry #{i} must have a 'key'")
        end
      end
    end
  end
end
