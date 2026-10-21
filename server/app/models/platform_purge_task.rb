# frozen_string_literal: true

# Durable retry record for cleanup that has to follow a committed deletion (the
# Vault purge after Account#destroy!). The server runs no Sidekiq: the worker's
# PlatformPurgeSweepJob calls POST /api/v1/internal/platform/purge_tasks/sweep,
# which runs run_due!.
class PlatformPurgeTask < ApplicationRecord
  KINDS = %w[secret_store_account].freeze
  STATUSES = %w[pending completed].freeze
  MAX_BACKOFF = 6.hours

  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }
  validates :subject_id, :next_attempt_at, presence: true

  scope :due, -> { where(status: "pending").where(next_attempt_at: ..Time.current) }

  # Records a failed first attempt. Error CLASS only: messages can carry secrets.
  def self.enqueue!(kind:, subject_id:, error:)
    task = find_or_initialize_by(kind: kind, subject_id: subject_id, status: "pending")
    task.attempts = task.new_record? ? 1 : task.attempts + 1
    task.last_error_class = error.class.name
    task.next_attempt_at = Time.current + backoff(task.attempts)
    task.save!
    task
  end

  def self.backoff(attempts)
    [ 2**attempts * 30, MAX_BACKOFF.to_i ].min.seconds
  end

  # Runs every due task once. Returns { completed:, failed: }.
  def self.run_due!(limit: 50)
    result = { completed: 0, failed: 0 }
    due.order(:next_attempt_at).limit(limit).each do |task|
      task.run!
      result[:completed] += 1
    rescue StandardError => e
      task.update!(attempts: task.attempts + 1, last_error_class: e.class.name,
                   next_attempt_at: Time.current + backoff(task.attempts + 1))
      Rails.logger.error("[PlatformPurgeTask] #{task.kind} retry failed: #{e.class}")
      result[:failed] += 1
    end
    result
  end

  def run!
    case kind
    when "secret_store_account"
      Security::SecretStore.purge_account(account_id: subject_id)
    end
    update!(status: "completed", completed_at: Time.current, attempts: attempts + 1)
  end
end
