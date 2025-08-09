class WebhookEvent < ApplicationRecord
  include AASM

  belongs_to :account, optional: true
  belongs_to :payment, optional: true

  validates :provider, presence: true, inclusion: { in: %w[stripe paypal] }
  validates :event_type, presence: true
  validates :provider_event_id, presence: true, uniqueness: true
  validates :event_data, presence: true
  validates :retry_count, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 10 }

  scope :pending, -> { where(status: "pending") }
  scope :failed, -> { where(status: "failed") }
  scope :processed, -> { where(status: "processed") }
  scope :for_provider, ->(provider) { where(provider: provider) }
  scope :recent, -> { order(created_at: :desc) }

  aasm column: :status do
    state :pending, initial: true
    state :processing
    state :processed
    state :failed
    state :skipped

    event :start_processing do
      transitions from: [ :pending, :failed ], to: :processing
    end

    event :mark_processed do
      transitions from: :processing, to: :processed do
        after do
          update!(processed_at: Time.current)
        end
      end
    end

    event :mark_failed do
      transitions from: :processing, to: :failed do
        after do
          increment!(:retry_count)
        end
      end
    end

    event :skip do
      transitions from: [ :pending, :failed ], to: :skipped
    end
  end

  def event_data_parsed
    @event_data_parsed ||= JSON.parse(event_data)
  rescue JSON::ParserError
    {}
  end

  def metadata_parsed
    @metadata_parsed ||= JSON.parse(metadata)
  rescue JSON::ParserError
    {}
  end

  def can_retry?
    failed? && retry_count < 10
  end

  def should_retry?
    can_retry? && !permanent_failure?
  end

  def next_retry_at
    return nil unless should_retry?

    # Exponential backoff: 1min, 5min, 15min, 1hr, 4hr, 12hr, 24hr
    delays = [ 1.minute, 5.minutes, 15.minutes, 1.hour, 4.hours, 12.hours, 24.hours ]
    delay = delays[retry_count - 1] || 24.hours

    updated_at + delay
  end

  def stripe?
    provider == "stripe"
  end

  def paypal?
    provider == "paypal"
  end

  def add_error(message)
    update!(error_message: message)
  end

  def add_metadata(key, value)
    current_metadata = metadata_parsed
    current_metadata[key.to_s] = value
    update!(metadata: current_metadata.to_json)
  end

  private

  def permanent_failure?
    # Define conditions for permanent failures that shouldn't be retried
    return false if error_message.blank?

    permanent_error_patterns = [
      /signature verification failed/i,
      /invalid webhook/i,
      /malformed/i,
      /authentication failed/i
    ]

    permanent_error_patterns.any? { |pattern| error_message.match?(pattern) }
  end
end
