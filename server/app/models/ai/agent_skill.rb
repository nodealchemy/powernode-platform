# frozen_string_literal: true

module Ai
  class AgentSkill < ApplicationRecord
    self.table_name = "ai_agent_skills"

    belongs_to :agent, class_name: "Ai::Agent", foreign_key: "ai_agent_id"
    belongs_to :skill, class_name: "Ai::Skill", foreign_key: "ai_skill_id"

    validates :ai_skill_id, uniqueness: { scope: :ai_agent_id, message: "skill already assigned to this agent" }

    scope :active, -> { where(is_active: true) }
    scope :ordered, -> { order(priority: :asc) }
  end
end
