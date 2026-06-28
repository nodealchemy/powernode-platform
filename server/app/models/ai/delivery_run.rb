# frozen_string_literal: true

module Ai
  # Durable record of one progressive DELIVERY of a ref to a target via a strategy
  # (Ai::Delivery::Orchestrator). The "direct" strategy delegates to Ai::Deploy (linked via
  # deploy_run); "canary"/"blue_green" capture the staged rollout plan + step results. This is
  # the multi-phase wrapper around the single-shot Ai::DeployRun.
  class DeliveryRun < ApplicationRecord
    self.table_name = "ai_delivery_runs"

    STRATEGIES = %w[direct canary blue_green].freeze
    STATUSES = %w[pending running planned dry_run succeeded failed rolled_back].freeze
    TERMINAL_STATUSES = %w[planned dry_run succeeded failed rolled_back].freeze
    # Maps an underlying DeployRun status onto a delivery status (direct strategy).
    DEPLOY_STATUS_MAP = {
      "succeeded" => "succeeded", "failed" => "failed", "rolled_back" => "rolled_back",
      "dry_run" => "dry_run", "skipped" => "failed", "blocked" => "failed"
    }.freeze

    belongs_to :account
    belongs_to :campaign, class_name: "Ai::Campaign", foreign_key: "campaign_id", optional: true
    belongs_to :campaign_land, class_name: "Ai::CampaignLand", foreign_key: "campaign_land_id", optional: true
    belongs_to :repository, class_name: "Devops::GitRepository", foreign_key: "repository_id", optional: true
    belongs_to :triggered_by, class_name: "User", foreign_key: "triggered_by_id", optional: true
    belongs_to :deploy_run, class_name: "Ai::DeployRun", foreign_key: "deploy_run_id", optional: true

    validates :target_kind, presence: true
    validates :strategy, presence: true, inclusion: { in: STRATEGIES }
    validates :status, presence: true, inclusion: { in: STATUSES }

    scope :recent, ->(limit = 50) { order(created_at: :desc).limit(limit) }
    scope :for_account, ->(acct) { where(account_id: acct.id) }

    def start!
      update!(status: "running", started_at: started_at || Time.current)
    end

    # Link + mirror the underlying single-shot deploy (direct strategy).
    def attach_deploy_run!(run)
      update!(
        deploy_run: run,
        status: DEPLOY_STATUS_MAP.fetch(run.status.to_s, "failed"),
        detail: run.detail,
        error_message: run.error_message,
        metadata: (metadata || {}).merge("deploy_run_id" => run.id, "method_key" => run.method_key),
        completed_at: Time.current
      )
    end

    # Record the staged rollout plan for a progressive strategy (canary/blue_green).
    # Real step execution is driven separately; here the plan is captured + the run parked
    # as "planned" (or "dry_run" when this was a dry run).
    def plan!(steps_plan, dry: dry_run)
      update!(
        status: dry ? "dry_run" : "planned",
        steps: Array(steps_plan),
        detail: "#{strategy} rollout plan: #{Array(steps_plan).size} step(s)",
        completed_at: dry ? Time.current : nil
      )
    end

    def succeed!(detail = nil)
      update!(status: "succeeded", detail: detail || self.detail, completed_at: Time.current)
    end

    def fail!(message)
      update!(status: "failed", error_message: message, completed_at: Time.current)
    end

    def mark_rolled_back!(message = nil)
      update!(status: "rolled_back", error_message: message, completed_at: Time.current)
    end

    def summary
      {
        id: id, strategy: strategy, status: status, dry_run: dry_run,
        target_kind: target_kind, environment: environment, ref: ref, base_ref: base_ref,
        deploy_run_id: deploy_run_id, steps: steps, detail: detail, error_message: error_message,
        started_at: started_at, completed_at: completed_at
      }
    end
  end
end
