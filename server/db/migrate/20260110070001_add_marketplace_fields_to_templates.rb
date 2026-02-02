# frozen_string_literal: true

class AddMarketplaceFieldsToTemplates < ActiveRecord::Migration[7.2]
  def change
    # Add marketplace publishing fields to AI Workflow Templates
    add_column :ai_workflow_templates, :is_marketplace_published, :boolean, default: false
    add_column :ai_workflow_templates, :marketplace_status, :string
    add_column :ai_workflow_templates, :marketplace_submitted_at, :datetime
    add_column :ai_workflow_templates, :marketplace_approved_at, :datetime
    add_column :ai_workflow_templates, :marketplace_rejection_reason, :text

    # Add marketplace publishing fields to Integration Templates
    add_column :integration_templates, :is_marketplace_published, :boolean, default: false
    add_column :integration_templates, :marketplace_status, :string
    add_column :integration_templates, :marketplace_submitted_at, :datetime
    add_column :integration_templates, :marketplace_approved_at, :datetime
    add_column :integration_templates, :marketplace_rejection_reason, :text
    add_column :integration_templates, :account_id, :uuid
    add_index :integration_templates, :account_id

    # Add marketplace publishing fields to Shared Prompt Templates
    add_column :shared_prompt_templates, :is_marketplace_published, :boolean, default: false
    add_column :shared_prompt_templates, :marketplace_status, :string
    add_column :shared_prompt_templates, :marketplace_submitted_at, :datetime
    add_column :shared_prompt_templates, :marketplace_approved_at, :datetime
    add_column :shared_prompt_templates, :marketplace_rejection_reason, :text
    add_column :shared_prompt_templates, :rating, :decimal, precision: 3, scale: 2, default: 0
    add_column :shared_prompt_templates, :rating_count, :integer, default: 0

    # Add indexes for marketplace queries
    add_index :ai_workflow_templates, [ :is_marketplace_published, :marketplace_status ], name: 'idx_ai_workflow_templates_marketplace'
    add_index :integration_templates, [ :is_marketplace_published, :marketplace_status ], name: 'idx_integration_templates_marketplace'
    add_index :shared_prompt_templates, [ :is_marketplace_published, :marketplace_status ], name: 'idx_shared_prompt_templates_marketplace'
  end
end
