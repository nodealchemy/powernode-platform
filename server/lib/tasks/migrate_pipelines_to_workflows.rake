# frozen_string_literal: true

namespace :pipelines do
  desc "Migrate CI/CD pipelines to AI Workflow format (unified workflow system)"
  task migrate_to_workflows: :environment do
    puts "Starting pipeline migration to unified workflow system..."

    migrated_count = 0
    error_count = 0
    skipped_count = 0

    CiCd::Pipeline.find_each do |pipeline|
      begin
        # Check if already migrated (workflow exists with same slug)
        existing_workflow = AiWorkflow.find_by(
          account_id: pipeline.account_id,
          slug: "cicd-#{pipeline.slug}",
          workflow_type: "cicd"
        )

        if existing_workflow
          puts "  Skipping #{pipeline.name} - already migrated"
          skipped_count += 1
          next
        end

        puts "Migrating pipeline: #{pipeline.name}"

        # Create the workflow
        workflow = AiWorkflow.new(
          account_id: pipeline.account_id,
          creator_id: pipeline.created_by_id,
          name: pipeline.name,
          slug: "cicd-#{pipeline.slug}",
          description: pipeline.description,
          status: pipeline.is_active ? "active" : "inactive",
          visibility: "private",
          workflow_type: "cicd",
          is_template: false,
          version: "1.0.0",
          is_active: pipeline.is_active,
          configuration: {
            "execution_mode" => "sequential",
            "timeout_seconds" => (pipeline.timeout_minutes || 60) * 60,
            "allow_concurrent" => pipeline.allow_concurrent,
            "pipeline_type" => pipeline.pipeline_type,
            "triggers" => pipeline.triggers,
            "environment" => pipeline.environment,
            "secret_refs" => pipeline.secret_refs,
            "runner_labels" => pipeline.runner_labels,
            "notification_recipients" => pipeline.notification_recipients,
            "notification_settings" => pipeline.notification_settings,
            "original_pipeline_id" => pipeline.id
          },
          metadata: {
            "migrated_from" => "ci_cd_pipeline",
            "migrated_at" => Time.current.iso8601,
            "original_pipeline_id" => pipeline.id,
            "features" => pipeline.features
          }
        )

        # Skip validation temporarily to create workflow first
        workflow.save!(validate: false)

        # Convert linear steps to nodes + edges
        nodes = []
        edges = []
        steps = pipeline.steps || []

        # Add start node
        start_node_id = SecureRandom.uuid
        nodes << {
          node_id: start_node_id,
          node_type: "start",
          name: "Start",
          description: "Pipeline start",
          position_x: 0,
          position_y: 0,
          is_start_node: true,
          is_end_node: false,
          configuration: PipelineMigrationHelpers.build_node_configuration("start", nil, pipeline.account),
          metadata: {}
        }

        # Convert each step to a node
        previous_node_id = start_node_id
        steps.each_with_index do |step, index|
          node_id = SecureRandom.uuid
          node_type = PipelineMigrationHelpers.map_step_type_to_node_type(step["step_type"])
          node_config = PipelineMigrationHelpers.build_node_configuration(
            node_type,
            step["configuration"],
            pipeline.account
          )

          node = {
            node_id: node_id,
            node_type: node_type,
            name: step["name"] || "Step #{index + 1}",
            description: step["description"] || "",
            position_x: 0,
            position_y: (index + 1) * 150,
            is_start_node: false,
            is_end_node: false,
            timeout_seconds: step["timeout_seconds"] || 300,
            configuration: node_config,
            metadata: {
              "original_step_id" => step["id"],
              "original_step_type" => step["step_type"],
              "condition" => step["condition"],
              "continue_on_error" => step["continue_on_error"],
              "requires_approval" => step["requires_approval"],
              "approval_settings" => step["approval_settings"]
            }
          }
          nodes << node

          # Create edge from previous node
          edges << {
            edge_id: SecureRandom.uuid,
            source_node_id: previous_node_id,
            target_node_id: node_id,
            edge_type: "default",
            metadata: {}
          }

          previous_node_id = node_id
        end

        # Add end node
        end_node_id = SecureRandom.uuid
        nodes << {
          node_id: end_node_id,
          node_type: "end",
          name: "End",
          description: "Pipeline end",
          position_x: 0,
          position_y: nodes.length * 150,
          is_start_node: false,
          is_end_node: true,
          configuration: PipelineMigrationHelpers.build_node_configuration("end", nil, pipeline.account),
          metadata: {}
        }

        # Connect last step to end
        edges << {
          edge_id: SecureRandom.uuid,
          source_node_id: previous_node_id,
          target_node_id: end_node_id,
          edge_type: "default",
          metadata: {}
        }

        # Create nodes
        nodes.each do |node_attrs|
          workflow.ai_workflow_nodes.create!(
            node_id: node_attrs[:node_id],
            node_type: node_attrs[:node_type],
            name: node_attrs[:name],
            description: node_attrs[:description] || "",
            position: { x: node_attrs[:position_x], y: node_attrs[:position_y] },
            is_start_node: node_attrs[:is_start_node],
            is_end_node: node_attrs[:is_end_node],
            timeout_seconds: node_attrs[:timeout_seconds] || 300,
            retry_count: 0,
            configuration: node_attrs[:configuration] || {},
            metadata: node_attrs[:metadata] || {}
          )
        end

        # Create edges
        edges.each do |edge_attrs|
          workflow.ai_workflow_edges.create!(
            edge_id: edge_attrs[:edge_id],
            source_node_id: edge_attrs[:source_node_id],
            target_node_id: edge_attrs[:target_node_id],
            edge_type: edge_attrs[:edge_type],
            metadata: edge_attrs[:metadata] || {}
          )
        end

        # Create triggers based on pipeline triggers
        PipelineMigrationHelpers.create_workflow_triggers(workflow, pipeline.triggers)

        puts "  Successfully migrated: #{pipeline.name} -> #{workflow.slug}"
        migrated_count += 1

      rescue StandardError => e
        puts "  ERROR migrating #{pipeline.name}: #{e.message}"
        puts "  Backtrace: #{e.backtrace.first(5).join("\n")}"
        error_count += 1
      end
    end

    puts "\n=== Migration Complete ==="
    puts "Migrated: #{migrated_count}"
    puts "Skipped:  #{skipped_count}"
    puts "Errors:   #{error_count}"
  end

  desc "Dry run - show what would be migrated"
  task migrate_to_workflows_dry_run: :environment do
    puts "DRY RUN - Pipeline Migration Analysis"
    puts "=" * 50

    CiCd::Pipeline.find_each do |pipeline|
      existing = AiWorkflow.find_by(
        account_id: pipeline.account_id,
        slug: "cicd-#{pipeline.slug}",
        workflow_type: "cicd"
      )

      status = existing ? "SKIP (exists)" : "MIGRATE"
      step_count = (pipeline.steps || []).length

      puts "#{status}: #{pipeline.name}"
      puts "  Account: #{pipeline.account_id}"
      puts "  Steps: #{step_count}"
      puts "  Type: #{pipeline.pipeline_type}"
      puts ""
    end
  end

end

# Helper module for pipeline migration
module PipelineMigrationHelpers
  module_function

  def map_step_type_to_node_type(step_type)
    mapping = {
      "checkout" => "git_checkout",
      "claude_execute" => "ai_agent",
      "ai_workflow" => "sub_workflow",
      "create_branch" => "git_branch",
      "create_pr" => "git_pull_request",
      "deploy" => "deploy",
      "run_tests" => "run_tests",
      "post_comment" => "git_comment",
      "upload_artifact" => "file",
      "download_artifact" => "file",
      "notify" => "notification",
      "custom" => "shell_command"
    }

    mapping[step_type] || "shell_command"
  end

  # Build valid configuration for each node type
  def build_node_configuration(node_type, step_config, account)
    step_config ||= {}

    case node_type
    when "start", "end"
      { "migrated" => true }
    when "ai_agent"
      # Find or use existing agent_id, fallback to first available agent
      agent_id = step_config["agent_id"] || account.ai_agents.first&.id
      {
        "agent_id" => agent_id,
        "prompt" => step_config["prompt"] || step_config["instructions"] || "",
        "model" => step_config["model"] || "claude-sonnet-4-20250514",
        "migrated_from" => "claude_execute"
      }.merge(step_config.except("agent_id", "prompt", "model"))
    when "git_checkout"
      {
        "repository" => step_config["repository"] || "${{ trigger.repository }}",
        "ref" => step_config["ref"] || "${{ trigger.ref }}",
        "fetch_depth" => step_config["fetch_depth"] || 1,
        "submodules" => step_config["submodules"] || false
      }.merge(step_config)
    when "git_branch"
      {
        "branch_name" => step_config["branch_name"] || "${{ inputs.branch_name }}",
        "base_branch" => step_config["base_branch"] || "main"
      }.merge(step_config)
    when "git_pull_request"
      {
        "title" => step_config["title"] || "${{ inputs.pr_title }}",
        "body" => step_config["body"] || "",
        "base" => step_config["base"] || "main",
        "draft" => step_config["draft"] || false
      }.merge(step_config)
    when "git_comment"
      {
        "comment_body" => step_config["comment_body"] || step_config["message"] || "",
        "target_type" => step_config["target_type"] || "pull_request"
      }.merge(step_config)
    when "deploy"
      {
        "environment" => step_config["environment"] || "staging",
        "strategy" => step_config["strategy"] || "rolling"
      }.merge(step_config)
    when "run_tests"
      {
        "test_command" => step_config["test_command"] || step_config["command"] || "npm test",
        "test_framework" => step_config["test_framework"] || "auto"
      }.merge(step_config)
    when "shell_command"
      {
        "command" => step_config["command"] || step_config["script"] || "echo 'No command specified'",
        "working_directory" => step_config["working_directory"] || "."
      }.merge(step_config)
    when "notification"
      {
        "channel" => step_config["channel"] || "email",
        "recipients" => step_config["recipients"] || [],
        "message" => step_config["message"] || ""
      }.merge(step_config)
    when "file"
      {
        "action" => step_config["action"] || "read",
        "path" => step_config["path"] || ""
      }.merge(step_config)
    when "sub_workflow"
      {
        "workflow_id" => step_config["workflow_id"],
        "inputs" => step_config["inputs"] || {}
      }.merge(step_config)
    when "condition"
      {
        "conditions" => step_config["conditions"] || [{ "field" => "status", "operator" => "equals", "value" => "success" }]
      }.merge(step_config)
    when "delay"
      {
        "delay_type" => step_config["delay_type"] || "fixed",
        "delay_seconds" => step_config["delay_seconds"] || 60
      }.merge(step_config)
    when "human_approval"
      {
        "approvers" => step_config["approvers"] || ["${{ workflow.creator }}"],
        "timeout_hours" => step_config["timeout_hours"] || 24
      }.merge(step_config)
    else
      # Generic fallback - ensure non-empty
      step_config.presence || { "migrated" => true }
    end
  end

  def create_workflow_triggers(workflow, triggers)
    return unless triggers.present?

    # Manual trigger
    if triggers["manual"]
      workflow.ai_workflow_triggers.create!(
        trigger_type: "manual",
        name: "Manual Trigger",
        is_active: true,
        configuration: { "migrated" => true },
        conditions: {},
        metadata: { "migrated_from" => "ci_cd_pipeline" }
      )
    end

    # Schedule trigger
    if triggers["schedule"].present?
      Array(triggers["schedule"]).each_with_index do |cron, index|
        workflow.ai_workflow_triggers.create!(
          trigger_type: "schedule",
          name: "Schedule #{index + 1}",
          is_active: true,
          schedule_cron: cron.is_a?(String) ? cron : cron["cron"],
          configuration: { "cron_expression" => cron },
          conditions: {},
          metadata: { "migrated_from" => "ci_cd_pipeline" }
        )
      end
    end

    # Git push trigger
    if triggers["push"].present?
      push_config = triggers["push"]
      branches = push_config.is_a?(Hash) ? push_config["branches"] : nil
      workflow.ai_workflow_triggers.create!(
        trigger_type: "event",
        name: "Git Push",
        is_active: true,
        configuration: {
          "event_type" => "git",
          "event_types" => ["git_push"],
          "branches" => branches || ["main", "develop"]
        },
        conditions: {},
        metadata: { "migrated_from" => "ci_cd_pipeline" }
      )
    end

    # Pull request trigger
    if triggers["pull_request"].present?
      pr_config = triggers["pull_request"]
      pr_events = pr_config.is_a?(Array) ? pr_config : ["opened", "synchronize"]
      workflow.ai_workflow_triggers.create!(
        trigger_type: "event",
        name: "Pull Request",
        is_active: true,
        configuration: {
          "event_type" => "git",
          "event_types" => ["git_pull_request"],
          "pr_events" => pr_events
        },
        conditions: {},
        metadata: { "migrated_from" => "ci_cd_pipeline" }
      )
    end

    # Webhook/API trigger - use api_call type since webhook requires URL
    if triggers["workflow_dispatch"].present?
      dispatch_config = triggers["workflow_dispatch"].is_a?(Hash) ? triggers["workflow_dispatch"] : {}
      workflow.ai_workflow_triggers.create!(
        trigger_type: "api_call",
        name: "API Dispatch",
        is_active: true,
        configuration: {
          "method" => "POST",
          "enabled" => true,
          "inputs" => dispatch_config["inputs"] || {}
        },
        conditions: {},
        metadata: { "migrated_from" => "ci_cd_pipeline", "original_type" => "workflow_dispatch" }
      )
    end
  end
end
