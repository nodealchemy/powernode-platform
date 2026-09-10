# frozen_string_literal: true

module Ai
  class SkillVersion < ApplicationRecord
    self.table_name = "ai_skill_versions"

    # ==========================================
    # Constants
    # ==========================================
    CHANGE_TYPES = %w[manual evolution consolidation ab_test].freeze

    # ==========================================
    # Associations
    # ==========================================
    belongs_to :account
    belongs_to :ai_skill, class_name: "Ai::Skill", foreign_key: "ai_skill_id"
    belongs_to :created_by_agent, class_name: "Ai::Agent", foreign_key: "created_by_agent_id", optional: true
    belongs_to :created_by_user, class_name: "User", foreign_key: "created_by_user_id", optional: true

    # ==========================================
    # Validations
    # ==========================================
    validates :version, presence: true, uniqueness: { scope: :ai_skill_id }
    validates :change_type, presence: true, inclusion: { in: CHANGE_TYPES }

    # ==========================================
    # Scopes
    # ==========================================
    scope :for_skill, ->(skill_id) { where(ai_skill_id: skill_id) }
    scope :active, -> { where(is_active: true) }
    scope :ab_variants, -> { where(is_ab_variant: true) }
    scope :by_effectiveness, -> { order(effectiveness_score: :desc) }

    # ==========================================
    # Public Methods
    # ==========================================

    def record_outcome!(successful:)
      if successful
        increment!(:success_count)
      else
        increment!(:failure_count)
      end
      increment!(:usage_count)

      recalculate_effectiveness! if usage_count >= 5
    end

    # D5 — activation must change WHAT IS SERVED, not just a label.
    #
    # Ai::Agent#build_skill_system_prompts plucks ai_skills.system_prompt, so a
    # version flagged active whose text was never copied there is inert: the
    # skill goes on serving whatever prompt it already had, and every outcome
    # recorded "against the active version" is really an outcome of the old
    # text. That falsifies the entire evolution loop — propose, activate,
    # measure — because only the first two steps ever touched anything.
    #
    # A version carrying no prompt leaves the served text alone rather than
    # blanking it: rows predating this column exist, and activating one must
    # not silently empty the skill it serves.
    def activate!
      transaction do
        self.class.where(ai_skill_id: ai_skill_id).update_all(is_active: false)
        update!(is_active: true)
        ai_skill.update!(system_prompt: system_prompt) if system_prompt.present?
      end
    end

    def version_summary
      {
        id: id,
        version: version,
        change_type: change_type,
        change_reason: change_reason,
        effectiveness_score: effectiveness_score,
        usage_count: usage_count,
        success_count: success_count,
        failure_count: failure_count,
        is_active: is_active,
        is_ab_variant: is_ab_variant,
        ab_traffic_pct: ab_traffic_pct,
        created_at: created_at
      }
    end

    private

    def recalculate_effectiveness!
      new_score = success_count / usage_count.to_f
      update_column(:effectiveness_score, new_score)
    end
  end
end
