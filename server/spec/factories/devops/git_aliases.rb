# frozen_string_literal: true

# This file provides devops_ prefixed aliases for Git-related factories
# The actual factories are defined in spec/factories/git/
# These aliases ensure consistent naming conventions across the codebase

FactoryBot.define do
  # Alias for git_repository -> devops_git_repository
  factory :devops_git_repository, parent: :git_repository

  # Alias for git_pipeline_approval -> devops_git_pipeline_approval
  factory :devops_git_pipeline_approval, parent: :git_pipeline_approval

  # Alias for git_runner -> devops_git_runner
  factory :devops_git_runner, parent: :git_runner

  # Alias for git_webhook_event -> devops_git_webhook_event
  factory :devops_git_webhook_event, parent: :git_webhook_event

  # Alias for git_workflow_trigger -> devops_git_workflow_trigger
  factory :devops_git_workflow_trigger, parent: :git_workflow_trigger

  # Alias for git_provider_credential -> devops_git_provider_credential
  factory :devops_git_provider_credential, parent: :git_provider_credential

  # Alias for git_provider -> devops_git_provider
  factory :devops_git_provider, parent: :git_provider

  # Alias for git_pipeline -> devops_git_pipeline
  factory :devops_git_pipeline, parent: :git_pipeline
end
