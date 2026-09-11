# frozen_string_literal: true

# Widens devops_swarm_deployments.status to allow "partially_converged" —
# stack_deploy_job.rb and service_update_job.rb (worker/app/jobs/swarm/) send
# it when a deployment's convergence wait times out but some services did
# come up, distinct from both a clean "completed" and an outright "failed".
# Devops::SwarmDeployment::STATUSES already lists it; the DB check constraint
# did not, so #partially_converge! raised ActiveRecord::StatementInvalid.
class AddPartiallyConvergedToSwarmDeploymentsStatus < ActiveRecord::Migration[8.0]
  OLD_STATUSES = %w[pending running completed failed cancelled].freeze
  NEW_STATUSES = %w[pending running completed partially_converged failed cancelled].freeze
  CONSTRAINT = "swarm_deployments_status_check"

  def up
    swap_status_constraint(NEW_STATUSES)
  end

  def down
    swap_status_constraint(OLD_STATUSES)
  end

  private

  def swap_status_constraint(statuses)
    remove_check_constraint :devops_swarm_deployments, name: CONSTRAINT
    add_check_constraint :devops_swarm_deployments, status_expression(statuses), name: CONSTRAINT
  end

  def status_expression(statuses)
    list = statuses.map { |s| "'#{s}'::character varying::text" }.join(", ")
    "status::text = ANY (ARRAY[#{list}])"
  end
end
