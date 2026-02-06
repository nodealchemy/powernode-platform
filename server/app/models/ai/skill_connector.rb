# frozen_string_literal: true

module Ai
  class SkillConnector < ApplicationRecord
    self.table_name = "ai_skill_connectors"

    # ==========================================
    # Constants
    # ==========================================
    ROLES = %w[primary optional fallback].freeze

    # ==========================================
    # Associations
    # ==========================================
    belongs_to :skill, class_name: "Ai::Skill", foreign_key: "ai_skill_id"
    belongs_to :mcp_server

    # ==========================================
    # Validations
    # ==========================================
    validates :role, inclusion: { in: ROLES }
    validates :ai_skill_id, uniqueness: { scope: :mcp_server_id }
  end
end
