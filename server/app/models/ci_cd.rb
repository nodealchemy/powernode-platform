# frozen_string_literal: true

# CI/CD namespace for pipeline-related models
# This module provides namespace for:
# - CiCd::Pipeline
# - CiCd::PipelineStep
# - CiCd::PipelineRun
# - CiCd::PipelineRepository
# - CiCd::Provider
# - CiCd::Repository
# - CiCd::Schedule
# - CiCd::StepApprovalToken
# - CiCd::StepExecution
module CiCd
  def self.table_name_prefix
    "ci_cd_"
  end
end
