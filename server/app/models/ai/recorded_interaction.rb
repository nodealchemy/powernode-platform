# frozen_string_literal: true

module Ai
  class RecordedInteraction < ApplicationRecord
    self.table_name = "ai_recorded_interactions"

    # Override ActiveRecord's dangerous attribute check for model_name column
    # The database column 'model_name' conflicts with ActiveRecord::Base.model_name
    class << self
      def dangerous_attribute_method?(method_name)
        return false if method_name == "model_name"

        super
      end
    end

    # Associations
    belongs_to :account
    belongs_to :sandbox, class_name: "Ai::Sandbox"
    belongs_to :source_workflow_run, class_name: "Ai::WorkflowRun", optional: true

    # Validations
    validates :recording_id, presence: true, uniqueness: true
    validates :interaction_type, presence: true, inclusion: {
      in: %w[llm_request tool_call api_call workflow_step agent_action]
    }

    # Scopes
    scope :by_type, ->(type) { where(interaction_type: type) }
    scope :by_provider, ->(provider) { where(provider_type: provider) }
    scope :by_model, ->(model) { where(model_name: model) }
    scope :for_workflow_run, ->(run) { where(source_workflow_run: run).order(sequence_number: :asc) }
    scope :recent, -> { order(recorded_at: :desc) }
    scope :ordered, -> { order(sequence_number: :asc) }

    # Callbacks
    before_validation :set_recording_id, on: :create
    before_validation :set_recorded_at, on: :create

    # Class methods
    def self.record!(sandbox:, account:, interaction_type:, request_data:, response_data:, provider_type: nil, model_name: nil, source_workflow_run: nil, latency_ms: nil, tokens_input: 0, tokens_output: 0, cost: 0, sequence_number: nil, metadata: {})
      create!(
        sandbox: sandbox,
        account: account,
        interaction_type: interaction_type,
        provider_type: provider_type,
        model_name: model_name,
        source_workflow_run: source_workflow_run,
        request_data: request_data,
        response_data: response_data,
        metadata: metadata,
        latency_ms: latency_ms,
        tokens_input: tokens_input,
        tokens_output: tokens_output,
        cost_usd: cost,
        sequence_number: sequence_number
      )
    end

    # Methods
    def llm_request?
      interaction_type == "llm_request"
    end

    def tool_call?
      interaction_type == "tool_call"
    end

    def api_call?
      interaction_type == "api_call"
    end

    def total_tokens
      tokens_input.to_i + tokens_output.to_i
    end

    def to_mock_response
      {
        provider_type: provider_type,
        model_name: model_name,
        response_data: response_data,
        latency_ms: latency_ms
      }
    end

    def replay_data
      {
        interaction_type: interaction_type,
        provider_type: provider_type,
        model_name: model_name,
        request: request_data,
        response: response_data,
        latency_ms: latency_ms,
        tokens: { input: tokens_input, output: tokens_output },
        cost_usd: cost_usd
      }
    end

    private

    def set_recording_id
      self.recording_id ||= SecureRandom.uuid
    end

    def set_recorded_at
      self.recorded_at ||= Time.current
    end
  end
end
