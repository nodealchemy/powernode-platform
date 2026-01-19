# frozen_string_literal: true

class AddAiProviderToPipelines < ActiveRecord::Migration[8.0]
  def change
    # Add new column for AiProvider association
    add_column :ci_cd_pipelines, :ai_provider_id, :uuid
    add_index :ci_cd_pipelines, :ai_provider_id
    add_foreign_key :ci_cd_pipelines, :ai_providers, on_delete: :nullify

    # Set default ai_provider for existing pipelines without one
    reversible do |dir|
      dir.up do
        # Link existing pipelines to account's default AI provider
        execute <<~SQL
          UPDATE ci_cd_pipelines p
          SET ai_provider_id = (
            SELECT ap.id FROM ai_providers ap
            WHERE ap.account_id = p.account_id
            AND ap.is_active = true
            ORDER BY ap.created_at ASC
            LIMIT 1
          )
          WHERE p.ai_provider_id IS NULL
        SQL
      end
    end
  end
end
