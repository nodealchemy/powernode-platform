# frozen_string_literal: true

module Devops
  class GitRunner < ApplicationRecord
    # Table name (using git_ prefix, not devops_)
    self.table_name = "git_runners"

    # Authentication
    # Belongs to account - access controlled through account ownership

    # Concerns
    include Auditable

    # Constants
    STATUSES = %w[online offline busy].freeze
    SCOPES = %w[repository organization enterprise].freeze

    # Associations
    belongs_to :credential, class_name: "Devops::GitProviderCredential", foreign_key: "git_provider_credential_id"
    belongs_to :repository, class_name: "Devops::GitRepository", foreign_key: "git_repository_id", optional: true
    belongs_to :account

    has_one :provider, through: :credential, source: :provider

    # Delegations
    delegate :provider_type, to: :credential, allow_nil: true

    # Validations
    validates :external_id, presence: true
    validates :name, presence: true, length: { maximum: 255 }
    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :runner_scope, presence: true, inclusion: { in: SCOPES }
    validates :external_id, uniqueness: { scope: :git_provider_credential_id }
    validates :total_jobs_run, :successful_jobs, :failed_jobs,
              numericality: { only_integer: true, greater_than_or_equal_to: 0 }

    # Scopes
    scope :online, -> { where(status: "online") }
    scope :offline, -> { where(status: "offline") }
    scope :busy, -> { where(status: "busy").or(where(busy: true)) }
    scope :available, -> { online.where(busy: false) }
    scope :by_scope, ->(scope_type) { where(runner_scope: scope_type) }
    scope :repository_runners, -> { by_scope("repository") }
    scope :organization_runners, -> { by_scope("organization") }
    scope :enterprise_runners, -> { by_scope("enterprise") }
    scope :for_credential, ->(credential_id) { where(git_provider_credential_id: credential_id) }
    scope :for_repository, ->(repository_id) { where(git_repository_id: repository_id) }
    scope :recently_seen, -> { where("last_seen_at >= ?", 5.minutes.ago) }
    scope :stale, -> { where("last_seen_at < ?", 5.minutes.ago).or(where(last_seen_at: nil)) }
    scope :with_label, ->(label) { where("labels @> ?", [ label ].to_json) }

    # Callbacks
    before_save :update_status_from_busy

    # Instance Methods

    def online?
      status == "online"
    end

    def offline?
      status == "offline"
    end

    def busy?
      status == "busy" || self.busy
    end

    def available?
      online? && !busy?
    end

    def repository_runner?
      runner_scope == "repository"
    end

    def organization_runner?
      runner_scope == "organization"
    end

    def enterprise_runner?
      runner_scope == "enterprise"
    end

    def success_rate
      return 0.0 if total_jobs_run.zero?

      ((successful_jobs.to_f / total_jobs_run) * 100).round(2)
    end

    def failure_rate
      return 0.0 if total_jobs_run.zero?

      ((failed_jobs.to_f / total_jobs_run) * 100).round(2)
    end

    def workload_percentage
      # Approximate workload based on recent activity
      # This is a simplified calculation
      return 0 if offline?
      return 100 if busy?

      50 # Online but not busy
    end

    def recently_active?
      last_seen_at.present? && last_seen_at >= 5.minutes.ago
    end

    def stale?
      last_seen_at.nil? || last_seen_at < 5.minutes.ago
    end

    def has_label?(label)
      labels.include?(label)
    end

    def label_list
      labels.join(", ")
    end

    # Update methods

    def mark_online!
      update!(status: "online", last_seen_at: Time.current)
    end

    def mark_offline!
      update!(status: "offline")
    end

    def mark_busy!
      update!(status: "busy", busy: true, last_seen_at: Time.current)
    end

    def mark_available!
      update!(status: "online", busy: false, last_seen_at: Time.current)
    end

    def record_job_completion!(success:)
      increment!(:total_jobs_run)
      if success
        increment!(:successful_jobs)
      else
        increment!(:failed_jobs)
      end
    end

    def record_success!
      record_job_completion!(success: true)
    end

    def record_failure!
      record_job_completion!(success: false)
    end

    def update_labels!(new_labels)
      update!(labels: new_labels)
    end

    def add_labels!(labels_to_add)
      update!(labels: (labels + labels_to_add).uniq)
    end

    def remove_labels!(labels_to_remove)
      update!(labels: labels - labels_to_remove)
    end

    def update_from_provider_data(data)
      assign_attributes(
        name: data["name"] || name,
        status: normalize_status(data["status"]),
        busy: data["busy"] || false,
        os: data["os"],
        architecture: data["architecture"],
        version: data["version"],
        labels: extract_labels(data["labels"]),
        last_seen_at: Time.current
      )
      save!
    end

    # Class methods

    def self.sync_from_provider(credential, runner_data, scope: "repository", repository: nil)
      runner = find_or_initialize_by(
        git_provider_credential_id: credential.id,
        external_id: runner_data["id"].to_s
      )

      runner.assign_attributes(
        account: credential.account,
        git_repository_id: repository&.id,
        runner_scope: scope,
        name: runner_data["name"],
        status: runner.send(:normalize_status, runner_data["status"]),
        busy: runner_data["busy"] || false,
        os: runner_data["os"],
        architecture: runner_data["architecture"],
        version: runner_data["version"],
        labels: runner.send(:extract_labels, runner_data["labels"]),
        last_seen_at: Time.current
      )

      runner.save!
      runner
    end

    # Backwards compatibility aliases
    def git_provider_credential
      credential
    end

    def git_repository
      repository
    end

    def git_provider
      provider
    end

    private

    def update_status_from_busy
      self.status = "busy" if busy? && status == "online"
    end

    def normalize_status(provider_status)
      case provider_status&.downcase
      when "online", "active", "idle"
        "online"
      when "busy", "running"
        "busy"
      when "offline", "inactive"
        "offline"
      else
        "offline"
      end
    end

    def extract_labels(labels_data)
      return [] if labels_data.blank?

      case labels_data
      when Array
        labels_data.map do |label|
          label.is_a?(Hash) ? label["name"] : label.to_s
        end
      when String
        labels_data.split(",").map(&:strip)
      else
        []
      end
    end
  end
end
