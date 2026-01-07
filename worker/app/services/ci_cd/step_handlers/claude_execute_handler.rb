# frozen_string_literal: true

module CiCd
  module StepHandlers
    # Handles Claude Code execution steps
    class ClaudeExecuteHandler < Base
      # Execute Claude Code step
      # @param config [Hash] Step configuration
      # @param context [Hash] Execution context
      # @param previous_outputs [Hash] Outputs from previous steps
      # @return [Hash] Result with :outputs and :logs keys
      def execute(config:, context:, previous_outputs: {})
        logs = []
        logs << log_info("Starting Claude execute step")

        # Get prompt from config or template
        prompt = build_prompt(config, context, previous_outputs)

        # Determine working directory
        workspace = previous_outputs.dig("checkout", :workspace) ||
                    config["working_directory"] ||
                    Dir.pwd

        logs << log_info("Executing Claude Code", model: config["model"], workspace: workspace)

        # Build and execute Claude command
        result = execute_claude(prompt, config, workspace)

        if result[:success]
          logs << log_info("Claude execution completed successfully")

          # Parse structured output if expected
          parsed_output = parse_output(result[:output], config)

          {
            outputs: {
              raw_output: result[:output],
              parsed: parsed_output,
              exit_code: result[:exit_code]
            },
            logs: logs.join("\n") + "\n\n--- Claude Output ---\n" + result[:output]
          }
        else
          logs << log_error("Claude execution failed", exit_code: result[:exit_code])

          raise StandardError, "Claude execution failed: #{result[:error]}"
        end
      end

      private

      def build_prompt(config, context, previous_outputs)
        # Get base prompt from config
        prompt = config["prompt"]

        # If prompt template ID is provided, fetch and render it
        if config["prompt_template_id"].present?
          prompt = fetch_and_render_template(
            config["prompt_template_id"],
            context,
            previous_outputs
          )
        end

        # Interpolate variables
        variables = build_variables(context, previous_outputs)
        interpolate(prompt, variables)
      end

      def fetch_and_render_template(template_id, context, previous_outputs)
        response = api_client.post("/api/v1/internal/ci_cd/prompt_templates/#{template_id}/render", {
          variables: build_variables(context, previous_outputs)
        })
        response.dig("data", "rendered_content")
      end

      def build_variables(context, previous_outputs)
        variables = {
          "context" => context,
          "previous_outputs" => previous_outputs
        }

        # Add trigger context variables
        trigger = context[:trigger_context] || {}
        variables.merge!(
          "pr_number" => trigger[:pr_number],
          "pr_title" => trigger[:pr_title],
          "pr_body" => trigger[:pr_body],
          "issue_number" => trigger[:issue_number],
          "issue_title" => trigger[:issue_title],
          "issue_body" => trigger[:issue_body],
          "branch" => trigger[:head_branch] || trigger[:ref],
          "commit_sha" => trigger[:head_sha] || trigger[:after],
          "repository" => trigger[:repository]
        )

        # Add diff if available
        if previous_outputs.dig("get_diff", :diff)
          variables["diff"] = previous_outputs.dig("get_diff", :diff)
        end

        variables.compact
      end

      def execute_claude(prompt, config, workspace)
        cmd_parts = ["claude", "--print"]

        # Add model if specified
        if config["model"].present?
          cmd_parts << "--model"
          cmd_parts << config["model"]
        end

        # Add session ID if specified
        if config["session_id"].present?
          cmd_parts << "--session-id"
          cmd_parts << config["session_id"]
        end

        full_command = cmd_parts.join(" ")
        timeout = (config["timeout_minutes"]&.to_i || 10) * 60

        output = nil
        error_output = nil
        exit_status = nil

        Open3.popen3(full_command, chdir: workspace) do |stdin, stdout, stderr, wait_thr|
          stdin.write(prompt)
          stdin.close

          begin
            Timeout.timeout(timeout) do
              output = stdout.read
              error_output = stderr.read
              exit_status = wait_thr.value
            end
          rescue Timeout::Error
            Process.kill("TERM", wait_thr.pid) rescue nil
            return {
              success: false,
              output: output,
              error: "Claude command timed out after #{timeout}s",
              exit_code: -1
            }
          end
        end

        {
          success: exit_status&.success?,
          output: output,
          error: error_output,
          exit_code: exit_status&.exitstatus || 1
        }
      end

      def parse_output(output, config)
        return nil unless config["parse_json"]

        # Try to extract JSON from the output
        json_match = output.match(/```json\s*([\s\S]*?)```/) ||
                     output.match(/\{[\s\S]*\}/)

        return nil unless json_match

        json_content = json_match[1] || json_match[0]
        JSON.parse(json_content)
      rescue JSON::ParserError => e
        log_warn("Failed to parse JSON output", exception: e.message)
        nil
      end
    end
  end
end
