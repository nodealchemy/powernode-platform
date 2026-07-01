# frozen_string_literal: true

# Append-only log of Fable/Mythos safety-classifier refusals and their recovery
# outcome, keyed by (account, model, agent_type, task_type, tool_surface,
# category, phase). Feeds the empirical signal (a refusal is a failure for the
# refused model) and drives Ai::ModelRefusalPromotionService, which pre-routes
# high-refusal (agent_type, category) combos away from Fable.
#
# UUIDv7 PK via the uuidv7() DB default (mirrors ApplicationRecord's UuidGenerator
# hook); FK columns are raw t.uuid with explicit indexes, mirroring the
# ai_agent_model_performances baseline table.
class CreateAiModelRefusalEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :ai_model_refusal_events, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.uuid    :account_id,      null: false
      t.uuid    :ai_provider_id,  null: false
      t.string  :model,           null: false, limit: 120  # the REFUSED model
      t.string  :agent_type,      null: false, limit: 50
      t.string  :task_type,       limit: 120               # skill / task (nullable)
      t.string  :tool_surface,    limit: 120               # (nullable)
      t.string  :category                                  # cyber/bio/reasoning_extraction/frontier_llm/null
      t.string  :phase,           null: false              # pre_output | mid_stream
      t.boolean :reframed,        null: false, default: false
      t.boolean :fell_back,       null: false, default: false
      t.string  :served_by_model                           # model that ultimately served (nullable)
      t.text    :explanation
      t.uuid    :agent_execution_id                        # nullable link
      t.timestamps

      # Per-(model, agent_type) refusal history for the empirical signal.
      t.index %i[account_id model agent_type], name: "idx_refusal_events_account_model_type"
      # Promotion key: high-refusal (agent_type, tool_surface, category) combos.
      t.index %i[account_id agent_type tool_surface category], name: "idx_refusal_events_promotion_key"
      t.index :created_at
    end
  end
end
