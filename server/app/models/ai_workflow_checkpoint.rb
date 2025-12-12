# frozen_string_literal: true

class AiWorkflowCheckpoint < ApplicationRecord
  # ==================== Associations ====================
  belongs_to :ai_workflow_run

  # ==================== Validations ====================
  validates :checkpoint_id, presence: true, uniqueness: { scope: :ai_workflow_run_id }
  validates :node_id, presence: true
  validates :checkpoint_type, presence: true, inclusion: {
    in: %w[node_completion node_start workflow_pause manual_checkpoint error_checkpoint],
    message: "%{value} is not a valid checkpoint type"
  }
  validates :sequence_number, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :workflow_state, presence: true
  validates :execution_context, presence: true

  # ==================== Scopes ====================
  scope :recent, -> { order(sequence_number: :desc) }
  scope :chronological, -> { order(sequence_number: :asc) }
  scope :for_run, ->(run_id) { where(ai_workflow_run_id: run_id) }
  scope :by_type, ->(type) { where(checkpoint_type: type) }
  scope :manual, -> { where(checkpoint_type: "manual_checkpoint") }
  scope :error_checkpoints, -> { where(checkpoint_type: "error_checkpoint") }

  # ==================== Callbacks ====================
  before_validation :generate_checkpoint_id, on: :create
  before_validation :set_sequence_number, on: :create

  # ==================== Instance Methods ====================

  # Get checkpoint summary for API responses
  def checkpoint_summary
    {
      id: id,
      checkpoint_id: checkpoint_id,
      node_id: node_id,
      checkpoint_type: checkpoint_type,
      sequence_number: sequence_number,
      description: description,
      created_at: created_at,
      can_replay: can_replay?
    }
  end

  # Full checkpoint details including state
  def checkpoint_details
    checkpoint_summary.merge(
      workflow_state: workflow_state,
      execution_context: execution_context,
      variable_snapshot: variable_snapshot,
      metadata: metadata
    )
  end

  # Check if this checkpoint can be used for replay
  def can_replay?
    workflow_state.present? &&
    execution_context.present? &&
    !error_checkpoint?
  end

  # Check if this is an error checkpoint
  def error_checkpoint?
    checkpoint_type == "error_checkpoint"
  end

  # Check if this is a manual checkpoint
  def manual_checkpoint?
    checkpoint_type == "manual_checkpoint"
  end

  # Get next checkpoint in sequence
  def next_checkpoint
    self.class.where(ai_workflow_run_id: ai_workflow_run_id)
             .where("sequence_number > ?", sequence_number)
             .chronological
             .first
  end

  # Get previous checkpoint in sequence
  def previous_checkpoint
    self.class.where(ai_workflow_run_id: ai_workflow_run_id)
             .where("sequence_number < ?", sequence_number)
             .recent
             .first
  end

  # Calculate state delta from previous checkpoint
  def state_delta
    prev = previous_checkpoint
    return workflow_state unless prev

    {
      added: workflow_state.except(*prev.workflow_state.keys),
      modified: workflow_state.select { |k, v| prev.workflow_state[k] != v && prev.workflow_state.key?(k) },
      removed: prev.workflow_state.keys - workflow_state.keys
    }
  end

  private

  # Generate unique checkpoint ID
  def generate_checkpoint_id
    self.checkpoint_id ||= "chkpt_#{SecureRandom.hex(12)}"
  end

  # Set sequence number based on existing checkpoints
  def set_sequence_number
    return if sequence_number.present?

    last_checkpoint = self.class.where(ai_workflow_run_id: ai_workflow_run_id)
                                .order(sequence_number: :desc)
                                .first

    self.sequence_number = last_checkpoint ? last_checkpoint.sequence_number + 1 : 0
  end
end
