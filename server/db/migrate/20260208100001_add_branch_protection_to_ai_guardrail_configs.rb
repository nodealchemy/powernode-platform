# frozen_string_literal: true

class AddBranchProtectionToAiGuardrailConfigs < ActiveRecord::Migration[8.0]
  def change
    add_column :ai_guardrail_configs, :protected_branches, :jsonb, default: ["main", "master", "develop"]
    add_column :ai_guardrail_configs, :require_worktree_for_repos, :boolean, default: true
    add_column :ai_guardrail_configs, :merge_approval_required, :boolean, default: true
    add_column :ai_guardrail_configs, :branch_protection_enabled, :boolean, default: false
    add_column :ai_guardrail_configs, :branch_protection_config, :jsonb, default: {}
  end
end
