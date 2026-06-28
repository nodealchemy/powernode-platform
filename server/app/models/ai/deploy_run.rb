# frozen_string_literal: true

module Ai
  # Durable record of one deploy attempt driven by Ai::Deploy::Orchestrator. Captures the
  # safety-envelope outcome (dry-run vs real, migration-safety, commands, health, rollback)
  # for audit + idempotency. Status is set from the method's Ai::Deploy::Result plus the
  # orchestrator's gates (blocked = a gate refused; skipped = kill-switch).
  class DeployRun < ApplicationRecord
    self.table_name = "ai_deploy_runs"

    STATUSES = %w[pending running dry_run succeeded failed rolled_back skipped blocked].freeze
    TERMINAL_STATUSES = %w[dry_run succeeded failed rolled_back skipped blocked].freeze

    belongs_to :account
    belongs_to :campaign, class_name: "Ai::Campaign", foreign_key: "campaign_id", optional: true
    belongs_to :campaign_land, class_name: "Ai::CampaignLand", foreign_key: "campaign_land_id", optional: true
    belongs_to :repository, class_name: "Devops::GitRepository", foreign_key: "repository_id", optional: true
    belongs_to :triggered_by, class_name: "User", foreign_key: "triggered_by_id", optional: true

    validates :target_kind, presence: true
    validates :method_key, presence: true
    validates :status, presence: true, inclusion: { in: STATUSES }

    scope :recent, ->(limit = 50) { order(created_at: :desc).limit(limit) }
    scope :for_account, ->(acct) { where(account_id: acct.id) }

    def start!
      update!(status: "running", started_at: started_at || Time.current)
    end

    # Apply a method's Ai::Deploy::Result (succeeded | failed | dry_run | skipped).
    def finish!(result)
      update!(
        status: result.status.to_s,
        detail: result.detail,
        commands: result.commands,
        metadata: (metadata || {}).merge(result.metadata || {}),
        completed_at: Time.current
      )
    end

    def block!(reason, extra_metadata = {})
      update!(status: "blocked", error_message: reason,
              metadata: (metadata || {}).merge(extra_metadata), completed_at: Time.current)
    end

    def skip!(reason)
      update!(status: "skipped", detail: reason, completed_at: Time.current)
    end

    def fail!(message, extra_metadata = {})
      update!(status: "failed", error_message: message,
              metadata: (metadata || {}).merge(extra_metadata), completed_at: Time.current)
    end

    def mark_rolled_back!(message, extra_metadata = {})
      update!(status: "rolled_back", error_message: message,
              metadata: (metadata || {}).merge(extra_metadata), completed_at: Time.current)
    end

    def terminal?
      status.in?(TERMINAL_STATUSES)
    end

    def summary
      {
        id: id, status: status, target_kind: target_kind, method_key: method_key,
        environment: environment, ref: ref, base_ref: base_ref, dry_run: dry_run,
        detail: detail, error_message: error_message,
        started_at: started_at, completed_at: completed_at
      }
    end
  end
end
