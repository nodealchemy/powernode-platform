# frozen_string_literal: true

# Durable retry record for cleanup that has to follow a committed deletion (the
# Vault purge after Account#destroy!). The server runs no Sidekiq: the worker's
# PlatformPurgeSweepJob calls POST /api/v1/internal/platform/purge_tasks/sweep,
# which runs run_due!.
#
# States: pending -> completed | dead. A task goes dead after MAX_ATTEMPTS failures
# (an operator must look; it is never retried silently forever) or when its subject
# account still exists (a purge must never touch a live account's secrets).
class PlatformPurgeTask < ApplicationRecord
  KINDS = %w[secret_store_account].freeze
  STATUSES = %w[pending completed dead].freeze
  MAX_ATTEMPTS = 10
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
  rescue ActiveRecord::RecordNotUnique
    retry
  end

  def self.backoff(attempts)
    [ 2**attempts * 30, MAX_BACKOFF.to_i ].min.seconds
  end

  # Runs every due task once. Returns { completed:, failed:, dead: }.
  # A task is CLAIMED in a short transaction (FOR UPDATE SKIP LOCKED, then its attempt count and next
  # attempt time are advanced, which is also what hides it from an overlapping sweep), and the purge
  # runs AFTER that transaction commits: no row lock is held across the Vault call, and even a database
  # error inside the purge cannot leave the task due for an instant retry.
  def self.run_due!(limit: 50)
    result = { completed: 0, failed: 0, dead: 0 }
    claimed = []
    limit.times do
      task = claim_next(claimed)
      break unless task

      claimed << task.id
      result[task.attempt!] += 1
    end
    result
  end

  def self.claim_next(already)
    transaction do
      task = due.where.not(id: already).order(:next_attempt_at).lock("FOR UPDATE SKIP LOCKED").first
      next unless task

      task.update!(attempts: task.attempts + 1, next_attempt_at: Time.current + backoff(task.attempts + 1))
      task
    end
  end

  # One attempt on a CLAIMED task (attempts already advanced). Returns :completed, :failed or :dead.
  # Never raises: a failure to record the outcome is logged and the task stays pending, backed off.
  def attempt!
    return settle_dead!("AccountStillExists") if Account.exists?(subject_id)

    purge!
    update!(status: "completed", completed_at: Time.current)
    :completed
  rescue StandardError => e
    record_failure(e)
  end

  private

  def purge!
    case kind
    when "secret_store_account"
      Security::SecretStore.purge_account(account_id: subject_id)
    end
  end

  def record_failure(error)
    Rails.logger.error("[PlatformPurgeTask] #{kind} attempt #{attempts} failed: #{error.class}")
    return settle_dead!(error.class.name) if attempts >= MAX_ATTEMPTS

    update!(last_error_class: error.class.name)
    :failed
  rescue StandardError => e
    Rails.logger.error("[PlatformPurgeTask] could not record the outcome of #{kind}: #{e.class}")
    :failed
  end

  def settle_dead!(error_class)
    update!(status: "dead", last_error_class: error_class)
    Rails.logger.error("[PlatformPurgeTask] #{kind} for #{subject_id} is dead (#{error_class}); needs an operator")
    :dead
  end
end
