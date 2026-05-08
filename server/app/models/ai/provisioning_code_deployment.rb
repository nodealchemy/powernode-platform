# frozen_string_literal: true

module Ai
  # AI-Driven Provisioning M3 — "Run My Code" deployment ledger row.
  #
  # Tracks a single repo deployment from an `Ai::Mission` onto a
  # `::System::NodeInstance`. Owned by the `DeployAppCodeExecutor`:
  # the executor creates the row in `pending`, hands off to Slice A's
  # `System::CodeDeployService`, and updates `status`, `commit_sha`,
  # `public_url`, `deployed_at`, or `last_error` based on the result.
  #
  # Reference: how-can-we-provide-flickering-candy plan, M3 slice 2.
  class ProvisioningCodeDeployment < ApplicationRecord
    self.table_name = "ai_provisioning_code_deployments"

    # Lifecycle states. `pending` is the seed state; `cloning|installing|
    # starting` are intermediate progress states surfaced to the operator
    # via real-time updates; `running` is the terminal success state;
    # `failed` is the terminal failure state (with `last_error`);
    # `rolled_back` is set by `rollback_deploy_app_code` after a tear-down.
    STATUSES = %w[pending cloning installing starting running failed rolled_back].freeze

    belongs_to :mission, class_name: "Ai::Mission"
    belongs_to :node_instance, class_name: "::System::NodeInstance"

    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :repo_url, presence: true
    validates :branch, presence: true

    scope :running, -> { where(status: "running") }
    scope :failed, -> { where(status: "failed") }
    scope :pending_deploy, -> { where(status: "pending") }
    scope :rolled_back, -> { where(status: "rolled_back") }
    scope :recent, -> { order(created_at: :desc) }
  end
end
