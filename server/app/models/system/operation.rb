# frozen_string_literal: true

module System
  class Operation < BaseRecord
    include System::Base

    # === Constants ===
    STATUSES = %w[pending scheduled running complete failed aborted cancelled].freeze
    COMMANDS = %w[
      start stop restart terminate reboot
      provision deprovision
      create_volume delete_volume attach_volume detach_volume
      create_snapshot delete_snapshot restore_snapshot
      create_network delete_network
      sync_modules apply_config
      backup restore
      custom
    ].freeze

    # === Associations ===
    belongs_to :account
    belongs_to :operable, polymorphic: true, optional: true
    belongs_to :initiated_by, class_name: 'User', optional: true

    # === Validations ===
    validates :command, presence: true
    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :progress, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }

    # === Scopes ===
    scope :by_status, ->(status) { where(status: status) }
    scope :pending, -> { by_status('pending') }
    scope :scheduled, -> { by_status('scheduled') }
    scope :running, -> { by_status('running') }
    scope :complete, -> { by_status('complete') }
    scope :failed, -> { by_status('failed') }
    scope :aborted, -> { by_status('aborted') }
    scope :cancelled, -> { by_status('cancelled') }

    scope :active, -> { where(status: %w[pending scheduled running]) }
    scope :finished, -> { where(status: %w[complete failed aborted cancelled]) }
    scope :exclusive, -> { where(exclusive: true) }
    scope :non_exclusive, -> { where(exclusive: false) }

    scope :for_operable, ->(operable) { where(operable: operable) }
    scope :by_command, ->(command) { where(command: command) }
    scope :recent, -> { order(created_at: :desc) }
    scope :scheduled_before, ->(time) { where('scheduled_at <= ?', time) }

    # === Status Predicates ===
    STATUSES.each do |status_name|
      define_method("#{status_name}?") { status == status_name }
    end

    # === State Transitions ===
    def can_start?
      pending? || scheduled?
    end

    def can_complete?
      running?
    end

    def can_fail?
      running?
    end

    def can_abort?
      running?
    end

    def can_cancel?
      pending? || scheduled?
    end

    def start!
      return false unless can_start?
      update!(status: 'running', started_at: Time.current, progress: 0)
      add_event('started', 'Operation started')
      true
    end

    def complete!
      return false unless can_complete?
      update!(status: 'complete', completed_at: Time.current, progress: 100)
      add_event('completed', 'Operation completed successfully')
      true
    end

    def fail!(message = nil)
      return false unless can_fail?
      update!(status: 'failed', completed_at: Time.current, error_message: message)
      add_event('failed', message || 'Operation failed')
      true
    end

    def abort!(message = nil)
      return false unless can_abort?
      update!(status: 'aborted', completed_at: Time.current, error_message: message)
      add_event('aborted', message || 'Operation aborted')
      true
    end

    def cancel!(message = nil)
      return false unless can_cancel?
      update!(status: 'cancelled', completed_at: Time.current, error_message: message)
      add_event('cancelled', message || 'Operation cancelled')
      true
    end

    def update_progress!(new_progress, message = nil)
      return false unless running?
      update!(progress: new_progress.clamp(0, 100))
      add_event('progress', message || "Progress: #{new_progress}%")
      true
    end

    # === Event Management ===
    def add_event(event_type, message, data = {})
      new_event = {
        type: event_type,
        message: message,
        timestamp: Time.current.iso8601,
        data: data
      }
      self.events = (events || []) + [new_event]
      save! if persisted?
      new_event
    end

    def last_event
      events&.last
    end

    # === Duration ===
    def duration
      return nil unless started_at
      end_time = completed_at || Time.current
      end_time - started_at
    end

    def duration_formatted
      return nil unless duration
      hours = (duration / 3600).to_i
      minutes = ((duration % 3600) / 60).to_i
      seconds = (duration % 60).to_i

      if hours > 0
        "#{hours}h #{minutes}m #{seconds}s"
      elsif minutes > 0
        "#{minutes}m #{seconds}s"
      else
        "#{seconds}s"
      end
    end

    # === Active Check ===
    def active?
      %w[pending scheduled running].include?(status)
    end

    def finished?
      %w[complete failed aborted cancelled].include?(status)
    end
  end
end
