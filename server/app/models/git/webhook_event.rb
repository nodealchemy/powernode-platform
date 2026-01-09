# frozen_string_literal: true

module Git
  class WebhookEvent < ApplicationRecord
    # Authentication
    # Belongs to account - access controlled through account ownership

    # Concerns
    include Auditable

    # Constants
    STATUSES = %w[pending processing processed failed queued_failed].freeze
    EVENT_TYPES = %w[
      push
      pull_request
      pull_request_review
      pull_request_review_comment
      merge_request
      issues
      issue_comment
      create
      delete
      fork
      release
      workflow_run
      workflow_job
      deployment
      deployment_status
      check_run
      check_suite
      status
      ping
    ].freeze

    # Associations
    belongs_to :repository, class_name: "Git::Repository", foreign_key: "git_repository_id", optional: true
    belongs_to :git_provider, class_name: "Git::Provider", foreign_key: "git_provider_id"
    belongs_to :account

    # Validations
    validates :event_type, presence: true, length: { maximum: 100 },
              inclusion: { in: EVENT_TYPES, message: "%{value} is not a valid event type" },
              allow_blank: false
    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :payload, presence: true

    # Scopes
    scope :pending, -> { where(status: "pending") }
    scope :processing, -> { where(status: "processing") }
    scope :processed, -> { where(status: "processed") }
    scope :failed, -> { where(status: "failed") }
    scope :unprocessed, -> { where(status: %w[pending processing]) }
    scope :by_event_type, ->(type) { where(event_type: type) }
    scope :by_type, ->(type) { by_event_type(type) } # Alias for backwards compatibility
    scope :by_action, ->(action) { where(action: action) }
    scope :recent, ->(limit = 50) { order(created_at: :desc).limit(limit) }
    scope :for_repository, ->(repo) { where(git_repository_id: repo.is_a?(Git::Repository) ? repo.id : repo) }
    scope :retryable, -> { failed.where("retry_count < ?", 3) }

    # Callbacks
    before_validation :set_default_status, on: :create
    before_create :generate_delivery_id

    # Instance Methods

    # Convenience method to get provider type string
    def provider
      git_provider&.provider_type
    end

    def pending?
      status == "pending"
    end

    def processing?
      status == "processing"
    end

    def processed?
      status == "processed"
    end

    def failed?
      status == "failed"
    end

    def mark_processing!
      update!(status: "processing")
    end

    def mark_processed!(result = {})
      update!(
        status: "processed",
        processed_at: Time.current,
        processing_result: result
      )
    end

    def mark_failed!(error_message)
      update!(
        status: "failed",
        error_message: error_message,
        retry_count: retry_count + 1
      )
    end

    def retryable?
      failed? && retry_count < 3
    end

    alias can_retry? retryable?

    def retry!
      raise StandardError, "Max retries exceeded" unless retryable?

      update!(status: "pending")
      Git::WebhookProcessingJob.perform_async(id)
      true
    end

    def repository_full_name
      payload.dig("repository", "full_name")
    end

    def push_event?
      event_type == "push"
    end

    def pull_request_event?
      event_type == "pull_request"
    end

    def workflow_event?
      event_type.start_with?("workflow_")
    end

    def ci_event?
      %w[workflow_run workflow_job check_run check_suite].include?(event_type)
    end

    def commit_sha
      sha || payload.dig("head_commit", "id") || payload.dig("after")
    end

    def branch_name
      return nil unless ref.present?

      ref.sub(%r{^refs/heads/}, "")
    end

    def tag_name
      return nil unless ref.present? && ref.start_with?("refs/tags/")

      ref.sub(%r{^refs/tags/}, "")
    end

    def sender_info
      {
        username: sender_username,
        id: sender_id,
        avatar_url: payload.dig("sender", "avatar_url")
      }
    end

    def payload_summary
      case event_type
      when "push"
        commits = payload["commits"] || []
        "#{commits.count} commit(s) to #{branch_name}"
      when "pull_request"
        "PR ##{payload.dig('pull_request', 'number')}: #{action}"
      when "workflow_run"
        "Workflow: #{payload.dig('workflow_run', 'name')} - #{payload.dig('workflow_run', 'conclusion')}"
      else
        action.presence || event_type
      end
    end

    # Backwards compatibility alias
    def git_repository
      repository
    end

    private

    def set_default_status
      self.status ||= "pending"
    end

    def generate_delivery_id
      self.delivery_id ||= SecureRandom.uuid
    end
  end
end
