# frozen_string_literal: true

module Mcp
  module NodeExecutors
    # Git Pull Request node executor - creates or updates a pull request
    #
    # Configuration:
    # - title: PR title
    # - body: PR description/body
    # - head: Source branch (defaults to current branch)
    # - base: Target branch (defaults to main)
    # - draft: Create as draft PR (default: false)
    # - repository_id: UUID of Devops::GitRepository
    # - labels: Array of labels to add
    # - reviewers: Array of reviewer usernames
    #
    class GitPullRequest < Base
      protected

      def perform_execution
        log_info "Creating pull request"

        # Resolve configuration
        title = resolve_value(configuration["title"])
        body = resolve_value(configuration["body"]) || ""
        head = resolve_value(configuration["head"]) || get_variable("branch_name")
        base = resolve_value(configuration["base"]) || "main"
        draft = configuration.fetch("draft", false)
        repository_id = resolve_value(configuration["repository_id"])
        labels = configuration["labels"] || []
        reviewers = configuration["reviewers"] || []

        validate_configuration!(title, head)

        pr_context = {
          title: title,
          body: body,
          head: head,
          base: base,
          draft: draft,
          repository_id: repository_id,
          labels: labels,
          reviewers: reviewers
        }

        log_info "PR context: #{pr_context.slice(:title, :head, :base)}"

        # If repository_id is provided, actually create the PR
        if repository_id.present?
          create_pull_request(pr_context)
        else
          build_output(pr_context, nil)
        end
      end

      private

      def validate_configuration!(title, head)
        errors = []
        errors << "title is required" if title.blank?
        errors << "head branch is required" if head.blank?

        raise ArgumentError, "PR configuration errors: #{errors.join(', ')}" if errors.any?
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

      def create_pull_request(pr_context)
        repository = Devops::GitRepository.find_by(id: pr_context[:repository_id])
        raise ArgumentError, "Repository not found" unless repository

        credential = repository.git_provider_credential
        raise ArgumentError, "No credential found for repository" unless credential

        api_client = Devops::Git::ApiClient.for(credential)

        result = api_client.create_pull_request(
          repository.owner,
          repository.name,
          title: pr_context[:title],
          body: pr_context[:body],
          head: pr_context[:head],
          base: pr_context[:base],
          draft: pr_context[:draft]
        )

        build_output(pr_context, result)
      rescue StandardError => e
        build_error_output(pr_context, e)
      end

      def build_output(pr_context, result)
        {
          output: {
            pr_created: result.present?,
            title: pr_context[:title],
            head: pr_context[:head],
            base: pr_context[:base]
          },
          data: {
            pr_number: result&.dig(:number),
            pr_url: result&.dig(:html_url) || result&.dig(:url),
            pr_id: result&.dig(:id),
            title: pr_context[:title],
            body: pr_context[:body],
            head: pr_context[:head],
            base: pr_context[:base],
            draft: pr_context[:draft],
            state: result&.dig(:state) || "pending"
          },
          metadata: {
            node_id: @node.node_id,
            node_type: "git_pull_request",
            executed_at: Time.current.iso8601
          }
        }
      end

      def build_error_output(pr_context, error)
        {
          output: {
            pr_created: false,
            error: error.message
          },
          data: {
            title: pr_context[:title],
            head: pr_context[:head],
            base: pr_context[:base]
          },
          metadata: {
            node_id: @node.node_id,
            node_type: "git_pull_request",
            executed_at: Time.current.iso8601,
            failed: true,
            error: error.message
          }
        }
      end
    end
  end
end
