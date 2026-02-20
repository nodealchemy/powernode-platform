# frozen_string_literal: true

module Ai
  class AgentLineage < ApplicationRecord
    self.table_name = "ai_agent_lineages"

    # ==========================================
    # Associations
    # ==========================================
    belongs_to :account
    belongs_to :parent_agent, class_name: "Ai::Agent", foreign_key: "parent_agent_id"
    belongs_to :child_agent, class_name: "Ai::Agent", foreign_key: "child_agent_id"

    # ==========================================
    # Validations
    # ==========================================
    validates :parent_agent_id, presence: true
    validates :child_agent_id, presence: true
    validates :spawned_at, presence: true
    validates :parent_agent_id, uniqueness: { scope: :child_agent_id, message: "lineage relationship already exists" }
    validate :parent_and_child_differ
    validate :no_circular_lineage

    # ==========================================
    # Scopes
    # ==========================================
    scope :active, -> { where(terminated_at: nil) }
    scope :terminated, -> { where.not(terminated_at: nil) }
    scope :for_parent, ->(agent_id) { where(parent_agent_id: agent_id) }
    scope :for_child, ->(agent_id) { where(child_agent_id: agent_id) }
    scope :recent, -> { order(spawned_at: :desc) }

    # ==========================================
    # Methods
    # ==========================================

    def active?
      terminated_at.nil?
    end

    def terminate!(reason: nil)
      update!(terminated_at: Time.current, termination_reason: reason)
    end

    # Calculate spawn depth from root ancestor
    def spawn_depth
      depth = 0
      current = parent_agent
      visited = Set.new([child_agent_id])

      while current && !visited.include?(current.id)
        visited.add(current.id)
        parent_lineage = self.class.for_child(current.id).active.first
        break unless parent_lineage

        depth += 1
        current = parent_lineage.parent_agent
      end

      depth
    end

    private

    def parent_and_child_differ
      return unless parent_agent_id == child_agent_id

      errors.add(:child_agent_id, "cannot be the same as parent agent")
    end

    def no_circular_lineage
      return unless parent_agent_id.present? && child_agent_id.present?

      # Check if child_agent is already an ancestor of parent_agent
      current_id = parent_agent_id
      visited = Set.new

      while current_id && !visited.include?(current_id)
        if current_id == child_agent_id
          errors.add(:base, "would create a circular lineage")
          return
        end

        visited.add(current_id)
        parent_record = self.class.for_child(current_id).active.first
        current_id = parent_record&.parent_agent_id
      end
    end
  end
end
