# frozen_string_literal: true

class AddSchedulingToRalphLoops < ActiveRecord::Migration[8.0]
  def change
    # ===========================================================================
    # Ralph Loop Scheduling
    # ===========================================================================
    # Adds scheduling capabilities to Ralph Loops enabling:
    # - Scheduled loop execution (cron-based)
    # - Recurring iterations at defined intervals
    # - Event-triggered execution via webhooks
    # - Pause/resume scheduling
    # ===========================================================================

    # Scheduling mode
    # manual: No automatic execution (default, user-controlled)
    # scheduled: Cron-based execution at defined times
    # continuous: Fixed interval between iterations
    # event_triggered: Webhook/event-based triggers (Git push, PR merge)
    add_column :ai_ralph_loops, :scheduling_mode, :string, default: "manual"

    # Schedule configuration (JSONB for flexibility)
    # Schema: {
    #   cron_expression: "0 9 * * 1-5",     # 9am weekdays (for scheduled mode)
    #   timezone: "America/New_York",       # Timezone for cron execution
    #   start_at: "2026-02-01T00:00:00Z",   # When schedule becomes active
    #   end_at: "2026-12-31T23:59:59Z",     # When schedule expires
    #   iteration_interval_seconds: 300,    # For continuous mode (5 min)
    #   max_iterations_per_day: 100,        # Daily limit
    #   pause_on_failure: true,             # Auto-pause on failure
    #   retry_on_failure: true,             # Auto-retry on failure
    #   retry_delay_seconds: 60,            # Delay before retry
    #   skip_if_running: true               # Skip if already running
    # }
    add_column :ai_ralph_loops, :schedule_config, :jsonb, default: {}

    # Schedule state tracking
    add_column :ai_ralph_loops, :next_scheduled_at, :datetime
    add_column :ai_ralph_loops, :last_scheduled_at, :datetime
    add_column :ai_ralph_loops, :schedule_paused, :boolean, default: false
    add_column :ai_ralph_loops, :schedule_paused_at, :datetime
    add_column :ai_ralph_loops, :schedule_paused_reason, :string

    # Daily iteration tracking (for rate limiting)
    add_column :ai_ralph_loops, :daily_iteration_count, :integer, default: 0
    add_column :ai_ralph_loops, :daily_iteration_reset_at, :date

    # Webhook token for event-triggered mode
    # Allows external systems to trigger loop execution
    add_column :ai_ralph_loops, :webhook_token, :string

    # Indexes for efficient scheduling queries
    add_index :ai_ralph_loops, :scheduling_mode
    add_index :ai_ralph_loops, :next_scheduled_at
    add_index :ai_ralph_loops, [ :schedule_paused, :next_scheduled_at ],
              name: "index_ralph_loops_on_schedule_state"
    add_index :ai_ralph_loops, :webhook_token, unique: true, where: "webhook_token IS NOT NULL"

    # Constraint for valid scheduling modes
    add_check_constraint :ai_ralph_loops,
      "scheduling_mode IN ('manual', 'scheduled', 'continuous', 'event_triggered')",
      name: "ai_ralph_loops_scheduling_mode_check"
  end
end
