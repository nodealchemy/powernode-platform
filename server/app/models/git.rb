# frozen_string_literal: true

# Git namespace for repository and provider management models
# This module provides namespace for:
# - Git::Provider
# - Git::ProviderCredential
# - Git::Repository
# - Git::Pipeline
# - Git::PipelineJob
# - Git::PipelineApproval
# - Git::PipelineSchedule
# - Git::Runner
# - Git::WebhookEvent
# - Git::WorkflowTrigger
module Git
  def self.table_name_prefix
    "git_"
  end
end
