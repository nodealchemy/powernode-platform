# frozen_string_literal: true

module Ai
  class RalphLoop < ApplicationRecord
    # ==================== Concerns ====================
    include Auditable
    include Ai::RalphLoopConcerns::StateMachine
    include Ai::RalphLoopConcerns::Scheduling
    include Ai::RalphLoopConcerns::TaskAndLearning
    include Ai::RalphLoopConcerns::StorageMetrics

    # ==================== Constants ====================
    STATUSES = %w[pending running paused completed failed cancelled].freeze
    TERMINAL_STATUSES = %w[completed failed cancelled].freeze

    # Scheduling mode enumeration
    SCHEDULING_MODES = %w[manual scheduled continuous event_triggered autonomous].freeze

    # Who drives this loop's task queue (campaign discovery/delegation control plane).
    # Flat-rate CLI executors (claude_code / external_cli) drain it via the dev-loop
    # pull queue; platform_* = the metered platform executor drains it.
    # nil = legacy (scheduling-mode-driven).
    DRIVER_KINDS = %w[claude_code external_cli platform_agent platform_team platform_mission].freeze
    # The canonical platform_agent driver of dev-improve (HIER-P2B-ENG,
    # operator ruling 2026-09-03 #4): a platform_agent delegation that names no
    # agent resolves to this seeded canonical — db/seeds/
    # ai_engineering_agents_seed.rb — via the account's own CLONE of it (the
    # HIER-P1 canonical rule; #default_agent_belongs_to_account below admits
    # nothing else). A seed identity, not config.
    PLATFORM_AGENT_DEFAULT_SLUG = "platform-developer"
    PLATFORM_DRIVER_KINDS = %w[platform_agent platform_team platform_mission].freeze
    # Vendor-neutral flat-rate executors: a Claude Code session OR any other
    # MCP-client CLI (Grok / Codex / Gemini …) drains the loop via the dev-loop pull
    # queue. Flat-rate ⇒ spends no platform token/$ budget (the inverse of the metered
    # PLATFORM_DRIVER_KINDS). `claude_code` is the original labelled instance;
    # `external_cli` generalises it to any vendor's CLI (vendor in configuration).
    FLAT_RATE_DRIVER_KINDS = %w[claude_code external_cli].freeze

    # ==================== Associations ====================
    belongs_to :account
    belongs_to :default_agent, class_name: "Ai::Agent", foreign_key: "default_agent_id", optional: true
    belongs_to :container_instance, class_name: "Devops::ContainerInstance", foreign_key: "container_instance_id", optional: true
    belongs_to :risk_contract, class_name: "Ai::CodeFactory::RiskContract",
               foreign_key: "risk_contract_id", optional: true
    belongs_to :mission, class_name: "Ai::Mission", foreign_key: "mission_id", optional: true
    belongs_to :campaign, class_name: "Ai::Campaign", foreign_key: "campaign_id", optional: true

    has_many :ralph_tasks, class_name: "Ai::RalphTask",
             foreign_key: "ralph_loop_id", dependent: :destroy
    has_many :ralph_iterations, class_name: "Ai::RalphIteration",
             foreign_key: "ralph_loop_id", dependent: :destroy

    # ==================== Validations ====================
    validates :name, presence: true, length: { maximum: 255 }
    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :default_agent, presence: true, on: :start
    validates :scheduling_mode, inclusion: { in: SCHEDULING_MODES }
    validates :driver_kind, inclusion: { in: DRIVER_KINDS }, allow_nil: true
    validate :default_agent_belongs_to_account, if: :default_agent_id_changed?
    validate :mission_belongs_to_account, if: :mission_id_changed?
    validates :current_iteration, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validates :max_iterations, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validates :repository_url, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https git ssh]),
                                         allow_blank: true }
    validates :webhook_token, uniqueness: true, allow_nil: true
    validate :validate_schedule_config, if: -> { scheduling_mode != "manual" }

    # ==================== Scopes ====================
    scope :pending, -> { where(status: "pending") }
    scope :running, -> { where(status: "running") }
    scope :paused, -> { where(status: "paused") }
    scope :completed, -> { where(status: "completed") }
    scope :failed, -> { where(status: "failed") }
    scope :cancelled, -> { where(status: "cancelled") }
    scope :terminal, -> { where(status: TERMINAL_STATUSES) }
    scope :active, -> { where(status: %w[pending running paused]) }
    scope :recent, -> { order(created_at: :desc) }
    # Metered loops: drained by the platform executor, which actually spends
    # tokens/$ (vs flat-rate CLI loops). Used for cost-per-accepted-change.
    scope :metered, -> { where(driver_kind: PLATFORM_DRIVER_KINDS) }

    # Scheduling scopes
    scope :scheduled, -> { where(scheduling_mode: %w[scheduled continuous]) }
    scope :event_triggered, -> { where(scheduling_mode: "event_triggered") }
    scope :due_for_execution, -> {
      where(schedule_paused: false)
        .where("next_scheduled_at <= ?", Time.current)
        .where(status: %w[pending running paused])
    }

    # ==================== Callbacks ====================
    before_validation :set_defaults, on: :create
    before_save :calculate_duration, if: -> { completed_at_changed? && completed_at.present? }
    before_create :generate_webhook_token, if: -> { scheduling_mode == "event_triggered" }
    after_save :update_task_counts, if: :saved_change_to_status?
    after_save :broadcast_status_update, if: :saved_change_to_status?
    after_save :update_next_scheduled_at, if: :saved_change_to_scheduling_mode?

    # ==================== Custom Errors ====================

    class InvalidTransitionError < StandardError; end

    def code_factory_mode?
      code_factory_mode == true
    end

    # Drained by a flat-rate CLI executor (Claude Code or any other MCP-client CLI —
    # Grok / Codex / Gemini …) via the dev-loop pull queue. Flat-rate is the canonical
    # "not metered" concept; prefer this over claude_code_driven? for cost/scheduling intent.
    def flat_rate_executor?
      driver_kind.in?(FLAT_RATE_DRIVER_KINDS)
    end

    # Back-compat: specifically the Claude Code instance of a flat-rate executor.
    # Use flat_rate_executor? when the intent is "any flat-rate / pull-drained loop".
    def claude_code_driven?
      driver_kind == "claude_code"
    end

    # Drained by the platform executor (agent/group/mission).
    def platform_driven?
      PLATFORM_DRIVER_KINDS.include?(driver_kind)
    end

    # Per-vendor attribution/telemetry for the flat-rate CLI executor. Sourced from
    # configuration["executor_vendor"] (e.g. "grok", "codex", "gemini") with no migration;
    # falls back to "anthropic" for the claude_code instance, a generic label for an
    # unlabelled external_cli, and nil for metered platform loops (no external CLI vendor).
    def executor_vendor
      configured = configuration&.dig("executor_vendor").presence
      return configured if configured
      return "anthropic" if claude_code_driven?
      return "external_cli" if driver_kind == "external_cli"

      nil
    end

    def run_all_active?
      configuration&.dig("run_all_active") == true
    end

    # Real (sandboxed) test execution is the DEFAULT (opt-out): the in-platform
    # sandbox runs the suite and gates task.pass! on the REAL result, replacing the
    # executor's self-reported (fabricated) checks_passed. Disable per loop with
    # configuration "real_test_execution" => false. A test command is optional —
    # when blank the worker auto-detects the framework at the repo root.
    # See Ai::Ralph::TestVerificationService.
    def real_test_execution?
      configuration&.dig("real_test_execution") != false
    end

    # Optional explicit test command; nil ⇒ the worker auto-detects the framework
    # from the repo-root manifest (mirrors TestVerificationService::FRAMEWORKS).
    def test_command
      configuration&.dig("test_command").presence
    end

    # Derive "owner/repo" from repository_url for the worker's repo lookup.
    # Handles both https://host/owner/repo(.git) and git@host:owner/repo(.git).
    def repository_full_name
      return nil if repository_url.blank?

      segments = repository_url.to_s.sub(/\.git\z/, "").split(%r{[/:]}).reject(&:blank?)
      return nil if segments.size < 2

      segments.last(2).join("/")
    end

    # ==================== G5: runtime-aware stop conditions ====================
    # Config-driven hard stops layered on top of the iteration cap. All keys live
    # in the loop's `configuration` hash (no migration):
    #   "completion"             => { "all_tasks_terminal" => true, "max_failed_pct" => 20 }
    #   "max_wall_clock_seconds" => 3600   # any runtime
    #   "max_tokens" / "max_cost" => …      # METERED (platform) loops only
    # Surfaced by #halt_reason / #runtime_cap_reason and enforced on BOTH the
    # dev-loop pull path (Ai::Tools::DevLoopTool) and the platform executor
    # (Ai::Ralph::ExecutionService), so "should I stop?" can't drift between them.
    # Flat-rate CLI loops (claude_code / external_cli) stay token/cost-UNCAPPED by design.

    # First triggered stop reason for this loop, or nil. The single source of
    # truth shared by every executor path.
    def halt_reason
      return "emergency_halt" if account&.respond_to?(:ai_suspended?) && account.ai_suspended?
      return "schedule_paused" if schedule_paused?
      return "loop_#{status}" if status.in?(%w[paused completed cancelled failed])
      return "goal_met" if goal_met?
      return "max_iterations_reached" if max_iterations_reached?

      runtime_cap_reason
    end

    # Resource caps only (wall-clock for any loop; token/$ for metered loops).
    # Split out so the platform path can layer it onto its own lifecycle guards
    # without re-deriving the account/schedule/goal checks.
    def runtime_cap_reason
      return "wall_clock_exceeded" if wall_clock_exceeded?
      return "token_cap_exceeded" if token_cap_exceeded?
      return "cost_cap_exceeded" if cost_cap_exceeded?

      nil
    end

    # configuration.completion goal evaluation — shared by the report-only queue
    # snapshot and the goal-driven terminator. Returns nil when no completion
    # criteria are configured; otherwise a hash whose :met flag says the objective
    # is satisfied. Human-decision tasks are excluded (the loop can't resolve them).
    def completion_status
      criteria = configuration&.dig("completion")
      return nil unless criteria.is_a?(Hash)

      executable = ralph_tasks.where.not(execution_type: "human")
      total = executable.count
      non_terminal = executable.where.not(status: Ai::RalphTask::TERMINAL_STATUSES).count
      failed_pct = total.zero? ? 0.0 : (executable.failed.count.to_f / total * 100).round(1)

      met = total.positive?
      met &&= non_terminal.zero? if criteria["all_tasks_terminal"]
      met &&= failed_pct <= criteria["max_failed_pct"].to_f if criteria["max_failed_pct"]

      { criteria: criteria, met: met, non_terminal: non_terminal, failed_pct: failed_pct }
    end

    def goal_met?
      assessment = completion_status
      assessment.present? && assessment[:met]
    end

    # Wall-clock budget (seconds) for the whole run; 0/blank ⇒ no cap.
    def max_wall_clock_seconds
      configuration&.dig("max_wall_clock_seconds").to_i
    end

    def wall_clock_exceeded?
      cap = max_wall_clock_seconds
      return false if cap <= 0 || started_at.blank?

      (Time.current - started_at) > cap
    end

    # Token / cost hard caps — read from configuration; 0/blank ⇒ no cap.
    def max_tokens
      configuration&.dig("max_tokens").to_i
    end

    def max_cost
      configuration&.dig("max_cost").to_f
    end

    # Accumulated spend over this loop's iterations (the metered cost surface).
    def accumulated_tokens
      ralph_iterations.sum(:tokens_input).to_i + ralph_iterations.sum(:tokens_output).to_i
    end

    def accumulated_cost
      ralph_iterations.sum(:cost).to_f
    end

    # Token/$ caps bite for METERED (platform-executor) loops only — flat-rate
    # CLI loops (claude_code / external_cli) spend no platform $, so they are uncapped.
    def token_cap_exceeded?
      return false unless platform_driven?

      max_tokens.positive? && accumulated_tokens >= max_tokens
    end

    def cost_cap_exceeded?
      return false unless platform_driven?

      max_cost.positive? && accumulated_cost >= max_cost
    end

    private

    def set_defaults
      self.status ||= "pending"
      self.scheduling_mode ||= "manual"
      self.configuration ||= {}
      self.prd_json ||= {}
      self.learnings ||= []
      self.current_iteration ||= 0
      self.max_iterations ||= 10
      self.total_tasks ||= 0
      self.completed_tasks ||= 0
      self.failed_tasks ||= 0
      self.code_factory_mode ||= false
      self.duty_cycle_config ||= {}
    end

    # Ownership, strictly. A GLOBAL canonical is deliberately NOT admitted here
    # (HIER-P2B-ENG review): the loop's default_agent is executed by
    # Ai::Ralph::TaskExecutor through Ai::AgentToolBridgeService, which resolves
    # tools and permissions as `agent.creator` — a user in the SEEDING account.
    # Wiring a global canonical onto another account's loop would therefore run
    # that account's work under a foreign principal. The canonical rule
    # (HIER-P1) is the answer: an account gets its OWN clone of the canonical,
    # with its own creator, and that clone drives the loop —
    # Ai::DevLoop::CampaignDriver#default_platform_agent mints it.
    def default_agent_belongs_to_account
      return unless default_agent && default_agent.account_id != account_id

      errors.add(:default_agent, "must belong to the same account")
    end

    def mission_belongs_to_account
      return unless mission && mission.account_id != account_id

      errors.add(:mission, "must belong to the same account")
    end

    def calculate_duration
      return unless started_at.present? && completed_at.present?

      self.duration_ms = ((completed_at - started_at) * 1000).to_i
    end

    def update_task_counts
      # Use update_columns to persist without triggering callbacks
      update_columns(
        total_tasks: ralph_tasks.count,
        completed_tasks: ralph_tasks.where(status: "passed").count,
        failed_tasks: ralph_tasks.where(status: "failed").count
      )
    end

    def broadcast_status_update
      # Use AiOrchestrationChannel for consistent real-time updates
      event_type = case status
      when "running" then saved_change_to_status? && status_before_last_save == "pending" ? "started" : "progress"
      when "completed" then "completed"
      when "failed" then "failed"
      when "paused" then "paused"
      when "cancelled" then "cancelled"
      else "progress"
      end

      AiOrchestrationChannel.broadcast_ralph_loop_event(self, event_type)
    rescue StandardError => e
      Rails.logger.warn("Failed to broadcast Ralph loop update: #{e.message}")
    end
  end
end
