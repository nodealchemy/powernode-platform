# frozen_string_literal: true

module Ai
  # Pull-based subscription to a data-source endpoint with a poll cadence.
  #
  # Mirrors Ai::DataConnector's sync cadence (POLL_FREQUENCIES, due_for_poll
  # scope, schedule_next_poll!, needs_poll?) but for the Phase 3 monitor loop:
  # the server-side Ai::DataSources::MonitorService walks due subscriptions,
  # runs the governed QueryService fetch, change-detects against the stored
  # last_checksum / last_etag, and records the poll outcome here. The worker
  # only fires the cron tick — all poll/fetch/change-detect logic is server-side.
  #
  # Cadence values reuse DataConnector's set (manual/hourly/daily/weekly/monthly)
  # plus two finer-grained tiers appropriate to a streaming monitor: "5min" and
  # "realtime" (the latter polled on every monitor tick, i.e. interval 0).
  class DataSourceSubscription < ApplicationRecord
    self.table_name = "ai_data_source_subscriptions"

    # Cadence: DataConnector::SYNC_FREQUENCIES + monitor-grade fine tiers.
    POLL_FREQUENCIES = %w[manual 5min hourly daily weekly monthly realtime].freeze
    STATUSES = %w[active paused error].freeze

    # Associations
    belongs_to :data_source, class_name: "Ai::DataSource", foreign_key: "ai_data_source_id"
    belongs_to :endpoint, class_name: "Ai::DataSourceEndpoint",
               foreign_key: "ai_data_source_endpoint_id"
    belongs_to :agent, class_name: "Ai::Agent", foreign_key: "ai_agent_id", optional: true

    # JSON column defaults (lambda required for mutable defaults)
    attribute :params, :json, default: -> { {} }
    attribute :metadata, :json, default: -> { {} }

    # Incremental high-watermark cursor (Phase 5). nil => no watermark yet
    # (full fetch). Persisted via record_poll!(cursor:) when the paired endpoint
    # declares incremental config; see Ai::DataSources::IncrementalSync.
    attribute :sync_cursor, :string

    # Validations
    validates :ai_data_source_id, presence: true
    validates :ai_data_source_endpoint_id, presence: true
    validates :poll_frequency, inclusion: { in: POLL_FREQUENCIES }, allow_nil: true
    validates :status, inclusion: { in: STATUSES }
    validates :consecutive_failures, numericality: { greater_than_or_equal_to: 0 }

    # Callbacks
    before_create :set_initial_poll_time

    # Scopes
    scope :active, -> { where(status: "active") }
    # Include "error" rows so a subscription that tripped the failure threshold is
    # still polled — that is the ONLY path that can clear error -> active (via
    # record_poll!), so excluding it would make the documented auto-recovery
    # unreachable and silently stop monitoring forever. Operator-set "paused" stays excluded.
    scope :due_for_poll, -> { where(status: %w[active error]).where("next_poll_at IS NOT NULL AND next_poll_at <= ?", Time.current) }
    scope :for_data_source, ->(ds) { where(ai_data_source_id: ds.is_a?(Ai::DataSource) ? ds.id : ds) }
    scope :for_endpoint, ->(ep) { where(ai_data_source_endpoint_id: ep.is_a?(Ai::DataSourceEndpoint) ? ep.id : ep) }

    # Status transitions
    def activate!
      update!(status: "active")
      schedule_next_poll!
    end

    def pause!
      update!(status: "paused", next_poll_at: nil)
    end

    def active?
      status == "active"
    end

    # Record the outcome of a single poll. Updates last_polled_at, the change
    # fingerprint (last_checksum / last_etag, only when supplied), the incremental
    # high-watermark (sync_cursor, only when supplied), schedules the next poll,
    # and maintains the consecutive_failures counter:
    #   - any error (changed: nil / status handled by caller) is not modeled here;
    #     callers pass changed:true|false on a successful poll.
    #   - a successful poll resets consecutive_failures to 0.
    #   - cursor: advances the incremental high-watermark when present (blank
    #     leaves the existing sync_cursor untouched — same opt-in semantics as
    #     checksum / etag).
    # Failures are recorded via record_failure! instead so the counter and error
    # status transition stay in one place.
    def record_poll!(changed:, checksum: nil, etag: nil, cursor: nil)
      attrs = {
        last_polled_at: Time.current,
        consecutive_failures: 0
      }
      attrs[:last_checksum] = checksum if checksum.present?
      attrs[:last_etag] = etag if etag.present?
      attrs[:sync_cursor] = cursor if cursor.present?
      # A successful poll clears a prior error status back to active.
      attrs[:status] = "active" if status == "error"

      update!(attrs)
      schedule_next_poll!
      changed
    end

    # Record a failed poll: bump the consecutive_failures counter and still
    # schedule the next attempt so a transient upstream fault self-heals. Marks
    # the subscription "error" once it has failed repeatedly so the monitor can
    # surface it without abandoning the cadence.
    def record_failure!(error_message = nil)
      failures = consecutive_failures + 1
      attrs = {
        last_polled_at: Time.current,
        consecutive_failures: failures
      }
      attrs[:status] = "error" if failures >= 5 && status == "active"
      attrs[:metadata] = metadata.merge(
        "last_error" => error_message.to_s,
        "last_error_at" => Time.current.iso8601
      ) if error_message.present?

      update!(attrs)
      # Keep polling even while erroring (unless paused) so recovery is automatic.
      schedule_next_poll! unless status == "paused"
      failures
    end

    # Advance next_poll_at by the cadence interval. "manual" never schedules;
    # "realtime" schedules immediately (interval 0) so it is picked up on the
    # next monitor tick.
    def schedule_next_poll!
      return if poll_frequency.blank? || poll_frequency == "manual"

      update!(next_poll_at: Time.current + poll_interval)
    end

    # True when this subscription is active and its next poll is due.
    def needs_poll?
      active? && next_poll_at.present? && next_poll_at <= Time.current
    end

    # Cadence interval as an ActiveSupport::Duration (0 for realtime).
    def poll_interval
      case poll_frequency
      when "realtime" then 0.seconds
      when "5min" then 5.minutes
      when "hourly" then 1.hour
      when "daily" then 1.day
      when "weekly" then 1.week
      when "monthly" then 1.month
      else 1.hour
      end
    end

    private

    # Seed next_poll_at on create for any non-manual cadence so the monitor
    # picks the subscription up without an explicit activate! call.
    def set_initial_poll_time
      return if next_poll_at.present?
      return if poll_frequency.blank? || poll_frequency == "manual"

      self.next_poll_at = Time.current
    end
  end
end
