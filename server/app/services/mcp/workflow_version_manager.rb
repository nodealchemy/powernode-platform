# frozen_string_literal: true

module Mcp
  # Manages workflow versioning, migration, and safe updates
  # Enables side-by-side execution of different workflow versions
  class WorkflowVersionManager
    attr_reader :workflow, :account, :user

    def initialize(workflow:, account:, user:)
      @workflow = workflow
      @account = account
      @user = user
    end

    # Create a new version of the workflow
    def create_version(changes:, change_summary: nil)
      new_version = calculate_next_version(changes[:version_type] || :patch)

      ActiveRecord::Base.transaction do
        # Deactivate current version if requested
        workflow.update!(is_active: false) if changes[:replace_active]

        # Create new version
        new_workflow = workflow.dup
        new_workflow.assign_attributes(
          version: new_version,
          parent_version_id: workflow.id,
          is_active: true,
          change_summary: change_summary || "Version #{new_version}",
          version_metadata: {
            created_by: user.id,
            created_at: Time.current.iso8601,
            changes: changes,
            migration_strategy: changes[:migration_strategy] || "immediate"
          }
        )

        # Apply changes to workflow structure
        apply_workflow_changes(new_workflow, changes)

        new_workflow.save!

        # Copy nodes and edges if requested
        if changes[:copy_structure]
          copy_workflow_structure(workflow, new_workflow)
        end

        # Log version creation
        Rails.logger.info "Created workflow version #{new_version} from #{workflow.version}"

        new_workflow
      end
    end

    # Migrate running workflows from old to new version
    def migrate_running_workflows(to_version:, strategy: :graceful)
      target_workflow = find_version(to_version)
      raise ArgumentError, "Target version #{to_version} not found" unless target_workflow

      running_workflows = AiWorkflowRun.where(ai_workflow_id: workflow.id, status: "running")

      case strategy
      when :graceful
        migrate_gracefully(running_workflows, target_workflow)
      when :immediate
        migrate_immediately(running_workflows, target_workflow)
      when :checkpoint
        migrate_with_checkpoint(running_workflows, target_workflow)
      else
        raise ArgumentError, "Unknown migration strategy: #{strategy}"
      end
    end

    # Rollback to a previous version
    def rollback_to_version(target_version)
      target_workflow = find_version(target_version)
      raise ArgumentError, "Target version #{target_version} not found" unless target_workflow

      ActiveRecord::Base.transaction do
        # Deactivate current active version
        AiWorkflow.where(account_id: account.id, name: workflow.name, is_active: true)
                  .update_all(is_active: false)

        # Activate target version
        target_workflow.update!(is_active: true)

        Rails.logger.info "Rolled back workflow '#{workflow.name}' to version #{target_version}"

        target_workflow
      end
    end

    # Get version history
    def version_history
      AiWorkflow.where(account_id: account.id, name: workflow.name)
                .order(created_at: :desc)
                .map do |wf|
        {
          id: wf.id,
          version: wf.version,
          is_active: wf.is_active,
          change_summary: wf.change_summary,
          created_at: wf.created_at,
          created_by: wf.version_metadata&.dig("created_by"),
          parent_version_id: wf.parent_version_id,
          active_runs: wf.ai_workflow_runs.where(status: [ "running", "paused" ]).count
        }
      end
    end

    # Compare two versions
    def compare_versions(version_a, version_b)
      workflow_a = find_version(version_a)
      workflow_b = find_version(version_b)

      {
        version_a: version_a,
        version_b: version_b,
        node_changes: compare_nodes(workflow_a, workflow_b),
        edge_changes: compare_edges(workflow_a, workflow_b),
        configuration_changes: compare_configurations(workflow_a, workflow_b),
        metadata_changes: {
          trigger_type_changed: workflow_a.trigger_type != workflow_b.trigger_type,
          description_changed: workflow_a.description != workflow_b.description,
          configuration_changed: workflow_a.configuration != workflow_b.configuration
        }
      }
    end

    private

    # Calculate next version number based on semver
    def calculate_next_version(version_type)
      current = workflow.version.split(".").map(&:to_i)

      case version_type
      when :major
        "#{current[0] + 1}.0.0"
      when :minor
        "#{current[0]}.#{current[1] + 1}.0"
      when :patch
        "#{current[0]}.#{current[1]}.#{current[2] + 1}"
      else
        raise ArgumentError, "Unknown version type: #{version_type}"
      end
    end

    # Apply structural changes to new workflow version
    def apply_workflow_changes(new_workflow, changes)
      new_workflow.description = changes[:description] if changes[:description]
      new_workflow.trigger_type = changes[:trigger_type] if changes[:trigger_type]
      new_workflow.configuration = new_workflow.configuration.merge(changes[:configuration] || {})
    end

    # Copy workflow structure (nodes and edges) to new version
    def copy_workflow_structure(source, target)
      # Copy nodes
      source.ai_workflow_nodes.each do |node|
        new_node = node.dup
        new_node.ai_workflow_id = target.id
        new_node.save!
      end

      # Copy edges
      source.ai_workflow_edges.each do |edge|
        new_edge = edge.dup
        new_edge.ai_workflow_id = target.id
        new_edge.save!
      end
    end

    # Graceful migration: let current runs finish, new runs use new version
    def migrate_gracefully(running_workflows, target_workflow)
      # Just switch active version - running workflows continue on old version
      workflow.update!(is_active: false)
      target_workflow.update!(is_active: true)

      {
        strategy: "graceful",
        migrated_count: 0,
        continuing_on_old_version: running_workflows.count,
        message: "New runs will use version " + target_workflow.version
      }
    end

    # Immediate migration: pause and migrate at current checkpoint
    def migrate_immediately(running_workflows, target_workflow)
      migrated_count = 0

      running_workflows.each do |run|
        # Create checkpoint
        checkpoint = create_migration_checkpoint(run)

        # Switch to new workflow version
        run.update!(ai_workflow_id: target_workflow.id)

        migrated_count += 1
      rescue StandardError => e
        Rails.logger.error "Failed to migrate run #{run.run_id}: #{e.message}"
      end

      {
        strategy: "immediate",
        migrated_count: migrated_count,
        failed_count: running_workflows.count - migrated_count
      }
    end

    # Checkpoint migration: create checkpoint and migrate
    def migrate_with_checkpoint(running_workflows, target_workflow)
      migrated_count = 0

      running_workflows.each do |run|
        checkpoint = create_migration_checkpoint(run)

        if checkpoint
          run.update!(
            ai_workflow_id: target_workflow.id,
            status: "paused",
            runtime_context: run.runtime_context.merge(
              "migration_checkpoint_id" => checkpoint.id,
              "migrated_from_version" => workflow.version,
              "migrated_to_version" => target_workflow.version
            )
          )
          migrated_count += 1
        end
      rescue StandardError => e
        Rails.logger.error "Failed to migrate run #{run.run_id}: #{e.message}"
      end

      {
        strategy: "checkpoint",
        migrated_count: migrated_count,
        paused_count: migrated_count,
        message: "Workflows paused at checkpoint - resume to continue on new version"
      }
    end

    # Create a migration checkpoint for a workflow run
    def create_migration_checkpoint(run)
      AiWorkflowCheckpoint.create(
        ai_workflow_run: run,
        checkpoint_type: "manual_checkpoint",
        node_id: run.current_node_id || "migration",
        workflow_state: run.runtime_context["state"] || {},
        execution_context: run.runtime_context,
        variable_snapshot: run.runtime_context["variables"] || {},
        description: "Migration checkpoint: #{workflow.version} → target version",
        metadata: {
          migration: true,
          from_version: workflow.version,
          created_at: Time.current.iso8601
        }
      )
    end

    # Find a specific version
    def find_version(version)
      AiWorkflow.find_by(account_id: account.id, name: workflow.name, version: version)
    end

    # Compare nodes between versions
    def compare_nodes(workflow_a, workflow_b)
      nodes_a = workflow_a.ai_workflow_nodes.index_by(&:node_id)
      nodes_b = workflow_b.ai_workflow_nodes.index_by(&:node_id)

      {
        added: (nodes_b.keys - nodes_a.keys).map { |id| nodes_b[id].as_json },
        removed: (nodes_a.keys - nodes_b.keys).map { |id| nodes_a[id].as_json },
        modified: nodes_a.keys.intersection(nodes_b.keys).select do |id|
          nodes_a[id].configuration != nodes_b[id].configuration
        end.map { |id| { node_id: id, old: nodes_a[id].configuration, new: nodes_b[id].configuration } }
      }
    end

    # Compare edges between versions
    def compare_edges(workflow_a, workflow_b)
      edges_a = workflow_a.ai_workflow_edges.map { |e| [ e.source_node_id, e.target_node_id ] }
      edges_b = workflow_b.ai_workflow_edges.map { |e| [ e.source_node_id, e.target_node_id ] }

      {
        added: edges_b - edges_a,
        removed: edges_a - edges_b
      }
    end

    # Compare configurations
    def compare_configurations(workflow_a, workflow_b)
      config_a = workflow_a.configuration || {}
      config_b = workflow_b.configuration || {}

      {
        added_keys: config_b.keys - config_a.keys,
        removed_keys: config_a.keys - config_b.keys,
        modified_keys: config_a.keys.intersection(config_b.keys).select do |key|
          config_a[key] != config_b[key]
        end
      }
    end
  end
end
