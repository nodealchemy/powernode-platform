# frozen_string_literal: true

class MigrateCicdPromptTemplatesToShared < ActiveRecord::Migration[8.0]
  def up
    # Check if source table exists
    return unless table_exists?(:ci_cd_prompt_templates)

    # Migrate all CI/CD prompt templates to shared with domain='cicd'
    execute <<~SQL
      INSERT INTO shared_prompt_templates (
        id, account_id, created_by_id, name, slug, category, domain,
        description, content, variables, metadata, version,
        parent_template_id, is_active, is_system, created_at, updated_at
      )
      SELECT
        id, account_id, created_by_id, name, slug, category, 'cicd',
        description, content, COALESCE(variables, '[]'::jsonb), COALESCE(metadata, '{}'::jsonb), COALESCE(version, 1),
        parent_template_id, COALESCE(is_active, true), COALESCE(is_system, false), created_at, updated_at
      FROM ci_cd_prompt_templates
      ON CONFLICT (account_id, slug) DO NOTHING
    SQL

    # Update ci_cd_pipeline_steps to use shared_prompt_template_id
    execute <<~SQL
      UPDATE ci_cd_pipeline_steps
      SET shared_prompt_template_id = ci_cd_prompt_template_id
      WHERE ci_cd_prompt_template_id IS NOT NULL
    SQL
  end

  def down
    # Remove migrated data from shared table
    execute "DELETE FROM shared_prompt_templates WHERE domain = 'cicd'"

    # Clear shared references from pipeline steps
    execute "UPDATE ci_cd_pipeline_steps SET shared_prompt_template_id = NULL"
  end
end
