# frozen_string_literal: true

module Mcp
  module NodeExecutors
    # Git Comment node executor - posts comments on PRs/issues
    #
    # Configuration:
    # - comment_body: The comment text to post
    # - target_type: "pull_request" or "issue" (default: pull_request)
    # - target_number: PR or issue number (can be from trigger context)
    # - repository_id: UUID of GitRepository
    #
    class GitComment < Base
      protected

      def perform_execution
        log_info "Posting git comment"

        comment_body = resolve_value(configuration["comment_body"])
        target_type = configuration["target_type"] || "pull_request"
        target_number = resolve_value(configuration["target_number"]) ||
                        get_variable("trigger.pull_request.number") ||
                        get_variable("pr_number")
        repository_id = resolve_value(configuration["repository_id"])

        validate_configuration!(comment_body, target_number)

        comment_context = {
          comment_body: comment_body,
          target_type: target_type,
          target_number: target_number,
          repository_id: repository_id
        }

        log_info "Comment context: #{comment_context.slice(:target_type, :target_number)}"

        if repository_id.present? && target_number.present?
          post_comment(comment_context)
        else
          build_output(comment_context, nil)
        end
      end

      private

      def validate_configuration!(comment_body, target_number)
        errors = []
        errors << "comment_body is required" if comment_body.blank?
        errors << "target_number is required" if target_number.blank?

        raise ArgumentError, "Comment configuration errors: #{errors.join(', ')}" if errors.any?
      end

      def resolve_value(value)
        return nil if value.nil?

        if value.is_a?(String) && value.match?(/\$\{\{(.+?)\}\}|\{\{(.+?)\}\}/)
          variable_name = value.match(/\$?\{\{(.+?)\}\}/)[1].strip
          get_variable(variable_name) || value
        else
          value
        end
      end

      def post_comment(comment_context)
        repository = GitRepository.find_by(id: comment_context[:repository_id])
        raise ArgumentError, "Repository not found" unless repository

        credential = repository.git_provider_credential
        raise ArgumentError, "No credential found" unless credential

        api_client = Git::ApiClient.for(credential)

        result = if comment_context[:target_type] == "issue"
                   api_client.create_issue_comment(
                     repository.owner,
                     repository.name,
                     comment_context[:target_number],
                     comment_context[:comment_body]
                   )
                 else
                   api_client.create_pr_comment(
                     repository.owner,
                     repository.name,
                     comment_context[:target_number],
                     comment_context[:comment_body]
                   )
                 end

        build_output(comment_context, result)
      rescue StandardError => e
        build_error_output(comment_context, e)
      end

      def build_output(comment_context, result)
        {
          output: {
            comment_posted: result.present?,
            target_type: comment_context[:target_type],
            target_number: comment_context[:target_number]
          },
          data: {
            comment_id: result&.dig(:id),
            comment_url: result&.dig(:html_url) || result&.dig(:url),
            target_type: comment_context[:target_type],
            target_number: comment_context[:target_number],
            body: comment_context[:comment_body]
          },
          metadata: {
            node_id: @node.node_id,
            node_type: "git_comment",
            executed_at: Time.current.iso8601
          }
        }
      end

      def build_error_output(comment_context, error)
        {
          output: {
            comment_posted: false,
            error: error.message
          },
          data: {
            target_type: comment_context[:target_type],
            target_number: comment_context[:target_number]
          },
          metadata: {
            node_id: @node.node_id,
            node_type: "git_comment",
            executed_at: Time.current.iso8601,
            failed: true,
            error: error.message
          }
        }
      end
    end
  end
end
