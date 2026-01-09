# frozen_string_literal: true

module Git
  class WorkflowTrigger < ApplicationRecord
    # ====================================
    # Associations
    # ====================================
    belongs_to :ai_workflow_trigger, class_name: "Ai::WorkflowTrigger"
    belongs_to :repository, class_name: "Git::Repository", foreign_key: "git_repository_id", optional: true

    # Delegate to workflow trigger for workflow access
    delegate :ai_workflow, to: :ai_workflow_trigger

    # ====================================
    # Constants
    # ====================================
    # Git event types that can trigger workflows
    GIT_EVENT_TYPES = %w[
      push
      pull_request
      pull_request_review
      pull_request_comment
      issue
      issue_comment
      commit_comment
      create
      delete
      fork
      release
      tag
      workflow_run
      check_run
      check_suite
      deployment
      deployment_status
      status
      merge_group
    ].freeze

    # Pull request actions
    PR_ACTIONS = %w[
      opened closed reopened synchronize
      ready_for_review converted_to_draft
      labeled unlabeled assigned unassigned
      review_requested review_request_removed
      edited
    ].freeze

    # Workflow run conclusions
    WORKFLOW_CONCLUSIONS = %w[
      success failure cancelled skipped
      timed_out action_required stale neutral
    ].freeze

    # ====================================
    # Validations
    # ====================================
    validates :event_type, presence: true, inclusion: {
      in: GIT_EVENT_TYPES,
      message: "must be a valid git event type"
    }
    validates :branch_pattern, presence: true
    validates :status, presence: true, inclusion: {
      in: %w[active paused disabled error],
      message: "must be a valid status"
    }
    validate :validate_event_filters
    validate :validate_payload_mapping

    # ====================================
    # JSON Columns
    # ====================================
    attribute :event_filters, :json, default: -> { {} }
    attribute :payload_mapping, :json, default: -> { {} }
    attribute :metadata, :json, default: -> { {} }

    # ====================================
    # Scopes
    # ====================================
    scope :active, -> { where(is_active: true, status: 'active') }
    scope :for_event, ->(event_type) { where(event_type: event_type) }
    scope :for_repository, ->(repo_id) { where(git_repository_id: repo_id) }
    scope :global, -> { where(git_repository_id: nil) }

    # ====================================
    # Instance Methods
    # ====================================

    # Check if this trigger should fire for a given webhook event
    def matches_event?(webhook_event)
      return false unless active?
      return false unless event_type == webhook_event.event_type

      # Check repository match
      if git_repository_id.present?
        return false unless webhook_event.git_repository_id == git_repository_id
      end

      # Check branch pattern match
      return false unless matches_branch?(webhook_event)

      # Check path pattern match
      return false unless matches_path?(webhook_event)

      # Check event filters
      return false unless matches_filters?(webhook_event)

      true
    end

    # Extract workflow input variables from webhook event
    def extract_variables(webhook_event)
      payload = webhook_event.payload || {}
      variables = {}

      # Apply payload mapping
      payload_mapping.each do |workflow_var, event_path|
        value = extract_value(payload, event_path)
        variables[workflow_var] = value unless value.nil?
      end

      # Add standard git context variables
      variables.merge(build_git_context(webhook_event))
    end

    # Trigger the associated workflow
    def trigger!(webhook_event, user: nil)
      return false unless matches_event?(webhook_event)
      return false unless ai_workflow_trigger.can_trigger?

      variables = extract_variables(webhook_event)
      context = {
        'git_event' => {
          'id' => webhook_event.id,
          'type' => webhook_event.event_type,
          'provider' => webhook_event.provider,
          'repository_id' => webhook_event.git_repository_id,
          'timestamp' => Time.current.iso8601
        }
      }

      # Trigger through the parent AI workflow trigger
      workflow_run = ai_workflow_trigger.trigger_workflow(variables, user: user, context: context)

      # Record the trigger
      if workflow_run
        increment!(:trigger_count)
        update_column(:last_triggered_at, Time.current)
        update!(metadata: metadata.merge({
          'last_run_id' => workflow_run.run_id,
          'last_event_id' => webhook_event.id
        }))
      end

      workflow_run
    rescue StandardError => e
      handle_error(e)
      raise
    end

    def active?
      is_active && status == 'active' && ai_workflow_trigger.active?
    end

    def activate!
      update!(status: 'active', is_active: true)
    end

    def pause!
      update!(status: 'paused')
    end

    def disable!
      update!(status: 'disabled', is_active: false)
    end

    # Backwards compatibility alias
    def git_repository
      repository
    end

    private

    def matches_branch?(webhook_event)
      return true if branch_pattern == '*'

      ref = extract_ref(webhook_event)
      return true if ref.blank?

      branch_name = ref.sub(%r{^refs/heads/}, '')

      # Support glob patterns
      if branch_pattern.include?('*')
        pattern = "^#{branch_pattern.gsub('*', '.*').gsub('?', '.')}$"
        branch_name.match?(Regexp.new(pattern))
      else
        branch_name == branch_pattern
      end
    end

    def matches_path?(webhook_event)
      return true if path_pattern.blank?

      commits = webhook_event.payload&.dig('commits') || []
      modified_files = commits.flat_map do |commit|
        (commit['added'] || []) + (commit['modified'] || []) + (commit['removed'] || [])
      end.uniq

      return false if modified_files.empty?

      # Support glob patterns for path matching
      if path_pattern.include?('*')
        pattern = "^#{path_pattern.gsub('*', '.*').gsub('?', '.')}$"
        regexp = Regexp.new(pattern)
        modified_files.any? { |file| file.match?(regexp) }
      else
        modified_files.any? { |file| file.start_with?(path_pattern) }
      end
    end

    def matches_filters?(webhook_event)
      return true if event_filters.blank?

      payload = webhook_event.payload || {}

      event_filters.all? do |filter_path, expected_value|
        actual_value = extract_value(payload, filter_path)

        if expected_value.is_a?(Array)
          expected_value.include?(actual_value)
        elsif expected_value.is_a?(String) && expected_value.start_with?('/')
          # Regex pattern
          pattern = expected_value[1..-2] # Remove leading/trailing slashes
          actual_value.to_s.match?(Regexp.new(pattern))
        else
          actual_value == expected_value
        end
      end
    end

    def extract_ref(webhook_event)
      payload = webhook_event.payload || {}

      case event_type
      when 'push'
        payload['ref']
      when 'pull_request'
        payload.dig('pull_request', 'head', 'ref')
      when 'workflow_run'
        payload.dig('workflow_run', 'head_branch')
      when 'create', 'delete'
        payload['ref']
      else
        payload['ref'] || payload.dig('pull_request', 'head', 'ref')
      end
    end

    def extract_value(hash, path)
      return nil unless hash.is_a?(Hash) && path.present?

      keys = path.split('.')
      current = hash

      keys.each do |key|
        case current
        when Hash
          # Try both string and symbol keys
          current = current[key] || current[key.to_sym]
        when Array
          # Support array indexing like [0]
          if key =~ /^\d+$/
            current = current[key.to_i]
          else
            return nil
          end
        else
          return nil
        end
      end

      current
    end

    def build_git_context(webhook_event)
      payload = webhook_event.payload || {}

      {
        'git_event_type' => webhook_event.event_type,
        'git_provider' => webhook_event.provider,
        'git_repository_id' => webhook_event.git_repository_id,
        'git_repository_name' => payload.dig('repository', 'full_name'),
        'git_ref' => extract_ref(webhook_event),
        'git_sha' => extract_sha(payload),
        'git_actor' => payload.dig('sender', 'login'),
        'git_timestamp' => payload['created_at'] || Time.current.iso8601
      }
    end

    def extract_sha(payload)
      payload['after'] ||
        payload.dig('head_commit', 'id') ||
        payload.dig('pull_request', 'head', 'sha') ||
        payload.dig('workflow_run', 'head_sha')
    end

    def validate_event_filters
      return if event_filters.blank?

      unless event_filters.is_a?(Hash)
        errors.add(:event_filters, 'must be a hash')
      end
    end

    def validate_payload_mapping
      return if payload_mapping.blank?

      unless payload_mapping.is_a?(Hash)
        errors.add(:payload_mapping, 'must be a hash')
      end
    end

    def handle_error(error)
      Rails.logger.error "Git::WorkflowTrigger #{id} error: #{error.message}"

      update!(
        status: 'error',
        metadata: metadata.merge({
          'error_message' => error.message,
          'error_timestamp' => Time.current.iso8601,
          'error_count' => (metadata['error_count'] || 0) + 1
        })
      )
    end
  end
end
