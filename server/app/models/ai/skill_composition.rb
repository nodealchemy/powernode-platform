# frozen_string_literal: true

module Ai
  class SkillComposition < ApplicationRecord
    self.table_name = "ai_skill_compositions"

    COMPOSITION_TYPES = %w[sequential parallel conditional].freeze

    belongs_to :composite_skill, class_name: "Ai::Skill", foreign_key: "composite_skill_id"
    belongs_to :component_skill, class_name: "Ai::Skill", foreign_key: "component_skill_id"

    validates :execution_order, presence: true, uniqueness: { scope: :composite_skill_id }
    validates :composition_type, presence: true, inclusion: { in: COMPOSITION_TYPES }

    attribute :condition, :json, default: -> { {} }
    attribute :input_mapping, :json, default: -> { {} }
    attribute :output_mapping, :json, default: -> { {} }

    scope :in_order, -> { order(:execution_order) }
    scope :for_composite, ->(skill_id) { where(composite_skill_id: skill_id) }
  end
end
