# frozen_string_literal: true

# Rename all ci_cd_ prefixed foreign key columns to devops_ prefix
# for consistency with the Devops:: namespace and devops_ table names.
class RenameCiCdColumnsToDevops < ActiveRecord::Migration[8.0]
  def change
    # ── devops_pipelines ──
    rename_column :devops_pipelines, :ci_cd_provider_id, :devops_provider_id

    # ── devops_pipeline_steps ──
    rename_column :devops_pipeline_steps, :ci_cd_pipeline_id, :devops_pipeline_id

    # ── devops_pipeline_runs ──
    rename_column :devops_pipeline_runs, :ci_cd_pipeline_id, :devops_pipeline_id

    # ── devops_pipeline_repositories ──
    rename_column :devops_pipeline_repositories, :ci_cd_pipeline_id, :devops_pipeline_id
    rename_column :devops_pipeline_repositories, :ci_cd_repository_id, :devops_repository_id

    # ── devops_repositories ──
    rename_column :devops_repositories, :ci_cd_provider_id, :devops_provider_id

    # ── devops_schedules ──
    rename_column :devops_schedules, :ci_cd_pipeline_id, :devops_pipeline_id

    # ── devops_step_executions ──
    rename_column :devops_step_executions, :ci_cd_pipeline_run_id, :devops_pipeline_run_id
    rename_column :devops_step_executions, :ci_cd_pipeline_step_id, :devops_pipeline_step_id
  end
end
