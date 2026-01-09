# frozen_string_literal: true

module Mcp
  module NodeExecutors
    # Git Create Check node executor - creates GitHub Check Runs
    #
    # Check runs provide richer status information than commit statuses,
    # including annotations, detailed output, and live updates.
    #
    # Configuration:
    # - repository_id: UUID of Git::Repository
    # - sha: Git commit SHA to create check for
    # - name: Check run name (required)
    # - status: Check status (queued, in_progress, completed)
    # - conclusion: Check conclusion when completed (success, failure, neutral, cancelled, skipped, timed_out, action_required)
    # - title: Output title
    # - summary: Output summary (supports markdown)
    # - text: Extended output text (supports markdown)
    # - details_url: URL for "Details" link
    # - external_id: External reference ID
    # - annotations: Array of code annotations
    #
    # Note: Check Runs are a GitHub-specific feature. For other providers,
    # this executor falls back to creating a commit status.
    #
    class GitCreateCheck < Base
      VALID_STATUSES = %w[queued in_progress completed].freeze
      VALID_CONCLUSIONS = %w[success failure neutral cancelled skipped timed_out action_required].freeze
      MAX_ANNOTATIONS_PER_REQUEST = 50
      MAX_SUMMARY_LENGTH = 65_535
      MAX_TEXT_LENGTH = 65_535

      protected

      def perform_execution
        log_info "Creating git check run"

        # Extract configuration
        repository_id = resolve_value(configuration["repository_id"])
        sha = resolve_value(configuration["sha"])
        name = resolve_value(configuration["name"])
        status = resolve_value(configuration["status"]) || "queued"
        conclusion = resolve_value(configuration["conclusion"])
        title = resolve_value(configuration["title"])
        summary = resolve_value(configuration["summary"])
        text = resolve_value(configuration["text"])
        details_url = resolve_value(configuration["details_url"])
        external_id = resolve_value(configuration["external_id"])
        annotations = configuration["annotations"] || []

        # Validate configuration
        validate_configuration!(repository_id, sha, name, status, conclusion)

        # Get repository and API client
        repository = find_repository(repository_id)
        api_client = build_api_client(repository)

        # Create check run based on provider capabilities
        result = if supports_check_runs?(api_client)
          create_check_run(
            api_client: api_client,
            repository: repository,
            sha: sha,
            name: name,
            status: status,
            conclusion: conclusion,
            title: title,
            summary: summary,
            text: text,
            details_url: details_url,
            external_id: external_id,
            annotations: annotations
          )
        else
          # Fallback to commit status for non-GitHub providers
          create_fallback_commit_status(
            api_client: api_client,
            repository: repository,
            sha: sha,
            name: name,
            conclusion: conclusion || map_status_to_conclusion(status),
            summary: summary
          )
        end

        build_output(result, repository, sha, name, status, conclusion)
      end

      private

      def validate_configuration!(repository_id, sha, name, status, conclusion)
        errors = []
        errors << "repository_id is required" if repository_id.blank?
        errors << "sha is required" if sha.blank?
        errors << "name is required" if name.blank?
        errors << "status must be one of: #{VALID_STATUSES.join(', ')}" unless VALID_STATUSES.include?(status)

        if status == "completed" && conclusion.blank?
          errors << "conclusion is required when status is 'completed'"
        end

        if conclusion.present? && !VALID_CONCLUSIONS.include?(conclusion)
          errors << "conclusion must be one of: #{VALID_CONCLUSIONS.join(', ')}"
        end

        if errors.any?
          raise ArgumentError, "Git Create Check configuration errors: #{errors.join(', ')}"
        end
      end

      def find_repository(repository_id)
        repository = Git::Repository.find_by(id: repository_id)
        raise ArgumentError, "Repository not found: #{repository_id}" unless repository
        repository
      end

      def build_api_client(repository)
        credential = repository.git_provider_credential
        raise ArgumentError, "No credential found for repository" unless credential

        Git::ApiClient.for(credential)
      end

      def supports_check_runs?(api_client)
        api_client.is_a?(Git::GithubApiClient)
      end

      def create_check_run(api_client:, repository:, sha:, name:, status:, conclusion:, title:, summary:, text:, details_url:, external_id:, annotations:)
        payload = {
          name: name,
          head_sha: sha,
          status: status
        }

        # Add conclusion if completed
        payload[:conclusion] = conclusion if status == "completed" && conclusion.present?

        # Add optional fields
        payload[:details_url] = details_url if details_url.present?
        payload[:external_id] = external_id if external_id.present?

        # Add output if any content provided
        if title.present? || summary.present? || text.present? || annotations.any?
          payload[:output] = {
            title: title || name,
            summary: truncate_text(summary, MAX_SUMMARY_LENGTH) || "Check run created by Powernode workflow"
          }
          payload[:output][:text] = truncate_text(text, MAX_TEXT_LENGTH) if text.present?

          if annotations.any?
            payload[:output][:annotations] = format_annotations(annotations).first(MAX_ANNOTATIONS_PER_REQUEST)
          end
        end

        # GitHub Check Runs API endpoint
        if api_client.respond_to?(:create_check_run)
          api_client.create_check_run(repository.owner, repository.name, payload)
        else
          # Manual API call for GitHub
          create_check_run_via_api(api_client, repository, payload)
        end
      end

      def create_check_run_via_api(api_client, repository, payload)
        # The GitHub API client doesn't have create_check_run, so we need to add it
        # For now, fall back to commit status
        log_info "Check runs API not available, falling back to commit status"

        state = case payload[:conclusion]
        when "success", "neutral", "skipped" then "success"
        when "failure", "cancelled", "timed_out", "action_required" then "failure"
        else "pending"
        end

        api_client.create_commit_status(
          repository.owner,
          repository.name,
          payload[:head_sha],
          state,
          {
            context: payload[:name],
            description: payload.dig(:output, :summary)&.truncate(140),
            target_url: payload[:details_url]
          }.compact
        ).merge(check_run_fallback: true)
      end

      def create_fallback_commit_status(api_client:, repository:, sha:, name:, conclusion:, summary:)
        state = case conclusion
        when "success", "neutral", "skipped" then "success"
        when "failure", "cancelled", "timed_out", "action_required" then "failure"
        when nil then "pending"
        else "pending"
        end

        api_client.create_commit_status(
          repository.owner,
          repository.name,
          sha,
          state,
          {
            context: name,
            description: summary&.truncate(140)
          }.compact
        ).merge(check_run_fallback: true)
      end

      def map_status_to_conclusion(status)
        case status
        when "completed" then "success"
        when "in_progress" then nil
        when "queued" then nil
        else nil
        end
      end

      def format_annotations(annotations)
        annotations.map do |annotation|
          {
            path: annotation["path"] || annotation[:path],
            start_line: annotation["start_line"] || annotation[:start_line],
            end_line: annotation["end_line"] || annotation[:end_line] || annotation["start_line"] || annotation[:start_line],
            annotation_level: annotation["level"] || annotation[:level] || "notice",
            message: annotation["message"] || annotation[:message],
            title: annotation["title"] || annotation[:title],
            raw_details: annotation["raw_details"] || annotation[:raw_details]
          }.compact
        end
      end

      def truncate_text(text, max_length)
        return nil if text.blank?
        text.truncate(max_length)
      end

      def resolve_value(value)
        return nil if value.nil?

        if value.is_a?(String) && value.match?(/\{\{(.+?)\}\}/)
          variable_name = value.match(/\{\{(.+?)\}\}/)[1].strip
          get_variable(variable_name) || value
        else
          value
        end
      end

      def build_output(result, repository, sha, name, status, conclusion)
        if result[:success]
          {
            output: {
              created: true,
              name: name,
              status: status,
              conclusion: conclusion,
              sha: sha,
              check_run_fallback: result[:check_run_fallback] || false
            },
            data: {
              repository_id: repository.id,
              repository_name: "#{repository.owner}/#{repository.name}",
              sha: sha,
              check_id: result[:id],
              check_url: result[:html_url] || result[:url]
            },
            metadata: {
              node_id: @node.node_id,
              node_type: "git_create_check",
              executed_at: Time.current.iso8601
            }
          }
        else
          {
            output: {
              created: false,
              error: result[:error]
            },
            data: {
              repository_id: repository.id,
              sha: sha,
              name: name
            },
            metadata: {
              node_id: @node.node_id,
              node_type: "git_create_check",
              executed_at: Time.current.iso8601,
              failed: true
            }
          }
        end
      end
    end
  end
end
