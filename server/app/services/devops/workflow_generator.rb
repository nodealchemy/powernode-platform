# frozen_string_literal: true

module Devops
  # Generates Gitea Actions workflow YAML from pipeline definitions
  class WorkflowGenerator
    attr_reader :pipeline

    def initialize(pipeline)
      @pipeline = pipeline
    end

    def generate
      {
        name: pipeline.name,
        on: generate_triggers,
        env: generate_environment_variables,
        jobs: generate_jobs
      }.deep_stringify_keys.to_yaml
    end

    private

    def generate_triggers
      triggers = pipeline.triggers || {}
      result = {}

      # Pull request trigger
      if triggers["pull_request"].present?
        result["pull_request"] = {
          "types" => Array(triggers["pull_request"])
        }
      end

      # Push trigger
      if triggers["push"].present?
        result["push"] = {
          "branches" => Array(triggers["push"]["branches"])
        }.compact
      end

      # Issue trigger
      if triggers["issues"].present?
        result["issues"] = {
          "types" => Array(triggers["issues"])
        }
      end

      # Issue comment trigger
      if triggers["issue_comment"].present?
        result["issue_comment"] = {
          "types" => Array(triggers["issue_comment"])
        }
      end

      # Schedule trigger (cron)
      if triggers["schedule"].present?
        result["schedule"] = Array(triggers["schedule"]).map do |cron|
          { "cron" => cron }
        end
      end

      # Manual dispatch
      if triggers["workflow_dispatch"].present? || triggers["manual"]
        result["workflow_dispatch"] = triggers["workflow_dispatch"] || {}
      end

      # Release trigger
      if triggers["release"].present?
        result["release"] = {
          "types" => Array(triggers["release"])
        }
      end

      result
    end

    def generate_environment_variables
      env = {}

      # AI configuration environment variables
      if pipeline.ai_config.present?
        env.merge!(pipeline.ai_config.environment_variables)
      end

      # Pipeline-specific settings
      settings = pipeline.settings || {}
      if settings["environment"]
        env.merge!(settings["environment"])
      end

      env.presence
    end

    def generate_jobs
      {
        "run-pipeline" => generate_main_job
      }
    end

    def generate_main_job
      job = {
        "runs-on" => determine_runner,
        "steps" => generate_steps
      }

      # Add container configuration if using Claude Code
      if uses_claude_code?
        job["container"] = generate_container_config
      end

      # Add environment if specified
      if pipeline.settings&.dig("environment_name").present?
        job["environment"] = pipeline.settings["environment_name"]
      end

      # Add permissions if needed
      if pipeline.settings&.dig("permissions").present?
        job["permissions"] = pipeline.settings["permissions"]
      end

      job
    end

    def determine_runner
      pipeline.settings&.dig("runner") || "ubuntu-latest"
    end

    def uses_claude_code?
      pipeline.pipeline_steps.any? { |step| step.step_type == "claude_execute" }
    end

    def generate_container_config
      {
        "image" => container_image,
        "env" => generate_container_env,
        "volumes" => generate_container_volumes
      }
    end

    def container_image
      pipeline.settings&.dig("container_image") ||
        "ghcr.io/#{pipeline.settings&.dig('registry_org') || 'powernode'}/claude-code:latest"
    end

    def generate_container_env
      env = {}

      if pipeline.ai_config.present?
        env.merge!(pipeline.ai_config.environment_variables)
      end

      # Add Gitea token reference
      env["GITEA_TOKEN"] = "${{ secrets.GITEA_TOKEN }}"

      env
    end

    def generate_container_volumes
      [
        "claude-sessions:/home/claude/.claude/sessions",
        "claude-memory:/home/claude/.claude/memory",
        "claude-cache:/home/claude/.cache"
      ]
    end

    def generate_steps
      steps = []

      # Always start with checkout
      steps << generate_checkout_step

      # Generate steps from pipeline definition
      pipeline.pipeline_steps.order(:position).each do |step|
        next unless step.is_enabled?

        steps << generate_step(step)
      end

      steps
    end

    def generate_checkout_step
      {
        "name" => "Checkout repository",
        "uses" => "actions/checkout@v4",
        "with" => {
          "fetch-depth" => 0
        }
      }
    end

    def generate_step(pipeline_step)
      case pipeline_step.step_type
      when "claude_execute"
        generate_claude_step(pipeline_step)
      when "post_comment"
        generate_comment_step(pipeline_step)
      when "create_pr"
        generate_create_pr_step(pipeline_step)
      when "deploy"
        generate_deploy_step(pipeline_step)
      when "run_command"
        generate_run_command_step(pipeline_step)
      when "upload_artifact"
        generate_upload_artifact_step(pipeline_step)
      else
        generate_generic_step(pipeline_step)
      end
    end

    def generate_claude_step(step)
      config = step.config || {}

      result = {
        "name" => step.name,
        "id" => step.slug,
        "run" => generate_claude_command(step)
      }

      # Add environment variables
      if config["env"].present?
        result["env"] = config["env"]
      end

      # Add timeout
      if config["timeout_minutes"].present?
        result["timeout-minutes"] = config["timeout_minutes"].to_i
      end

      result
    end

    def generate_claude_command(step)
      config = step.config || {}

      # Get prompt from template or inline
      prompt = if step.prompt_template.present?
                 step.prompt_template.content
               else
                 config["prompt"] || ""
               end

      # Build the Claude command
      cmd = ["claude --print"]

      # Add model if specified
      if config["model"].present?
        cmd << "--model #{config['model']}"
      end

      # Add the prompt
      cmd << "\"$(cat <<'PROMPT'\n#{prompt}\nPROMPT\n)\""

      # Output to file if specified
      if config["output_file"].present?
        cmd << "> #{config['output_file']}"
      end

      cmd.join(" ")
    end

    def generate_comment_step(step)
      config = step.config || {}

      {
        "name" => step.name,
        "uses" => "actions/github-script@v7",
        "with" => {
          "github-token" => "${{ secrets.GITEA_TOKEN }}",
          "script" => generate_comment_script(config)
        }
      }
    end

    def generate_comment_script(config)
      body_source = config["body_file"].present? ?
        "fs.readFileSync('#{config['body_file']}', 'utf8')" :
        "'#{config['body']}'"

      <<~SCRIPT
        const fs = require('fs');
        const body = #{body_source};

        await github.rest.issues.createComment({
          owner: context.repo.owner,
          repo: context.repo.repo,
          issue_number: context.issue.number,
          body: body
        });
      SCRIPT
    end

    def generate_create_pr_step(step)
      config = step.config || {}

      {
        "name" => step.name,
        "env" => {
          "GITEA_TOKEN" => "${{ secrets.GITEA_TOKEN }}"
        },
        "run" => <<~SCRIPT
          git push -u origin "${BRANCH:-$(git branch --show-current)}"

          curl -X POST \\
            -H "Authorization: token $GITEA_TOKEN" \\
            -H "Content-Type: application/json" \\
            "${{ gitea.server_url }}/api/v1/repos/${{ gitea.repository }}/pulls" \\
            -d '{
              "title": "#{config['title'] || '${{ gitea.event.issue.title }}'}",
              "body": "#{config['body'] || 'AI-generated PR'}",
              "head": "'$(git branch --show-current)'",
              "base": "#{config['base'] || 'develop'}"
            }'
        SCRIPT
      }
    end

    def generate_deploy_step(step)
      config = step.config || {}

      {
        "name" => step.name,
        "run" => config["command"] || "./scripts/deploy.sh #{config['environment'] || 'staging'}"
      }
    end

    def generate_run_command_step(step)
      config = step.config || {}

      result = {
        "name" => step.name,
        "run" => config["command"]
      }

      if config["working_directory"].present?
        result["working-directory"] = config["working_directory"]
      end

      result
    end

    def generate_upload_artifact_step(step)
      config = step.config || {}

      {
        "name" => step.name,
        "uses" => "actions/upload-artifact@v4",
        "with" => {
          "name" => config["artifact_name"] || "build-artifacts",
          "path" => config["path"] || ".",
          "retention-days" => config["retention_days"] || 30
        }
      }
    end

    def generate_generic_step(step)
      config = step.config || {}

      result = {
        "name" => step.name
      }

      if config["uses"].present?
        result["uses"] = config["uses"]
        result["with"] = config["with"] if config["with"].present?
      elsif config["run"].present?
        result["run"] = config["run"]
      end

      result
    end
  end
end
