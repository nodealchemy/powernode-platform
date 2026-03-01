# frozen_string_literal: true

module Ai
  module DevopsBridge
    class CodeReviewAgent
      include Ai::Concerns::PromptTemplateLookup

      REVIEW_DIMENSIONS = %w[security performance correctness style].freeze
      PROMPT_SLUG = "ai-code-review-dimension"
      FALLBACK_PROMPT = <<~LIQUID
        Review the following pull request diff focusing on {{ dimension }} issues.

        Repository: {{ repository_name }}
        PR Title: {{ pr_title }}
        PR Description: {{ pr_description }}

        Diff:
        {{ diff }}

        Provide specific, actionable feedback for any {{ dimension }} issues found.
        Format each finding as: [SEVERITY] file:line - description
      LIQUID

      def initialize(account:)
        @account = account
      end

      def review_pull_request(repository:, pr_number:, options: {})
        context = PrContextBuilder.new(
          account: @account,
          repository: repository,
          pr_number: pr_number
        ).build

        return { error: "Could not fetch PR context" } unless context

        results = REVIEW_DIMENSIONS.map do |dimension|
          review_dimension(context, dimension, options)
        end.compact

        {
          pr_number: pr_number,
          repository: repository.name,
          reviews: results,
          summary: generate_summary(results),
          reviewed_at: Time.current.iso8601
        }
      end

      private

      def review_dimension(context, dimension, options)
        agent = find_review_agent(dimension)
        return nil unless agent

        prompt = build_review_prompt(context, dimension)

        execution = execute_agent(agent, prompt)
        return nil unless execution

        {
          dimension: dimension,
          agent_id: agent.id,
          agent_name: agent.name,
          findings: execution[:output],
          severity: classify_severity(execution[:output])
        }
      rescue => e
        Rails.logger.error "[CodeReviewAgent] #{dimension} review failed: #{e.message}"
        nil
      end

      def find_review_agent(dimension)
        # Look for agents tagged with code review capability
        Ai::Agent.where(account: @account)
                 .where("system_prompt ILIKE ?", "%code review%")
                 .where("system_prompt ILIKE ?", "%#{dimension}%")
                 .first ||
          Ai::Agent.where(account: @account, status: "active").first
      end

      def build_review_prompt(context, dimension)
        resolve_prompt_template(
          PROMPT_SLUG,
          account: @account,
          variables: {
            dimension: dimension,
            repository_name: context[:repository_name],
            pr_title: context[:title],
            pr_description: context[:description],
            diff: context[:diff].truncate(8000)
          },
          fallback: FALLBACK_PROMPT
        )
      end

      def execute_agent(agent, prompt)
        service = Ai::AgentOrchestrationService.new(account: @account)
        result = service.execute_agent(
          agent: agent,
          input: prompt,
          trigger_type: "code_review"
        )

        { output: result[:output] || result[:response] }
      rescue => e
        Rails.logger.error "[CodeReviewAgent] Agent execution failed: #{e.message}"
        nil
      end

      def classify_severity(output)
        return "info" unless output

        output_lower = output.to_s.downcase
        if output_lower.include?("[critical]") || output_lower.include?("vulnerability")
          "critical"
        elsif output_lower.include?("[warning]") || output_lower.include?("[high]")
          "warning"
        else
          "info"
        end
      end

      def generate_summary(results)
        total = results.size
        critical = results.count { |r| r[:severity] == "critical" }
        warnings = results.count { |r| r[:severity] == "warning" }

        "Reviewed #{total} dimensions. #{critical} critical, #{warnings} warnings."
      end
    end
  end
end
