# frozen_string_literal: true

# DevOps namespace for CI/CD pipeline and integration models
# This module provides namespace for:
# - Devops::Pipeline
# - Devops::PipelineStep
# - Devops::PipelineRun
# - Devops::PipelineRepository
# - Devops::PipelineTemplate
# - Devops::PipelineTemplateInstallation
# - Devops::Provider
# - Devops::Repository
# - Devops::Schedule
# - Devops::StepApprovalToken
# - Devops::StepExecution
# - Devops::IntegrationTemplate
# - Devops::IntegrationCredential
# - Devops::IntegrationInstance
# - Devops::IntegrationExecution
module Devops
  def self.table_name_prefix
    "devops_"
  end
end
