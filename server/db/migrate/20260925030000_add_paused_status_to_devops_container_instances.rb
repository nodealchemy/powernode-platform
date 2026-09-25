# frozen_string_literal: true

# Ai::Runtime::SandboxManagerService#pause_sandbox has always written
# status: "paused" to a Devops::ContainerInstance, but neither the model's
# STATUSES inclusion list nor this DB-level check constraint ever allowed it —
# every real pause has raised (masked in the controller's rescue as a generic
# error). Add "paused" to both so pause/resume actually persist.
class AddPausedStatusToDevopsContainerInstances < ActiveRecord::Migration[8.0]
  WITHOUT = %w[pending provisioning running completed failed cancelled timeout].freeze
  WITH = %w[pending provisioning running paused completed failed cancelled timeout].freeze
  CONSTRAINT = "mcp_instances_status_check"

  def up
    swap_status_constraint(WITH)
  end

  def down
    # Remap any paused row before the constraint stops allowing it — WITHOUT
    # is the real STATUSES list this migration is undoing, and it would
    # otherwise leave existing "paused" rows violating the just-restored
    # constraint (irrecoverable without a manual UPDATE, since the app code
    # rolled back too and no longer understands "paused").
    execute("UPDATE devops_container_instances SET status = 'cancelled' WHERE status = 'paused'")
    swap_status_constraint(WITHOUT)
  end

  private

  def swap_status_constraint(statuses)
    remove_check_constraint :devops_container_instances, name: CONSTRAINT
    list = statuses.map { |s| "'#{s}'::character varying::text" }.join(", ")
    add_check_constraint :devops_container_instances, "status::text = ANY (ARRAY[#{list}])", name: CONSTRAINT
  end
end
