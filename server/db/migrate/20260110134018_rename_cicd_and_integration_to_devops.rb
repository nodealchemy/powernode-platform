# frozen_string_literal: true

class RenameCicdAndIntegrationToDevops < ActiveRecord::Migration[8.0]
  def change
    # CI/CD tables → DevOps namespace
    rename_table :ci_cd_pipelines, :devops_pipelines
    rename_table :ci_cd_pipeline_steps, :devops_pipeline_steps
    rename_table :ci_cd_pipeline_runs, :devops_pipeline_runs
    rename_table :ci_cd_pipeline_repositories, :devops_pipeline_repositories
    rename_table :ci_cd_pipeline_templates, :devops_pipeline_templates
    rename_table :ci_cd_pipeline_template_installations, :devops_pipeline_template_installations
    rename_table :ci_cd_providers, :devops_providers
    rename_table :ci_cd_repositories, :devops_repositories
    rename_table :ci_cd_schedules, :devops_schedules
    rename_table :ci_cd_step_approval_tokens, :devops_step_approval_tokens
    rename_table :ci_cd_step_executions, :devops_step_executions

    # Integration tables → DevOps namespace
    rename_table :integration_templates, :devops_integration_templates
    rename_table :integration_credentials, :devops_integration_credentials
    rename_table :integration_instances, :devops_integration_instances
    rename_table :integration_executions, :devops_integration_executions
  end
end
